#!/usr/bin/env bash
set -euo pipefail

AAB="${1:-}"
if [[ -z "${AAB}" || ! -f "${AAB}" ]]; then
  echo "Usage: EXPECTED_UPLOAD_CERT_SHA256=<fingerprint> $0 /path/to/release.aab" >&2
  echo "   or: GODOT_ANDROID_KEYSTORE_RELEASE_{PATH,USER,PASSWORD}=... $0 /path/to/release.aab" >&2
  exit 2
fi

if ! command -v bundletool >/dev/null 2>&1; then
  echo "ERROR: bundletool이 필요합니다." >&2
  exit 1
fi

JAVA_HOME_17="${JAVA_HOME_17:-/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home}"
if [[ ! -x "${JAVA_HOME_17}/bin/java" ]]; then
  echo "ERROR: bundletool 검증에 사용할 JDK 17을 찾을 수 없습니다." >&2
  exit 1
fi
if [[ ! -x "${JAVA_HOME_17}/bin/jarsigner" || ! -x "${JAVA_HOME_17}/bin/keytool" ]]; then
  echo "ERROR: AAB 서명을 검증할 JDK 17 jarsigner/keytool을 찾을 수 없습니다." >&2
  exit 1
fi

JAVA_HOME="${JAVA_HOME_17}" bundletool validate --bundle="${AAB}" >/dev/null
MANIFEST="$(JAVA_HOME="${JAVA_HOME_17}" bundletool dump manifest --bundle="${AAB}" --module=base)"
AAB_LISTING="$(unzip -l "${AAB}")"
AAB_ENTRIES="$(unzip -Z1 "${AAB}")"

set +e
SIGNATURE="$("${JAVA_HOME_17}/bin/jarsigner" \
  -J-Duser.language=en -J-Duser.country=US \
  -verify -verbose -certs "${AAB}" 2>&1)"
SIGNATURE_STATUS=$?
set -e
if [[ ${SIGNATURE_STATUS} -ne 0 ]] || ! grep -Eq '^jar verified([,.]|$)' <<<"${SIGNATURE}"; then
  echo "ERROR: AAB JAR 서명 검증에 실패했습니다." >&2
  exit 1
fi
if grep -Eqi 'jar is unsigned|contains unsigned entries' <<<"${SIGNATURE}" || \
   ! grep -Fq -- '- Signed by ' <<<"${SIGNATURE}"; then
  echo "ERROR: AAB가 서명되지 않았거나 일부 entry가 서명되지 않았습니다." >&2
  exit 1
fi

set +e
CERTIFICATE="$("${JAVA_HOME_17}/bin/keytool" \
  -J-Duser.language=en -J-Duser.country=US \
  -printcert -jarfile "${AAB}" 2>&1)"
CERTIFICATE_STATUS=$?
set -e
if [[ ${CERTIFICATE_STATUS} -ne 0 ]]; then
  echo "ERROR: AAB signer 인증서를 읽을 수 없습니다." >&2
  exit 1
fi
SIGNER_COUNT="$(grep -Ec '^Signer #[0-9]+:' <<<"${CERTIFICATE}" || true)"
if [[ "${SIGNER_COUNT}" != "1" ]]; then
  echo "ERROR: AAB가 정확히 하나의 인증서로 서명되지 않았습니다." >&2
  exit 1
fi
ACTUAL_FINGERPRINT="$(awk '/SHA256:/{sub(/^.*SHA256:[[:space:]]*/, ""); print; exit}' <<<"${CERTIFICATE}" | tr '[:lower:]' '[:upper:]' | tr -d ':[:space:]')"
if [[ ! "${ACTUAL_FINGERPRINT}" =~ ^[0-9A-F]{64}$ ]]; then
  echo "ERROR: AAB signer 인증서의 SHA-256 fingerprint를 읽을 수 없습니다." >&2
  exit 1
fi

if [[ -n "${EXPECTED_UPLOAD_CERT_SHA256:-}" ]]; then
  EXPECTED_FINGERPRINT="$(sed -E 's/^[Ss][Hh][Aa]-?256:[[:space:]]*//' <<<"${EXPECTED_UPLOAD_CERT_SHA256}" | tr '[:lower:]' '[:upper:]' | tr -d ':[:space:]')"
  EXPECTED_SOURCE="EXPECTED_UPLOAD_CERT_SHA256"
elif [[ -n "${GODOT_ANDROID_KEYSTORE_RELEASE_PATH:-}" && \
        -n "${GODOT_ANDROID_KEYSTORE_RELEASE_USER:-}" && \
        -n "${GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD:-}" ]]; then
  if [[ ! -f "${GODOT_ANDROID_KEYSTORE_RELEASE_PATH}" ]]; then
    echo "ERROR: upload keystore 파일을 찾을 수 없습니다." >&2
    exit 1
  fi
  set +e
  KEYSTORE_CERTIFICATE="$("${JAVA_HOME_17}/bin/keytool" \
    -J-Duser.language=en -J-Duser.country=US \
    -list -v \
    -keystore "${GODOT_ANDROID_KEYSTORE_RELEASE_PATH}" \
    -alias "${GODOT_ANDROID_KEYSTORE_RELEASE_USER}" \
    -storepass:env GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD 2>&1)"
  KEYSTORE_STATUS=$?
  set -e
  if [[ ${KEYSTORE_STATUS} -ne 0 ]]; then
    echo "ERROR: 환경 변수로 주입한 upload keystore 인증서를 읽을 수 없습니다." >&2
    exit 1
  fi
  EXPECTED_FINGERPRINT="$(awk '/SHA256:/{sub(/^.*SHA256:[[:space:]]*/, ""); print; exit}' <<<"${KEYSTORE_CERTIFICATE}" | tr '[:lower:]' '[:upper:]' | tr -d ':[:space:]')"
  EXPECTED_SOURCE="upload-keystore"
else
  echo "ERROR: signer identity pin이 없습니다." >&2
  echo "       EXPECTED_UPLOAD_CERT_SHA256 또는 release keystore PATH/USER/PASSWORD 환경 변수를 제공하세요." >&2
  exit 1
fi

if [[ ! "${EXPECTED_FINGERPRINT}" =~ ^[0-9A-F]{64}$ ]]; then
  echo "ERROR: 기대 upload certificate SHA-256 fingerprint 형식이 올바르지 않습니다." >&2
  exit 1
fi
if [[ "${ACTUAL_FINGERPRINT}" != "${EXPECTED_FINGERPRINT}" ]]; then
  echo "ERROR: AAB signer 인증서가 기대한 upload certificate와 다릅니다." >&2
  exit 1
fi

grep -Fq 'package="com.mrkimkim.dungeonoffice"' <<<"${MANIFEST}" || {
  echo "ERROR: application ID가 다릅니다." >&2
  exit 1
}
grep -Eq 'android:minSdkVersion="24"' <<<"${MANIFEST}" || {
  echo "ERROR: minSdk가 24가 아닙니다." >&2
  exit 1
}
grep -Eq 'android:targetSdkVersion="36"' <<<"${MANIFEST}" || {
  echo "ERROR: targetSdk가 36이 아닙니다." >&2
  exit 1
}

FORBIDDEN_PERMISSIONS=(
  android.permission.INTERNET
  android.permission.ACCESS_NETWORK_STATE
  android.permission.CHANGE_NETWORK_STATE
  android.permission.ACCESS_WIFI_STATE
  android.permission.CHANGE_WIFI_STATE
  android.permission.READ_EXTERNAL_STORAGE
  android.permission.WRITE_EXTERNAL_STORAGE
  android.permission.MANAGE_EXTERNAL_STORAGE
  android.permission.READ_MEDIA_IMAGES
  android.permission.READ_MEDIA_VIDEO
  android.permission.READ_MEDIA_AUDIO
  android.permission.REQUEST_INSTALL_PACKAGES
  android.permission.QUERY_ALL_PACKAGES
  android.permission.ACCESS_COARSE_LOCATION
  android.permission.ACCESS_FINE_LOCATION
  android.permission.ACCESS_BACKGROUND_LOCATION
  android.permission.READ_CONTACTS
  android.permission.WRITE_CONTACTS
  android.permission.GET_ACCOUNTS
  android.permission.CAMERA
  android.permission.RECORD_AUDIO
  android.permission.POST_NOTIFICATIONS
  android.permission.READ_PHONE_STATE
  android.permission.READ_PHONE_NUMBERS
  android.permission.CALL_PHONE
  android.permission.READ_CALL_LOG
  android.permission.WRITE_CALL_LOG
  android.permission.BODY_SENSORS
  android.permission.ACTIVITY_RECOGNITION
  com.android.vending.BILLING
  com.google.android.gms.permission.AD_ID
)
for permission in "${FORBIDDEN_PERMISSIONS[@]}"; do
  if grep -Fq "android:name=\"${permission}\"" <<<"${MANIFEST}"; then
    echo "ERROR: AAB가 금지 권한 ${permission}을 요청합니다." >&2
    exit 1
  fi
done

grep -Eq 'android:allowBackup="false"' <<<"${MANIFEST}" || {
  echo "ERROR: Android 자동 백업이 비활성화되지 않았습니다." >&2
  exit 1
}
grep -Eq 'android:isGame="true"' <<<"${MANIFEST}" || {
  echo "ERROR: android:isGame이 true가 아닙니다." >&2
  exit 1
}
grep -Eq 'android:appCategory="(0|game)"' <<<"${MANIFEST}" || {
  echo "ERROR: android:appCategory가 game이 아닙니다." >&2
  exit 1
}
grep -Fq 'android.intent.category.LAUNCHER' <<<"${MANIFEST}" || {
  echo "ERROR: launcher activity가 없습니다." >&2
  exit 1
}
if grep -Fq 'android.intent.category.HOME' <<<"${MANIFEST}"; then
  echo "ERROR: 일반 게임 AAB에 HOME launcher category가 포함되어 있습니다." >&2
  exit 1
fi

grep -Eq '^base/lib/arm64-v8a/[^/]+\.so$' <<<"${AAB_ENTRIES}" || {
  echo "ERROR: AAB에 arm64-v8a native library가 없습니다." >&2
  exit 1
}
if grep -Eq '^base/lib/(armeabi-v7a|x86|x86_64)/' <<<"${AAB_ENTRIES}"; then
  echo "ERROR: AAB에 MVP 범위 밖 ABI native library가 포함되어 있습니다." >&2
  exit 1
fi

DEX_ENTRIES="$(grep -E '^base/dex/classes([0-9]+)?\.dex$' <<<"${AAB_ENTRIES}" || true)"
if [[ -z "${DEX_ENTRIES}" ]]; then
  echo "ERROR: AAB base module에서 DEX를 찾을 수 없습니다." >&2
  exit 1
fi
FORBIDDEN_DEX_PATTERN='Lcom/android/billingclient/|Lcom/google/firebase/|Lcom/google/android/gms/(ads|analytics|measurement)/|Lcom/adjust/sdk/|Lcom/appsflyer/|Lcom/facebook/appevents/'
FORBIDDEN_DEX_HIT=""
while IFS= read -r dex_entry; do
  [[ -z "${dex_entry}" ]] && continue
  hit="$(unzip -p "${AAB}" "${dex_entry}" | strings | grep -E -m 1 "${FORBIDDEN_DEX_PATTERN}" || true)"
  if [[ -n "${hit}" ]]; then
    FORBIDDEN_DEX_HIT="${dex_entry}: ${hit}"
    break
  fi
done <<<"${DEX_ENTRIES}"
if [[ -n "${FORBIDDEN_DEX_HIT}" ]]; then
  echo "ERROR: AAB DEX에서 금지된 Billing/원격 SDK를 찾았습니다: ${FORBIDDEN_DEX_HIT}" >&2
  exit 1
fi

REQUIRED_LEGAL_ASSETS=(
  assets/site/privacy/index.md
  assets/site/licenses/index.md
  assets/site/licenses/android-runtime.md
  assets/site/licenses/godot-copyright.md
)
for legal_asset in "${REQUIRED_LEGAL_ASSETS[@]}"; do
  if ! grep -Fq "${legal_asset}" <<<"${AAB_LISTING}"; then
    echo "ERROR: canonical 법적 고지 ${legal_asset}가 AAB에 없습니다." >&2
    exit 1
  fi
done

echo "Android AAB boundary: PASS"
echo "  package=com.mrkimkim.dungeonoffice minSdk=24 targetSdk=36 ABI=arm64-v8a"
echo "  forbidden-permissions=absent remote-SDKs=absent allowBackup=false"
echo "  game=true HOME=absent launcher=present signer=1 legal-bundle=complete"
echo "  upload-cert-sha256=${ACTUAL_FINGERPRINT} pin-source=${EXPECTED_SOURCE}"
