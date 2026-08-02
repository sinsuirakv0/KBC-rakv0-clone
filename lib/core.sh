#!/data/data/com.termux/files/usr/bin/bash

readonly KBC_ORIGINAL_PACKAGE="jp.co.ponos.battlecats"
readonly KBC_DEFAULT_NAME="KBC cloneにゃんこ"
readonly KBC_PACKAGE_PREFIX="jp.co.ponos.battlecats.kbc."
readonly KBC_DEFAULT_PACKAGE_SUFFIX="main"

readonly KBC_DATA_DIR="${KBC_CLONE_DATA_DIR:-${HOME}/.local/share/kbc-clone}"
readonly KBC_STATE_DIR="${KBC_CLONE_STATE_DIR:-${HOME}/.local/state/kbc-clone}"
readonly KBC_CACHE_DIR="${KBC_CLONE_CACHE_DIR:-${HOME}/.cache/kbc-clone}"
readonly KBC_CONFIG_DIR="${KBC_CLONE_CONFIG_DIR:-${HOME}/.config/kbc-clone}"
readonly KBC_DOWNLOAD_DIR="${KBC_CLONE_DOWNLOAD_DIR:-/sdcard/Download/KBC-clone-nyanko}"
readonly KBC_REGISTRY_FILE="${KBC_STATE_DIR}/clones.tsv"
readonly KBC_KEYSTORE_DIR="${KBC_DATA_DIR}/keystore"
readonly KBC_ICON_DIR="${KBC_DATA_DIR}/icons"
readonly KBC_ORIGINAL_ICON_PATH="${KBC_CLONE_ROOT}/assets/kbc-original-icon.png"
readonly KBC_KEYSTORE_PATH="${KBC_KEYSTORE_DIR}/kbc-clone.jks"
readonly KBC_PASSWORD_PATH="${KBC_KEYSTORE_DIR}/.signing-password"
readonly KBC_KEY_ALIAS="kbc-clone"
readonly KBC_APKEDITOR_PATH="${KBC_CLONE_ROOT}/vendor/APKEditor.jar"
readonly KBC_APKEDITOR_VERSION="1.4.9"
readonly KBC_APKEDITOR_URL="https://github.com/REAndroid/APKEditor/releases/download/V1.4.9/APKEditor-1.4.9.jar"
readonly KBC_APKEDITOR_SHA256="A9CD40DF818845456BE6D696DE6110C89EDF4B0A0580CB83438ED6B25A366E67"
readonly KBC_UPDATE_REPOSITORY="${KBC_CLONE_UPDATE_REPOSITORY:-sinsuirakv0/KBC-rakv0-clone}"
readonly KBC_UPDATE_BRANCH="${KBC_CLONE_UPDATE_BRANCH:-main}"
readonly KBC_UPDATE_VERSION_URL="${KBC_CLONE_UPDATE_VERSION_URL:-https://raw.githubusercontent.com/${KBC_UPDATE_REPOSITORY}/${KBC_UPDATE_BRANCH}/VERSION}"
readonly KBC_UPDATE_ARCHIVE_URL="${KBC_CLONE_UPDATE_ARCHIVE_URL:-https://github.com/${KBC_UPDATE_REPOSITORY}/archive/refs/heads/${KBC_UPDATE_BRANCH}.tar.gz}"

KBC_COLOR_ENABLED=true
if [[ ! -t 1 || "${NO_COLOR:-}" == "1" ]]; then
  KBC_COLOR_ENABLED=false
fi

kbc_color() {
  local code="$1"
  if [[ "${KBC_COLOR_ENABLED}" == true ]]; then
    printf '\033[%sm' "${code}"
  fi
}

kbc_reset_color() {
  if [[ "${KBC_COLOR_ENABLED}" == true ]]; then
    printf '\033[0m'
  fi
}

kbc_info() {
  {
    kbc_color "1;36"
    printf '[KBC clone] '
    kbc_reset_color
    printf '%s\n' "$*"
  } >&2
}

kbc_success() {
  {
    kbc_color "1;32"
    printf '[完了] '
    kbc_reset_color
    printf '%s\n' "$*"
  } >&2
}

kbc_warn() {
  {
    kbc_color "1;33"
    printf '[注意] '
    kbc_reset_color
    printf '%s\n' "$*"
  } >&2
}

kbc_die() {
  {
    kbc_color "1;31"
    printf '[エラー] '
    kbc_reset_color
    printf '%s\n' "$*"
  } >&2
  exit 1
}

kbc_require_command() {
  command -v "$1" >/dev/null 2>&1 ||
    kbc_die "必要なコマンドがありません: $1"
}

kbc_initialize_directories() {
  mkdir -p \
    "${KBC_DATA_DIR}" \
    "${KBC_STATE_DIR}" \
    "${KBC_CACHE_DIR}" \
    "${KBC_CONFIG_DIR}" \
    "${KBC_KEYSTORE_DIR}" \
    "${KBC_ICON_DIR}"

  if [[ -d /sdcard/Download && -w /sdcard/Download ]]; then
    mkdir -p "${KBC_DOWNLOAD_DIR}"
  fi
}

kbc_validate_package_name() {
  local package_name="$1"
  [[ "${package_name}" =~ ^[a-zA-Z][a-zA-Z0-9_]*(\.[a-zA-Z][a-zA-Z0-9_]*)+$ ]]
}

kbc_validate_package_suffix() {
  local package_suffix="$1"
  [[ "${package_suffix}" =~ ^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)*$ ]]
}

kbc_package_from_suffix() {
  local package_suffix="$1"
  kbc_validate_package_suffix "${package_suffix}" || return 1
  printf '%s%s' "${KBC_PACKAGE_PREFIX}" "${package_suffix}"
}

kbc_require_package_suffix() {
  local package_suffix="$1"
  kbc_validate_package_suffix "${package_suffix}" ||
    kbc_die "識別子は小文字英字で始め、英小文字・数字・_・.だけで指定してください: ${package_suffix}"
}

kbc_require_clone_package() {
  local package_name="$1"
  kbc_validate_package_name "${package_name}" ||
    kbc_die "パッケージ名の形式が正しくありません: ${package_name}"
  [[ "${package_name}" != "${KBC_ORIGINAL_PACKAGE}" ]] ||
    kbc_die "本家と同じパッケージ名は使用できません"
}

kbc_validate_png_icon() {
  local icon_path="$1"
  local magic

  [[ -f "${icon_path}" ]] || return 1
  magic="$(od -An -tx1 -N8 "${icon_path}" | tr -d ' \n')"
  [[ "${magic}" == "89504e470d0a1a0a" ]]
}

kbc_require_png_icon() {
  local icon_path="$1"
  [[ -f "${icon_path}" ]] ||
    kbc_die "アイコンが見つかりません: ${icon_path}"
  kbc_validate_png_icon "${icon_path}" ||
    kbc_die "アイコンはPNG形式で指定してください: ${icon_path}"
}

kbc_managed_icon_path() {
  local package_name="$1"
  printf '%s/%s.png' "${KBC_ICON_DIR}" "${package_name}"
}

kbc_store_icon() {
  local source_path="$1"
  local package_name="$2"
  local destination_path
  local source_resolved
  local destination_resolved

  kbc_require_png_icon "${source_path}"
  mkdir -p "${KBC_ICON_DIR}"
  destination_path="$(kbc_managed_icon_path "${package_name}")"
  source_resolved="$(realpath -m "${source_path}")"
  destination_resolved="$(realpath -m "${destination_path}")"
  if [[ "${source_resolved}" != "${destination_resolved}" ]]; then
    cp -- "${source_path}" "${destination_path}"
  fi
  chmod 600 "${destination_path}" 2>/dev/null || true
  printf '%s' "${destination_path}"
}

kbc_sanitize_record_field() {
  printf '%s' "$1" | tr '\t\r\n' '   '
}

kbc_escape_xml_attribute() {
  printf '%s' "$1" |
    sed \
      -e 's/&/\&amp;/g' \
      -e 's/"/\&quot;/g' \
      -e 's/</\&lt;/g' \
      -e 's/>/\&gt;/g'
}

kbc_escape_sed_replacement() {
  printf '%s' "$1" | sed -e 's/[&|\\]/\\&/g'
}

kbc_confirm() {
  local prompt="$1"
  local default_answer="${2:-y}"
  local answer
  local suffix="[Y/n]"

  if [[ "${default_answer}" == "n" ]]; then
    suffix="[y/N]"
  fi

  printf '%s %s ' "${prompt}" "${suffix}"
  IFS= read -r answer
  answer="${answer:-${default_answer}}"
  [[ "${answer}" =~ ^[Yy]$ ]]
}

kbc_prompt() {
  local prompt="$1"
  local default_value="${2:-}"
  local answer

  if [[ -n "${default_value}" ]]; then
    printf '%s [%s]: ' "${prompt}" "${default_value}" >&2
  else
    printf '%s: ' "${prompt}" >&2
  fi
  IFS= read -r answer
  printf '%s' "${answer:-${default_value}}"
}

kbc_timestamp() {
  date -u '+%Y-%m-%dT%H:%M:%SZ'
}

kbc_is_termux() {
  [[ "${PREFIX:-}" == *"com.termux"* || -d /data/data/com.termux/files/usr ]]
}

kbc_default_output_dir() {
  if [[ -d /sdcard/Download && -w /sdcard/Download ]]; then
    printf '%s' "${KBC_DOWNLOAD_DIR}"
  else
    printf '%s' "${KBC_DATA_DIR}/output"
  fi
}
