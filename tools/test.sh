#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ -n "${GODOT_BIN:-}" && -x "${GODOT_BIN}" ]]; then
  GODOT="${GODOT_BIN}"
elif command -v godot >/dev/null 2>&1; then
  GODOT="$(command -v godot)"
elif command -v godot4 >/dev/null 2>&1; then
  GODOT="$(command -v godot4)"
else
  echo "ERROR: Godot을 찾을 수 없습니다. GODOT_BIN을 지정하세요." >&2
  exit 1
fi

cd "${ROOT}"

run_godot_strict() {
  local log_file
  log_file="$(mktemp)"
  set +e
  "$@" 2>&1 | tee "${log_file}"
  local command_status=${PIPESTATUS[0]}
  set -e
  if [[ ${command_status} -ne 0 ]]; then
    rm -f "${log_file}"
    echo "ERROR: Godot command exited with ${command_status}." >&2
    exit "${command_status}"
  fi
  if grep -Eq 'SCRIPT ERROR:|Parse Error:|^ERROR:' "${log_file}"; then
    rm -f "${log_file}"
    echo "ERROR: Godot reported a script/runtime error despite a zero exit code." >&2
    exit 1
  fi
  rm -f "${log_file}"
}

run_godot_strict "${GODOT}" --headless --path "${ROOT}" --editor --quit
run_godot_strict "${GODOT}" --headless --path "${ROOT}" --script res://tests/run_tests.gd
