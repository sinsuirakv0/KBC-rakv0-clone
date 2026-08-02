#!/usr/bin/env bash
set -euo pipefail

readonly TEST_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly TEST_TEMP="$(mktemp -d)"
trap 'rm -rf -- "${TEST_TEMP}"' EXIT

export KBC_CLONE_ROOT="${TEST_ROOT}"
export KBC_CLONE_DATA_DIR="${TEST_TEMP}/data"
export KBC_CLONE_STATE_DIR="${TEST_TEMP}/state"
export KBC_CLONE_CACHE_DIR="${TEST_TEMP}/cache"
export KBC_CLONE_CONFIG_DIR="${TEST_TEMP}/config"
export KBC_CLONE_DOWNLOAD_DIR="${TEST_TEMP}/downloads"

source "${TEST_ROOT}/lib/core.sh"
source "${TEST_ROOT}/lib/registry.sh"
source "${TEST_ROOT}/lib/builder.sh"
source "${TEST_ROOT}/lib/updater.sh"
source "${TEST_ROOT}/lib/ui.sh"

kbc_initialize_directories
kbc_registry_initialize

# 誤入力後も終了せず、次の入力を受け付けることを確認する。
package_suffix="$(
  printf 'Bad ID\nsub1\n' |
    kbc_ui_prompt_package_suffix "main" 2>/dev/null
)"
[[ "${package_suffix}" == "sub1" ]] || {
  printf 'FAIL: 識別IDの再入力\n' >&2
  exit 1
}

app_name="$(
  printf '\n' |
    kbc_ui_prompt_app_name "KBC cloneにゃんこ" 2>/dev/null
)"
[[ "${app_name}" == "KBC cloneにゃんこ" ]] || {
  printf 'FAIL: アプリ名の初期値\n' >&2
  exit 1
}

cancel_action() {
  return 2
}

cancel_output="$(printf '\n' | kbc_ui_run_screen cancel_action)"
grep -q '操作をキャンセルしました' <<<"${cancel_output}" || {
  printf 'FAIL: キャンセル後のメニュー復帰\n' >&2
  exit 1
}

printf 'PASS: ui tests\n'
