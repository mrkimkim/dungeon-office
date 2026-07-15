#!/usr/bin/env bash
set -euo pipefail

APK="${1:-}"
if [[ -z "${APK}" || ! -f "${APK}" ]]; then
  echo "Usage: $0 /path/to/debug.apk" >&2
  exit 2
fi

if [[ -n "${AAPT_BIN:-}" && -x "${AAPT_BIN}" ]]; then
  AAPT="${AAPT_BIN}"
else
  SDK_ROOT="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-${HOME}/Library/Android/sdk}}"
  AAPT="$(find "${SDK_ROOT}/build-tools" -mindepth 2 -maxdepth 2 -type f -name aapt 2>/dev/null | sort -V | tail -n 1)"
fi
if [[ -z "${AAPT:-}" || ! -x "${AAPT}" ]]; then
  echo "ERROR: aapt를 찾을 수 없습니다. AAPT_BIN을 지정하세요." >&2
  exit 1
fi

if [[ -n "${APKSIGNER_BIN:-}" && -x "${APKSIGNER_BIN}" ]]; then
  APKSIGNER="${APKSIGNER_BIN}"
elif [[ -x "$(dirname "${AAPT}")/apksigner" ]]; then
  APKSIGNER="$(dirname "${AAPT}")/apksigner"
else
  APKSIGNER="$(find "${SDK_ROOT:-${HOME}/Library/Android/sdk}/build-tools" -mindepth 2 -maxdepth 2 -type f -name apksigner 2>/dev/null | sort -V | tail -n 1)"
fi
if [[ -z "${APKSIGNER:-}" || ! -x "${APKSIGNER}" ]]; then
  echo "ERROR: apksigner를 찾을 수 없습니다. APKSIGNER_BIN을 지정하세요." >&2
  exit 1
fi

BADGING="$("${AAPT}" dump badging "${APK}")"
MANIFEST="$("${AAPT}" dump xmltree "${APK}" AndroidManifest.xml)"
PERMISSIONS="$("${AAPT}" dump permissions "${APK}")"
APK_LISTING="$(unzip -l "${APK}")"
APK_ENTRIES="$(unzip -Z1 "${APK}")"
SIGNATURE="$("${APKSIGNER}" verify --verbose --print-certs "${APK}")"

grep -q "package: name='com.mrkimkim.dungeonoffice'" <<<"${BADGING}" || {
  echo "ERROR: application ID가 다릅니다." >&2
  exit 1
}
grep -q "sdkVersion:'24'" <<<"${BADGING}" || {
  echo "ERROR: standard template minSdk가 24가 아닙니다." >&2
  exit 1
}
grep -q "targetSdkVersion:'36'" <<<"${BADGING}" || {
  echo "ERROR: standard template targetSdk가 36이 아닙니다." >&2
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
  if grep -Fq "uses-permission: name='${permission}'" <<<"${PERMISSIONS}"; then
    echo "ERROR: APK가 금지 권한 ${permission}을 요청합니다." >&2
    exit 1
  fi
done

grep -Fq "uses-permission: name='android.permission.VIBRATE'" <<<"${PERMISSIONS}" || {
  echo "ERROR: 햅틱 기능에 필요한 VIBRATE 권한이 없습니다." >&2
  exit 1
}

grep -q 'android:allowBackup.*0x0' <<<"${MANIFEST}" || {
  echo "ERROR: Android 자동 백업이 비활성화되지 않았습니다." >&2
  exit 1
}
grep -Eq 'android:isGame.*(0x1|0xffffffff)$' <<<"${MANIFEST}" || {
  echo "ERROR: android:isGame이 true가 아닙니다." >&2
  exit 1
}
grep -q 'android:appCategory.*0x0' <<<"${MANIFEST}" || {
  echo "ERROR: android:appCategory가 game이 아닙니다." >&2
  exit 1
}
grep -q 'android.intent.category.LAUNCHER' <<<"${MANIFEST}" || {
  echo "ERROR: launcher activity가 없습니다." >&2
  exit 1
}
if grep -Fq 'android.intent.category.HOME' <<<"${MANIFEST}"; then
  echo "ERROR: 일반 게임 APK에 HOME launcher category가 포함되어 있습니다." >&2
  exit 1
fi

grep -q "^native-code: 'arm64-v8a'$" <<<"${BADGING}" || {
  echo "ERROR: APK native-code가 arm64-v8a 단독이 아닙니다." >&2
  exit 1
}
grep -Eq '^lib/arm64-v8a/[^/]+\.so$' <<<"${APK_ENTRIES}" || {
  echo "ERROR: APK에 arm64-v8a native library가 없습니다." >&2
  exit 1
}
if grep -Eq '^lib/(armeabi-v7a|x86|x86_64)/' <<<"${APK_ENTRIES}"; then
  echo "ERROR: APK에 MVP 범위 밖 ABI native library가 포함되어 있습니다." >&2
  exit 1
fi

grep -Fq 'Number of signers: 1' <<<"${SIGNATURE}" || {
  echo "ERROR: APK가 정확히 하나의 인증서로 서명되지 않았습니다." >&2
  exit 1
}

DEX_ENTRIES="$(grep -E '^classes([0-9]+)?\.dex$' <<<"${APK_ENTRIES}" || true)"
if [[ -z "${DEX_ENTRIES}" ]]; then
  echo "ERROR: APK에서 DEX를 찾을 수 없습니다." >&2
  exit 1
fi
FORBIDDEN_DEX_PATTERN='Lcom/android/billingclient/|Lcom/google/firebase/|Lcom/google/android/gms/(ads|analytics|measurement)/|Lcom/adjust/sdk/|Lcom/appsflyer/|Lcom/facebook/appevents/'
FORBIDDEN_DEX_HIT=""
while IFS= read -r dex_entry; do
  [[ -z "${dex_entry}" ]] && continue
  hit="$(unzip -p "${APK}" "${dex_entry}" | strings | grep -E -m 1 "${FORBIDDEN_DEX_PATTERN}" || true)"
  if [[ -n "${hit}" ]]; then
    FORBIDDEN_DEX_HIT="${dex_entry}: ${hit}"
    break
  fi
done <<<"${DEX_ENTRIES}"
if [[ -n "${FORBIDDEN_DEX_HIT}" ]]; then
  echo "ERROR: APK DEX에서 금지된 Billing/원격 SDK를 찾았습니다: ${FORBIDDEN_DEX_HIT}" >&2
  exit 1
fi

REQUIRED_LEGAL_ASSETS=(
  assets/site/privacy/index.md
  assets/site/licenses/index.md
  assets/site/licenses/android-runtime.md
  assets/site/licenses/godot-copyright.md
)
for legal_asset in "${REQUIRED_LEGAL_ASSETS[@]}"; do
  if ! grep -Fq "${legal_asset}" <<<"${APK_LISTING}"; then
    echo "ERROR: canonical 법적 고지 ${legal_asset}가 APK에 없습니다." >&2
    exit 1
  fi
done

echo "Android APK boundary: PASS"
echo "  package=com.mrkimkim.dungeonoffice minSdk=24 targetSdk=36 ABI=arm64-v8a"
echo "  VIBRATE=present forbidden-permissions=absent remote-SDKs=absent allowBackup=false"
echo "  game=true HOME=absent launcher=present signer=1 legal-bundle=complete"
