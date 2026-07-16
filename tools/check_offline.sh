#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

SCAN_PATHS=(src data project.godot export_presets.cfg)
if [[ -d addons ]]; then
  SCAN_PATHS+=(addons)
fi

NETWORK_API_PATTERN='HTTPRequest|HTTPClient|WebSocketPeer|WebSocketMultiplayerPeer|WebRTCPeer|WebRTCMultiplayerPeer|WebView|JavaScriptBridge|PacketPeerUDP|PacketPeerDTLS|UDPServer|TCPServer|StreamPeerTCP|StreamPeerTLS|DTLSServer|ENetMultiplayerPeer'
if rg -n "${NETWORK_API_PATTERN}" "${SCAN_PATHS[@]}"; then
  echo "ERROR: 오프라인 MVP에서 금지한 네트워크 또는 WebView API를 찾았습니다." >&2
  exit 1
fi

REMOTE_SDK_PATTERN='com[.:/]android[.:/]billingclient|com[.:/]google[.:/]firebase|com[.:/]google[.:/]android[.:/]gms[.:/](ads|analytics|measurement)|firebase|crashlytics|google.?analytics|admob|adjust.?sdk|appsflyer|facebook.?appevents'
if rg -n -i "${REMOTE_SDK_PATTERN}" "${SCAN_PATHS[@]}"; then
  echo "ERROR: 오프라인 MVP에서 금지한 Billing/광고/분석/원격 SDK 참조를 찾았습니다." >&2
  exit 1
fi

COMMERCIAL_API_PATTERN='BillingClient|GooglePlayBilling|billing[_./-]?product|purchase[_./-]?token|queryProductDetails|launchBillingFlow'
if rg -n -i "${COMMERCIAL_API_PATTERN}" "${SCAN_PATHS[@]}"; then
  echo "ERROR: 무료 MVP 범위 밖 Billing 상품 또는 구매 API 참조를 찾았습니다." >&2
  exit 1
fi

PRESET_COUNT="$(rg -c '^\[preset\.[0-9]+\.options\]$' export_presets.cfg)"
if [[ -z "${PRESET_COUNT}" || "${PRESET_COUNT}" == "0" ]]; then
  echo "ERROR: Android export preset options를 찾을 수 없습니다." >&2
  exit 1
fi

for setting in \
  'permissions/internet=false' \
  'permissions/vibrate=true' \
  'permissions/custom_permissions=PackedStringArray()' \
  'architectures/arm64-v8a=true' \
  'architectures/armeabi-v7a=false' \
  'architectures/x86_64=false'; do
  setting_count="$(rg -Fxc "${setting}" export_presets.cfg || true)"
  if [[ "${setting_count}" != "${PRESET_COUNT}" ]]; then
    echo "ERROR: 모든 Android preset이 ${setting} 경계를 명시해야 합니다." >&2
    exit 1
  fi
done

echo "Offline boundary: PASS"
echo "  network-APIs=absent remote-SDKs=absent Billing=absent"
echo "  INTERNET=disabled VIBRATE=enabled custom-permissions=empty ABI=arm64-v8a-only"
