#!/data/data/com.termux/files/usr/bin/bash

KBC_UPDATE_RUN_DIR=""
KBC_UPDATE_SOURCE_DIR=""
KBC_UPDATE_PERFORMED=false

kbc_update_cleanup() {
  if [[ -z "${KBC_UPDATE_RUN_DIR}" || ! -d "${KBC_UPDATE_RUN_DIR}" ]]; then
    return 0
  fi

  if [[ "${KBC_UPDATE_RUN_DIR}" == "${KBC_CACHE_DIR}/update/run."* ]]; then
    rm -rf -- "${KBC_UPDATE_RUN_DIR}"
  else
    kbc_warn "安全のため更新用一時ディレクトリを削除しませんでした: ${KBC_UPDATE_RUN_DIR}"
  fi
  KBC_UPDATE_RUN_DIR=""
}

kbc_cleanup() {
  kbc_build_cleanup
  kbc_update_cleanup
}

kbc_validate_version() {
  local version="$1"
  [[ "${version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z]+)*$ ]]
}

kbc_read_current_version() {
  local version_path="${KBC_CLONE_ROOT}/VERSION"
  local version

  [[ -f "${version_path}" ]] ||
    kbc_die "現在のバージョン情報が見つかりません"
  version="$(tr -d '\r\n' <"${version_path}")"
  kbc_validate_version "${version}" ||
    kbc_die "現在のバージョン情報が正しくありません: ${version}"
  printf '%s' "${version}"
}

kbc_fetch_latest_version() {
  local version

  version="$(
    curl \
      --fail \
      --silent \
      --show-error \
      --location \
      --retry 3 \
      --connect-timeout 15 \
      "${KBC_UPDATE_VERSION_URL}"
  )" || kbc_die "最新版を確認できません。通信状態を確認してください"
  version="$(printf '%s' "${version}" | tr -d '\r\n')"
  kbc_validate_version "${version}" ||
    kbc_die "取得したバージョン情報が正しくありません: ${version}"
  printf '%s' "${version}"
}

kbc_version_is_newer() {
  local candidate="$1"
  local current="$2"
  local newest

  kbc_validate_version "${candidate}" || return 1
  kbc_validate_version "${current}" || return 1
  [[ "${candidate}" != "${current}" ]] || return 1
  newest="$(printf '%s\n%s\n' "${candidate}" "${current}" | sort -V | tail -n 1)"
  [[ "${newest}" == "${candidate}" ]]
}

kbc_update_prepare_source() {
  local expected_version="$1"
  local archive_path
  local list_path
  local top_directory
  local extracted_version
  local required_path

  mkdir -p "${KBC_CACHE_DIR}/update"
  KBC_UPDATE_RUN_DIR="$(mktemp -d "${KBC_CACHE_DIR}/update/run.XXXXXX")"
  archive_path="${KBC_UPDATE_RUN_DIR}/source.tar.gz"
  list_path="${KBC_UPDATE_RUN_DIR}/archive-list.txt"

  kbc_info "更新ファイルを取得しています"
  curl \
    --fail \
    --silent \
    --show-error \
    --location \
    --retry 3 \
    --connect-timeout 15 \
    --output "${archive_path}" \
    "${KBC_UPDATE_ARCHIVE_URL}" ||
    kbc_die "更新ファイルを取得できませんでした"

  [[ "$(od -An -tx1 -N2 "${archive_path}" | tr -d ' \n')" == "1f8b" ]] ||
    kbc_die "取得した更新ファイルはgzip形式ではありません"
  tar -tzf "${archive_path}" >"${list_path}" ||
    kbc_die "更新ファイルの内容を確認できません"
  if grep -Eq '(^/|(^|/)\.\.(/|$))' "${list_path}"; then
    kbc_die "更新ファイルに安全でないパスが含まれています"
  fi

  top_directory="$(head -n 1 "${list_path}" | cut -d/ -f1)"
  [[ "${top_directory}" =~ ^[A-Za-z0-9._-]+$ ]] ||
    kbc_die "更新ファイルの最上位フォルダが正しくありません"
  tar -xzf "${archive_path}" -C "${KBC_UPDATE_RUN_DIR}" ||
    kbc_die "更新ファイルを展開できません"
  KBC_UPDATE_SOURCE_DIR="${KBC_UPDATE_RUN_DIR}/${top_directory}"

  for required_path in \
    VERSION \
    install.sh \
    bin/kbc-clone \
    lib/core.sh \
    lib/updater.sh; do
    [[ -f "${KBC_UPDATE_SOURCE_DIR}/${required_path}" ]] ||
      kbc_die "更新ファイルに必要な項目がありません: ${required_path}"
  done

  extracted_version="$(
    tr -d '\r\n' <"${KBC_UPDATE_SOURCE_DIR}/VERSION"
  )"
  [[ "${extracted_version}" == "${expected_version}" ]] ||
    kbc_die "更新ファイルとバージョン情報が一致しません"
}

kbc_command_self_update() {
  local assume_yes=false
  local force=false
  local check_only=false
  local current_version
  local latest_version
  local installed_version_path
  local installed_version

  while (($# > 0)); do
    case "$1" in
      --yes|-y)
        assume_yes=true
        shift
        ;;
      --force)
        force=true
        shift
        ;;
      --check)
        check_only=true
        shift
        ;;
      *)
        kbc_die "不明な更新オプションです: $1"
        ;;
    esac
  done

  kbc_is_termux ||
    kbc_die "ツールの自動更新はTermux内で実行してください"
  current_version="$(kbc_read_current_version)"
  latest_version="$(kbc_fetch_latest_version)"

  printf '現在のバージョン: %s\n' "${current_version}"
  printf '公開中の最新版    : %s\n' "${latest_version}"

  if [[ "${check_only}" == true ]]; then
    if kbc_version_is_newer "${latest_version}" "${current_version}"; then
      printf '更新できます。\n'
    else
      printf '更新はありません。\n'
    fi
    return 0
  fi

  if [[ "${force}" == false ]] &&
    ! kbc_version_is_newer "${latest_version}" "${current_version}"; then
    kbc_success "すでに最新版です"
    return 0
  fi

  if [[ "${assume_yes}" == false ]] &&
    ! kbc_confirm "最新版へ更新しますか？" "y"; then
    return 2
  fi

  kbc_update_prepare_source "${latest_version}"
  bash "${KBC_UPDATE_SOURCE_DIR}/install.sh" --update

  installed_version_path="${PREFIX}/opt/kbc-clone/VERSION"
  [[ -f "${installed_version_path}" ]] ||
    kbc_die "更新後のバージョン情報を確認できません"
  installed_version="$(tr -d '\r\n' <"${installed_version_path}")"
  [[ "${installed_version}" == "${latest_version}" ]] ||
    kbc_die "更新後のバージョンが一致しません"

  KBC_UPDATE_PERFORMED=true
  kbc_update_cleanup
  kbc_success "ツールを ${latest_version} へ更新しました"
}
