#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT="${1:-${ROOT}/build/android/dungeon-office-release.aab}"
GODOT="${GODOT_BIN:-godot}"

if ! command -v "${GODOT}" >/dev/null 2>&1; then
  echo "ERROR: Godot 실행 파일을 찾을 수 없습니다. GODOT_BIN을 지정하세요." >&2
  exit 1
fi

for variable in \
  GODOT_ANDROID_KEYSTORE_RELEASE_PATH \
  GODOT_ANDROID_KEYSTORE_RELEASE_USER \
  GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD; do
  if [[ -z "${!variable:-}" ]]; then
    echo "ERROR: ${variable} 환경 변수가 필요합니다." >&2
    exit 1
  fi
done

if [[ ! -f "${GODOT_ANDROID_KEYSTORE_RELEASE_PATH}" ]]; then
  echo "ERROR: release keystore 파일을 찾을 수 없습니다." >&2
  exit 1
fi

mkdir -p "$(dirname "${OUTPUT}")"
cd "${ROOT}"

GODOT_ARGS=(--headless --path "${ROOT}")
if [[ ! -f "${ROOT}/android/.build_version" ]] || \
   [[ "$(<"${ROOT}/android/.build_version")" != "4.7.stable" ]]; then
  GODOT_ARGS+=(--install-android-build-template)
fi
GODOT_ARGS+=(--export-release "Android Release" "${OUTPUT}")

LOG_FILE="$(mktemp)"
trap 'rm -f "${LOG_FILE}"' EXIT
set +e
"${GODOT}" "${GODOT_ARGS[@]}" 2>&1 | tee "${LOG_FILE}"
GODOT_STATUS=${PIPESTATUS[0]}
set -e
if [[ ${GODOT_STATUS} -ne 0 ]] || grep -Eq 'SCRIPT ERROR:|Parse Error:|^ERROR:' "${LOG_FILE}"; then
  rm -f "${OUTPUT}"
  echo "ERROR: Godot release export가 실패했습니다." >&2
  exit 1
fi
if [[ ! -s "${OUTPUT}" ]]; then
  echo "ERROR: release AAB가 생성되지 않았습니다." >&2
  exit 1
fi
echo "Release AAB 생성 완료: ${OUTPUT}"
