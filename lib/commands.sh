#!/data/data/com.termux/files/usr/bin/bash

kbc_command_help() {
  cat <<'EOF'
KBC cloneにゃんこ

初めて使う場合:
  kbc-clone

画面に表示される番号を選ぶと、順番に案内します。

使い方:
  kbc-clone                         初心者向けメニュー
  kbc-clone list                    作成済みクローンの一覧
  kbc-clone create [オプション]     新しいクローンを作る
  kbc-clone update <package> [オプション]
                                    作成済みクローンを更新
  kbc-clone register [オプション]   既存クローンを管理対象へ追加
  kbc-clone manage                  アプリを開く・削除する
  kbc-clone doctor                  ツールが動くか確認
  kbc-clone self-update             ツールを最新版へ更新

create/updateオプション:
  --xapk <パス|URL>       元になるにゃんこ大戦争のXAPK
  --package-suffix <ID>  アプリを見分ける短いID
  --app-name <名前>       ホーム画面に表示する名前
  --icon <PNG>            アプリアイコン
  --original-icon         公式アイコンを使用
  --output <APK>          出力APK
  --install               生成後にインストーラーを開く
  --keep-work             中間ファイルを残す

更新確認:
  kbc-clone self-update --check

例:
  kbc-clone create \
    --xapk /sdcard/Download/battlecats-arm64-v8a.xapk \
    --package-suffix sub1 \
    --app-name "KBC cloneにゃんこ" \
    --icon /sdcard/Download/kbc-icon.png \
    --install
EOF
}

kbc_command_list() {
  local package_name
  local app_name
  local version_code
  local version_name
  local abi
  local source_hash
  local updated_at
  local icon_path

  printf '本家\t%s\t%s\n' "にゃんこ大戦争" "${KBC_ORIGINAL_PACKAGE}"
  while IFS=$'\t' read -r \
    package_name \
    app_name \
    version_code \
    version_name \
    abi \
    source_hash \
    updated_at \
    icon_path; do
    printf 'クローン\t%s\t%s\tv%s\t%s\t%s\n' \
      "${app_name}" \
      "${package_name}" \
      "${version_name}" \
      "${abi}" \
      "${updated_at}"
  done < <(kbc_registry_list)
}

kbc_command_create() {
  local identity
  local package_name
  local package_suffix
  local app_name
  local icon_path=""
  local xapk_source=""
  local output_path=""
  local install_after=false

  identity="$(kbc_registry_next_identity)"
  IFS=$'\t' read -r package_name app_name <<<"${identity}"
  package_suffix="${package_name#"${KBC_PACKAGE_PREFIX}"}"

  while (($# > 0)); do
    case "$1" in
      --xapk)
        (($# >= 2)) || kbc_die "--xapkの値がありません"
        xapk_source="$2"
        shift 2
        ;;
      --package-suffix)
        (($# >= 2)) || kbc_die "--package-suffixの値がありません"
        package_suffix="$2"
        shift 2
        ;;
      --package)
        kbc_die "新規作成では --package-suffix を使用してください。固定部分は ${KBC_PACKAGE_PREFIX} です"
        ;;
      --app-name)
        (($# >= 2)) || kbc_die "--app-nameの値がありません"
        app_name="$2"
        shift 2
        ;;
      --icon)
        (($# >= 2)) || kbc_die "--iconの値がありません"
        icon_path="$2"
        shift 2
        ;;
      --original-icon)
        icon_path=""
        shift
        ;;
      --output)
        (($# >= 2)) || kbc_die "--outputの値がありません"
        output_path="$2"
        shift 2
        ;;
      --install)
        install_after=true
        shift
        ;;
      --keep-work)
        KBC_BUILD_KEEP_WORK=true
        shift
        ;;
      *)
        kbc_die "不明なオプションです: $1"
        ;;
    esac
  done

  [[ -n "${xapk_source}" ]] || kbc_die "--xapkを指定してください"
  kbc_require_package_suffix "${package_suffix}"
  package_name="$(kbc_package_from_suffix "${package_suffix}")"
  if kbc_registry_find "${package_name}" >/dev/null 2>&1; then
    kbc_die "同じ識別子のクローンが登録済みです: ${package_suffix}"
  fi
  if [[ -z "${output_path}" ]]; then
    output_path="$(kbc_default_output_dir)/${package_suffix//./-}.apk"
  fi

  kbc_build_clone \
    "${xapk_source}" \
    "${package_name}" \
    "${app_name}" \
    "${output_path}" \
    "${icon_path}"
  if [[ "${install_after}" == true ]]; then
    kbc_android_install_apk "${KBC_BUILD_OUTPUT}"
  fi
}

kbc_command_update() {
  local package_name="${1:-}"
  local record
  local app_name
  local current_version_code
  local current_version_name
  local current_abi
  local source_hash
  local updated_at
  local icon_path
  local xapk_source=""
  local output_path=""
  local install_after=false

  [[ -n "${package_name}" ]] ||
    kbc_die "更新するパッケージ名を指定してください"
  shift
  record="$(kbc_registry_find "${package_name}")" ||
    kbc_die "台帳にないクローンです: ${package_name}"
  IFS=$'\t' read -r \
    package_name \
    app_name \
    current_version_code \
    current_version_name \
    current_abi \
    source_hash \
    updated_at \
    icon_path <<<"${record}"
  [[ "${icon_path:-}" == "-" ]] && icon_path=""

  while (($# > 0)); do
    case "$1" in
      --xapk)
        (($# >= 2)) || kbc_die "--xapkの値がありません"
        xapk_source="$2"
        shift 2
        ;;
      --output)
        (($# >= 2)) || kbc_die "--outputの値がありません"
        output_path="$2"
        shift 2
        ;;
      --app-name)
        (($# >= 2)) || kbc_die "--app-nameの値がありません"
        app_name="$2"
        shift 2
        ;;
      --icon)
        (($# >= 2)) || kbc_die "--iconの値がありません"
        icon_path="$2"
        shift 2
        ;;
      --original-icon)
        icon_path=""
        shift
        ;;
      --install)
        install_after=true
        shift
        ;;
      --keep-work)
        KBC_BUILD_KEEP_WORK=true
        shift
        ;;
      *)
        kbc_die "不明なオプションです: $1"
        ;;
    esac
  done

  [[ -n "${xapk_source}" ]] || kbc_die "--xapkを指定してください"
  if [[ -z "${output_path}" ]]; then
    output_path="$(kbc_default_output_dir)/${package_name##*.}.apk"
  fi

  kbc_build_clone \
    "${xapk_source}" \
    "${package_name}" \
    "${app_name}" \
    "${output_path}" \
    "${icon_path}"
  if ((KBC_BUILD_VERSION_CODE < current_version_code)); then
    kbc_warn "作成したAPKは登録済みの版より古いため、上書きできない可能性があります。"
  fi
  if [[ "${install_after}" == true ]]; then
    kbc_android_install_apk "${KBC_BUILD_OUTPUT}"
  fi
}

kbc_command_register() {
  local package_name=""
  local app_name="${KBC_DEFAULT_NAME}"
  local version_code="0"
  local version_name="unknown"
  local abi="unknown"
  local icon_path=""
  local managed_icon_path=""

  while (($# > 0)); do
    case "$1" in
      --package)
        (($# >= 2)) || kbc_die "--packageの値がありません"
        package_name="$2"
        shift 2
        ;;
      --app-name)
        (($# >= 2)) || kbc_die "--app-nameの値がありません"
        app_name="$2"
        shift 2
        ;;
      --version-code)
        (($# >= 2)) || kbc_die "--version-codeの値がありません"
        version_code="$2"
        shift 2
        ;;
      --version-name)
        (($# >= 2)) || kbc_die "--version-nameの値がありません"
        version_name="$2"
        shift 2
        ;;
      --abi)
        (($# >= 2)) || kbc_die "--abiの値がありません"
        abi="$2"
        shift 2
        ;;
      --icon)
        (($# >= 2)) || kbc_die "--iconの値がありません"
        icon_path="$2"
        shift 2
        ;;
      *)
        kbc_die "不明なオプションです: $1"
        ;;
    esac
  done

  [[ -n "${package_name}" ]] || kbc_die "--packageを指定してください"
  kbc_require_clone_package "${package_name}"
  [[ "${version_code}" =~ ^[0-9]+$ ]] ||
    kbc_die "versionCodeは数値で指定してください"
  if [[ -n "${icon_path}" ]]; then
    managed_icon_path="$(kbc_store_icon "${icon_path}" "${package_name}")"
  fi

  kbc_registry_upsert \
    "${package_name}" \
    "${app_name}" \
    "${version_code}" \
    "${version_name}" \
    "${abi}" \
    "" \
    "$(kbc_timestamp)" \
    "${managed_icon_path}"
  kbc_success "台帳へ登録しました: ${package_name}"
}

kbc_command_doctor() {
  local missing=0
  local command_name
  local actual_hash
  local status

  printf 'KBC clone 動作診断\n'
  printf '  端末ABI: %s\n' "$(kbc_android_device_abis)"
  printf '  データ: %s\n' "${KBC_DATA_DIR}"
  printf '  台帳: %s\n' "${KBC_REGISTRY_FILE}"

  for command_name in \
    java \
    curl \
    jq \
    tar \
    unzip \
    zipalign \
    apksigner \
    keytool \
    termux-open; do
    if command -v "${command_name}" >/dev/null 2>&1; then
      status="OK"
    else
      status="不足"
      missing=1
    fi
    printf '  %-12s %s\n' "${command_name}" "${status}"
  done

  if [[ -f "${KBC_APKEDITOR_PATH}" ]]; then
    actual_hash="$(sha256sum "${KBC_APKEDITOR_PATH}" | awk '{print toupper($1)}')"
    if [[ "${actual_hash}" == "${KBC_APKEDITOR_SHA256}" ]]; then
      printf '  APKEditor    OK (v%s)\n' "${KBC_APKEDITOR_VERSION}"
    else
      printf '  APKEditor    SHA-256不一致\n'
      missing=1
    fi
  else
    printf '  APKEditor    不足\n'
    missing=1
  fi

  if ((missing == 0)); then
    kbc_success "利用可能です"
  else
    kbc_warn "不足があります。install.shを再実行してください。"
    return 1
  fi
}
