#!/usr/bin/env bash
set -euo pipefail

readonly TEST_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly TEST_TEMP="$(mktemp -d "${TEST_ROOT}/.tmp-updater.XXXXXX")"
trap 'rm -rf -- "${TEST_TEMP}"' EXIT

fixture_root="${TEST_TEMP}/fixture"
fixture_url_root="${fixture_root}"
archive_root="${fixture_root}/KBC-rakv0-clone-main"
mkdir -p "${archive_root}/bin" "${archive_root}/lib"
printf '9.9.9\n' >"${fixture_root}/remote-VERSION"
cp "${fixture_root}/remote-VERSION" "${archive_root}/VERSION"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'source_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"' \
  'install_root="${PREFIX}/opt/kbc-clone"' \
  'mkdir -p "${install_root}"' \
  'cp "${source_root}/VERSION" "${install_root}/VERSION"' \
  >"${archive_root}/install.sh"
cp "${TEST_ROOT}/bin/kbc-clone" "${archive_root}/bin/kbc-clone"
cp "${TEST_ROOT}/lib/core.sh" "${archive_root}/lib/core.sh"
cp "${TEST_ROOT}/lib/updater.sh" "${archive_root}/lib/updater.sh"
tar -czf "${fixture_root}/source.tar.gz" \
  -C "${fixture_root}" \
  "KBC-rakv0-clone-main"

if command -v cygpath >/dev/null 2>&1; then
  fixture_url_root="/$(cygpath -m "${fixture_root}")"
fi

export KBC_CLONE_ROOT="${TEST_ROOT}"
export KBC_CLONE_DATA_DIR="${TEST_TEMP}/data"
export KBC_CLONE_STATE_DIR="${TEST_TEMP}/state"
export KBC_CLONE_CACHE_DIR="${TEST_TEMP}/cache"
export KBC_CLONE_CONFIG_DIR="${TEST_TEMP}/config"
export KBC_CLONE_DOWNLOAD_DIR="${TEST_TEMP}/downloads"
export KBC_CLONE_UPDATE_VERSION_URL="file://${fixture_url_root}/remote-VERSION"
export KBC_CLONE_UPDATE_ARCHIVE_URL="file://${fixture_url_root}/source.tar.gz"
export PREFIX="${TEST_TEMP}/com.termux/files/usr"

source "${TEST_ROOT}/lib/core.sh"
source "${TEST_ROOT}/lib/updater.sh"

kbc_initialize_directories

latest_version="$(kbc_fetch_latest_version)"
[[ "${latest_version}" == "9.9.9" ]] || {
  printf 'FAIL: 最新バージョン取得\n' >&2
  exit 1
}
kbc_version_is_newer "9.9.9" "0.2.0" || {
  printf 'FAIL: バージョン比較\n' >&2
  exit 1
}
if kbc_version_is_newer "0.1.0" "0.2.0"; then
  printf 'FAIL: 古いバージョンを最新版と判定しました\n' >&2
  exit 1
fi

kbc_update_prepare_source "${latest_version}"
[[ -f "${KBC_UPDATE_SOURCE_DIR}/install.sh" ]] || {
  printf 'FAIL: 更新アーカイブ展開\n' >&2
  exit 1
}
update_run_dir="${KBC_UPDATE_RUN_DIR}"
kbc_update_cleanup
[[ -z "${KBC_UPDATE_RUN_DIR}" && ! -e "${update_run_dir}" ]] || {
  printf 'FAIL: 更新一時ファイル削除\n' >&2
  exit 1
}

KBC_UPDATE_PERFORMED=false
kbc_command_self_update --yes >/dev/null
[[ "${KBC_UPDATE_PERFORMED}" == true ]] || {
  printf 'FAIL: 自己更新完了状態\n' >&2
  exit 1
}
[[ "$(tr -d '\r\n' <"${PREFIX}/opt/kbc-clone/VERSION")" == "9.9.9" ]] || {
  printf 'FAIL: 自己更新後のバージョン\n' >&2
  exit 1
}

printf 'PASS: updater tests\n'
