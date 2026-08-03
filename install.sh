#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

update_mode=false
while (($# > 0)); do
  case "$1" in
    --update)
      update_mode=true
      shift
      ;;
    *)
      printf '不明なセットアップオプションです: %s\n' "$1" >&2
      exit 1
      ;;
  esac
done

if [[ "${PREFIX:-}" != *"com.termux"* ]]; then
  printf 'このセットアップはTermux内で実行してください。\n' >&2
  exit 1
fi

readonly SOURCE_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly INSTALL_ROOT="${PREFIX}/opt/kbc-clone"
readonly COMMAND_LINK="${PREFIX}/bin/kbc-clone"

export KBC_CLONE_ROOT="${INSTALL_ROOT}"

required_commands=(
  java
  curl
  unzip
  tar
  zipalign
  apksigner
  jq
  termux-open
  termux-open-url
  termux-reload-settings
  python
)
missing_command=false
for command_name in "${required_commands[@]}"; do
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    missing_command=true
    break
  fi
done

if [[ "${update_mode}" == false ]]; then
  printf '[KBC clone] Termuxパッケージを準備します\n'
  pkg update -y
  pkg install -y openjdk-17 curl unzip aapt apksigner jq termux-tools python
elif [[ "${missing_command}" == true ]]; then
  printf '[KBC clone] 不足しているTermuxパッケージを追加します\n'
  pkg install -y openjdk-17 curl unzip aapt apksigner jq termux-tools python
else
  printf '[KBC clone] 導入済みパッケージを再利用します\n'
fi

mkdir -p \
  "${INSTALL_ROOT}/bin" \
  "${INSTALL_ROOT}/lib" \
  "${INSTALL_ROOT}/assets" \
  "${INSTALL_ROOT}/vendor"

cp -f "${SOURCE_ROOT}/bin/kbc-clone" "${INSTALL_ROOT}/bin/kbc-clone"
cp -f "${SOURCE_ROOT}"/lib/*.sh "${INSTALL_ROOT}/lib/"
cp -f "${SOURCE_ROOT}/lib/IconResizer.java" "${INSTALL_ROOT}/lib/IconResizer.java"
cp -f "${SOURCE_ROOT}/lib/app_name_dialog.py" "${INSTALL_ROOT}/lib/app_name_dialog.py"
if [[ -d "${SOURCE_ROOT}/assets" ]]; then
  cp -a "${SOURCE_ROOT}/assets/." "${INSTALL_ROOT}/assets/"
fi
cp -f "${SOURCE_ROOT}/README.md" "${INSTALL_ROOT}/README.md"
cp -f "${SOURCE_ROOT}/VERSION" "${INSTALL_ROOT}/VERSION"

source "${INSTALL_ROOT}/lib/core.sh"
kbc_configure_termux_integration

legacy_keystore_dir="${HOME}/kbc-clone/keystore"
if [[ ! -f "${KBC_KEYSTORE_PATH}" \
  && -f "${legacy_keystore_dir}/kbc-clone.jks" \
  && -f "${legacy_keystore_dir}/.signing-password" ]]; then
  mkdir -p "${KBC_KEYSTORE_DIR}"
  cp -p \
    "${legacy_keystore_dir}/kbc-clone.jks" \
    "${KBC_KEYSTORE_PATH}"
  cp -p \
    "${legacy_keystore_dir}/.signing-password" \
    "${KBC_PASSWORD_PATH}"
  chmod 600 "${KBC_KEYSTORE_PATH}" "${KBC_PASSWORD_PATH}"
  printf '[KBC clone] 旧版の署名鍵を移行しました\n'
fi

if [[ ! -f "${KBC_APKEDITOR_PATH}" ]]; then
  printf '[KBC clone] APKEditor %sを取得します\n' "${KBC_APKEDITOR_VERSION}"
  curl \
    --fail \
    --location \
    --retry 3 \
    --output "${KBC_APKEDITOR_PATH}.part" \
    "${KBC_APKEDITOR_URL}"
  mv "${KBC_APKEDITOR_PATH}.part" "${KBC_APKEDITOR_PATH}"
fi

actual_hash="$(sha256sum "${KBC_APKEDITOR_PATH}" | awk '{print toupper($1)}')"
if [[ "${actual_hash}" != "${KBC_APKEDITOR_SHA256}" ]]; then
  printf 'APKEditorのSHA-256が一致しません。\n' >&2
  exit 1
fi

chmod +x "${INSTALL_ROOT}/bin/kbc-clone"
ln -sfn "${INSTALL_ROOT}/bin/kbc-clone" "${COMMAND_LINK}"

printf '\nセットアップが完了しました。\n'
printf '次のコマンドで起動できます:\n\n  kbc-clone\n\n'
