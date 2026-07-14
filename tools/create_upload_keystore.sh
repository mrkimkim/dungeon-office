#!/usr/bin/env bash
set -euo pipefail

KEYSTORE_PATH="${1:-${HOME}/.config/dungeon-office/signing/dungeon-office-upload.p12}"
KEY_ALIAS="dungeon-office-upload"
JAVA_HOME_17="${JAVA_HOME_17:-/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home}"
KEYTOOL="${JAVA_HOME_17}/bin/keytool"

if [[ ! -x "${KEYTOOL}" ]]; then
  echo "ERROR: JDK 17 keytool을 찾을 수 없습니다. JAVA_HOME_17을 지정하세요." >&2
  exit 1
fi

if [[ -e "${KEYSTORE_PATH}" ]]; then
  echo "ERROR: 기존 키를 덮어쓰지 않습니다: ${KEYSTORE_PATH}" >&2
  exit 1
fi

umask 077
mkdir -p "$(dirname "${KEYSTORE_PATH}")"

echo "Dungeon Office 전용 upload key를 만듭니다. 다음 암호는 저장소 밖의 암호 관리자에 보관하세요."
"${KEYTOOL}" -genkeypair \
  -keystore "${KEYSTORE_PATH}" \
  -storetype PKCS12 \
  -alias "${KEY_ALIAS}" \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000 \
  -dname "CN=Dungeon Office Upload Key"

chmod 600 "${KEYSTORE_PATH}"
echo "생성 완료: ${KEYSTORE_PATH}"
echo "alias: ${KEY_ALIAS}"
echo "이 파일과 암호를 각각 안전하게 백업한 뒤 Play Console의 upload key로만 사용하세요."
