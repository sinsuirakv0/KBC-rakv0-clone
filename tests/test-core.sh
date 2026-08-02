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

assert_equal() {
  local expected="$1"
  local actual="$2"
  local message="$3"
  if [[ "${expected}" != "${actual}" ]]; then
    printf 'FAIL: %s\nexpected: %s\nactual:   %s\n' \
      "${message}" "${expected}" "${actual}" >&2
    exit 1
  fi
}

kbc_initialize_directories
kbc_registry_initialize

kbc_validate_package_name "jp.co.ponos.battlecats.clone1"
if kbc_validate_package_name "not a package"; then
  printf 'FAIL: 不正なパッケージ名を許可しました\n' >&2
  exit 1
fi

kbc_validate_package_suffix "main"
kbc_validate_package_suffix "user_1.sub2"
for invalid_suffix in "Main" "1main" "main-" "main."; do
  if kbc_validate_package_suffix "${invalid_suffix}"; then
    printf 'FAIL: 不正な識別子を許可しました: %s\n' "${invalid_suffix}" >&2
    exit 1
  fi
done
assert_equal \
  "jp.co.ponos.battlecats.kbc.user_1" \
  "$(kbc_package_from_suffix 'user_1')" \
  "固定プレフィックスの結合"

test_icon="${TEST_TEMP}/input-icon.png"
printf '\x89PNG\r\n\x1a\nKBC-test' >"${test_icon}"
stored_icon="$(kbc_store_icon "${test_icon}" 'jp.co.ponos.battlecats.kbc.user_1')"
[[ -f "${stored_icon}" ]] || {
  printf 'FAIL: 指定アイコンが保存されませんでした\n' >&2
  exit 1
}
cmp "${test_icon}" "${stored_icon}"

escaped="$(kbc_escape_xml_attribute 'KBC & "clone" <test>')"
assert_equal \
  'KBC &amp; &quot;clone&quot; &lt;test&gt;' \
  "${escaped}" \
  "XML属性エスケープ"

kbc_registry_upsert \
  "jp.co.ponos.battlecats.kbc.main" \
  "KBC cloneにゃんこ" \
  "1505010" \
  "15.5.1" \
  "arm64-v8a" \
  "ABCDEF" \
  "2026-08-03T00:00:00Z" \
  "/tmp/kbc-main.png"

assert_equal "1" "$(kbc_registry_count)" "台帳件数"
record="$(kbc_registry_find 'jp.co.ponos.battlecats.kbc.main')"
IFS=$'\t' read -r \
  package_name app_name version_code version_name abi source_hash updated_at icon_path \
  <<<"${record}"
assert_equal "jp.co.ponos.battlecats.kbc.main" "${package_name}" "パッケージ名"
assert_equal "KBC cloneにゃんこ" "${app_name}" "表示名"
assert_equal "1505010" "${version_code}" "versionCode"
assert_equal "15.5.1" "${version_name}" "versionName"
assert_equal "arm64-v8a" "${abi}" "ABI"
assert_equal "ABCDEF" "${source_hash}" "入力ハッシュ"
assert_equal "2026-08-03T00:00:00Z" "${updated_at}" "更新日時"
assert_equal "/tmp/kbc-main.png" "${icon_path}" "アイコンパス"

next_identity="$(kbc_registry_next_identity)"
assert_equal \
  $'jp.co.ponos.battlecats.kbc.clone2\tKBC cloneにゃんこ 2' \
  "${next_identity}" \
  "次のクローン識別子"

kbc_registry_remove "jp.co.ponos.battlecats.kbc.main"
assert_equal "0" "$(kbc_registry_count)" "台帳削除"

printf 'PASS: core tests\n'
