#!/usr/bin/env bash
set -euo pipefail

find_godot() {
  if [[ -n "${GODOT_BIN:-}" && -x "${GODOT_BIN}" ]]; then
    printf '%s\n' "${GODOT_BIN}"
    return
  fi
  if command -v godot >/dev/null 2>&1; then
    command -v godot
    return
  fi
  if command -v godot4 >/dev/null 2>&1; then
    command -v godot4
    return
  fi
  return 1
}

find_android_sdk() {
  local candidate
  for candidate in \
    "${ANDROID_HOME:-}" \
    "${ANDROID_SDK_ROOT:-}" \
    "${HOME}/Library/Android/sdk" \
    "${HOME}/Android/Sdk"; do
    if [[ -n "${candidate}" && -d "${candidate}" ]]; then
      printf '%s\n' "${candidate}"
      return
    fi
  done
  return 1
}

find_java_home() {
  local candidate
  for candidate in \
    "${JAVA_HOME:-}" \
    "/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home" \
    "/usr/local/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home"; do
    if [[ -n "${candidate}" && -x "${candidate}/bin/java" ]]; then
      printf '%s\n' "${candidate}"
      return
    fi
  done
  return 1
}

find_export_templates() {
  local candidate
  for candidate in \
    "${HOME}/Library/Application Support/Godot/export_templates/4.7.stable" \
    "${HOME}/.local/share/godot/export_templates/4.7.stable"; do
    if [[ -f "${candidate}/version.txt" && \
          "$(<"${candidate}/version.txt")" == "4.7.stable" && \
          -f "${candidate}/android_debug.apk" && \
          -f "${candidate}/android_release.apk" && \
          -f "${candidate}/android_source.zip" ]]; then
      printf '%s\n' "${candidate}"
      return
    fi
  done
  return 1
}

if ! GODOT="$(find_godot)"; then
  echo "ERROR: Godot 4.7-stable을 찾을 수 없습니다. GODOT_BIN을 지정하세요." >&2
  exit 1
fi

VERSION="$(${GODOT} --version | head -n 1)"
if [[ "${VERSION}" != 4.7* ]]; then
  echo "ERROR: Godot 4.7이 필요하지만 '${VERSION}'을 찾았습니다." >&2
  exit 1
fi

echo "Godot: ${GODOT} (${VERSION})"

if ! EXPORT_TEMPLATES="$(find_export_templates)"; then
  echo "ERROR: Godot 4.7.stable Android APK 및 Gradle source export templates를 찾을 수 없습니다." >&2
  exit 1
fi
echo "Godot export templates: ${EXPORT_TEMPLATES}"

if ! command -v unzip >/dev/null 2>&1 || \
   ! unzip -tq "${EXPORT_TEMPLATES}/android_source.zip" >/dev/null; then
  echo "ERROR: android_source.zip을 읽을 수 없거나 압축 파일이 손상되었습니다." >&2
  exit 1
fi
ANDROID_SOURCE_CONFIG="$(unzip -p "${EXPORT_TEMPLATES}/android_source.zip" config.gradle)"
if [[ "${ANDROID_SOURCE_CONFIG}" != *"buildTools         : '36.1.0'"* ]] || \
   [[ "${ANDROID_SOURCE_CONFIG}" != *"ndkVersion         : '29.0.14206865'"* ]]; then
  echo "ERROR: Godot Android source template의 Build Tools 또는 NDK 버전이 프로젝트 계약과 다릅니다." >&2
  exit 1
fi
echo "Godot Android source template: verified"

if ! JAVA_17_HOME="$(find_java_home)"; then
  echo "ERROR: JDK 17을 찾을 수 없습니다. JAVA_HOME을 JDK 17로 지정하세요." >&2
  exit 1
fi
JAVA_VERSION="$("${JAVA_17_HOME}/bin/java" -version 2>&1 | head -n 1)"
if [[ "${JAVA_VERSION}" != *'version "17.'* ]]; then
  echo "ERROR: Android export에는 JDK 17이 필요하지만 '${JAVA_VERSION}'을 찾았습니다." >&2
  exit 1
fi
echo "Java: ${JAVA_17_HOME} (${JAVA_VERSION})"

if ! ANDROID_SDK="$(find_android_sdk)"; then
  echo "ERROR: Android SDK를 찾을 수 없습니다. ANDROID_HOME 또는 ANDROID_SDK_ROOT를 지정하세요." >&2
  exit 1
fi
echo "Android SDK: ${ANDROID_SDK}"

if [[ ! -d "${ANDROID_SDK}/platforms/android-36" ]]; then
  echo "ERROR: Android SDK Platform 36이 필요합니다." >&2
  exit 1
fi
echo "Android SDK Platform: 36"

if [[ ! -d "${ANDROID_SDK}/build-tools/36.1.0" ]]; then
  echo "ERROR: Android SDK Build Tools 36.1.0이 필요합니다." >&2
  exit 1
fi
echo "Android SDK Build Tools: 36.1.0"

if [[ ! -d "${ANDROID_SDK}/ndk/29.0.14206865" ]]; then
  echo "ERROR: Android NDK 29.0.14206865가 필요합니다." >&2
  exit 1
fi
echo "Android NDK: 29.0.14206865"

if [[ ! -d "${ANDROID_SDK}/cmake/3.10.2.4988404" ]]; then
  echo "ERROR: CMake 3.10.2.4988404가 필요합니다." >&2
  exit 1
fi
echo "CMake: 3.10.2.4988404"

if [[ -x "${ANDROID_SDK}/platform-tools/adb" ]]; then
  ADB="${ANDROID_SDK}/platform-tools/adb"
  echo "adb: ${ADB}"
elif command -v adb >/dev/null 2>&1; then
  ADB="$(command -v adb)"
  echo "adb: ${ADB}"
else
  echo "ERROR: Android SDK Platform Tools(adb)가 필요합니다." >&2
  exit 1
fi

DEVICE_COUNT="$(${ADB} devices | sed '1d' | rg -c '\sdevice$' || true)"
if [[ "${DEVICE_COUNT}" -gt 0 ]]; then
  echo "Android devices: ${DEVICE_COUNT} connected"
elif [[ "${1:-}" == "--require-device" ]]; then
  echo "ERROR: adb 상태가 device인 Android 기기 또는 emulator가 필요합니다." >&2
  exit 1
else
  echo "Android devices: none (실기 smoke 전에는 --require-device로 다시 검사)"
fi
