#!/data/data/com.termux/files/usr/bin/bash

kbc_ui_header() {
  clear 2>/dev/null || true
  kbc_color "1;36"
  printf 'KBC cloneにゃんこ\n'
  kbc_reset_color
  printf '%s\n\n' '番号を選ぶだけで、クローンの作成と更新ができます。'
}

kbc_ui_pause() {
  printf '\nEnterキーでメニューへ戻ります'
  IFS= read -r _
}

kbc_ui_title() {
  printf '\n%s\n' "$1"
  printf '%s\n\n' '----------------------------------------'
}

kbc_ui_step() {
  local current="$1"
  local total="$2"
  local title="$3"
  printf '\n[%s/%s] %s\n' "${current}" "${total}" "${title}"
}

kbc_ui_run_screen() {
  local action="$1"
  local had_errexit=false
  local status

  [[ "$-" == *e* ]] && had_errexit=true
  set +e
  (
    set -e
    trap kbc_cleanup EXIT
    "${action}"
  )
  status=$?
  if [[ "${had_errexit}" == true ]]; then
    set -e
  fi

  if ((status == 10)); then
    printf '\n新しいバージョンで再起動します。\n'
    sleep 1
    exec "${PREFIX}/bin/kbc-clone"
  elif ((status == 2)); then
    printf '\n操作をキャンセルしました。\n'
  elif ((status != 0)); then
    printf '\n操作を完了できませんでした。表示された内容を確認してください。\n'
  fi
  kbc_ui_pause
}

kbc_ui_prompt_app_name_in_browser() {
  local default_name="$1"
  local dialog_directory
  local result_path
  local ready_path
  local token
  local dialog_pid
  local dialog_url
  local app_name
  local attempt

  kbc_is_termux || return 1
  command -v python >/dev/null 2>&1 || return 1
  command -v termux-open-url >/dev/null 2>&1 || return 1
  [[ -f "${KBC_APP_NAME_DIALOG_PATH}" ]] || return 1

  dialog_directory="$(mktemp -d "${KBC_CACHE_DIR}/app-name.XXXXXX")"
  result_path="${dialog_directory}/result.txt"
  ready_path="${dialog_directory}/ready.txt"
  token="$(od -An -N24 -tx1 /dev/urandom | tr -d ' \n')"

  python "${KBC_APP_NAME_DIALOG_PATH}" \
    --default "${default_name}" \
    --result "${result_path}" \
    --ready "${ready_path}" \
    --token "${token}" &
  dialog_pid=$!

  for ((attempt = 0; attempt < 50; attempt += 1)); do
    if [[ -s "${ready_path}" ]]; then
      break
    fi
    if ! kill -0 "${dialog_pid}" 2>/dev/null; then
      break
    fi
    sleep 0.1
  done

  if [[ ! -s "${ready_path}" ]]; then
    wait "${dialog_pid}" 2>/dev/null || true
    kbc_remove_cache_directory "${dialog_directory}"
    return 1
  fi

  dialog_url="$(tr -d '\r\n' <"${ready_path}")"
  if ! termux-open-url "${dialog_url}"; then
    kill "${dialog_pid}" 2>/dev/null || true
    wait "${dialog_pid}" 2>/dev/null || true
    kbc_remove_cache_directory "${dialog_directory}"
    return 1
  fi

  printf 'ブラウザにアプリ名の入力欄を開きました。日本語キーボードで入力して決定してください。\n' >&2
  printf '決定後はTermuxへ戻ってください。5分間待機します。\n' >&2
  if ! wait "${dialog_pid}"; then
    kbc_remove_cache_directory "${dialog_directory}"
    return 1
  fi

  if [[ ! -f "${result_path}" ]]; then
    kbc_remove_cache_directory "${dialog_directory}"
    return 1
  fi
  app_name="$(<"${result_path}")"
  kbc_remove_cache_directory "${dialog_directory}"
  kbc_validate_app_name "${app_name}" || return 1
  printf '%s' "${app_name}"
}

kbc_ui_prompt_app_name() {
  local default_name="$1"
  local app_name

  if app_name="$(kbc_ui_prompt_app_name_in_browser "${default_name}")"; then
    printf '%s' "${app_name}"
    return 0
  fi

  printf '標準入力欄を開けなかったため、Termuxの入力欄でアプリ名を入力します。\n' >&2
  while true; do
    app_name="$(kbc_prompt 'ホーム画面に表示するアプリ名' "${default_name}")"
    if kbc_validate_app_name "${app_name}"; then
      printf '%s' "${app_name}"
      return 0
    fi
    kbc_warn "アプリ名は空白だけにせず、80文字以内で入力してください。"
  done
}

kbc_ui_prompt_package_suffix() {
  local default_suffix="$1"
  local package_suffix
  local package_name

  printf '同じ端末に複数入れるための内部IDです。\n' >&2
  printf 'よく分からない場合は、何も入力せず初期値のまま進めてください。\n' >&2
  printf '固定部分: %s\n' "${KBC_PACKAGE_PREFIX}" >&2

  while true; do
    package_suffix="$(kbc_prompt '固定部分の後ろに付けるID' "${default_suffix}")"
    if ! kbc_validate_package_suffix "${package_suffix}"; then
      kbc_warn "例: main、sub1、my.cat（英小文字で開始）"
      continue
    fi

    package_name="$(kbc_package_from_suffix "${package_suffix}")"
    if kbc_registry_find "${package_name}" >/dev/null 2>&1; then
      kbc_warn "そのIDはすでに使われています。別のIDを入力してください。"
      continue
    fi

    printf '%s' "${package_suffix}"
    return 0
  done
}

kbc_ui_icon_label() {
  local icon_path="$1"
  if [[ "${icon_path}" == "${KBC_ORIGINAL_ICON_PATH}" ]]; then
    printf 'KBCオリジナル'
  elif [[ -n "${icon_path}" ]]; then
    printf '%s' "$(basename -- "${icon_path}")"
  else
    printf '公式アイコン'
  fi
}

kbc_ui_discover_xapks() {
  local search_root="/sdcard/Download"
  [[ -d "${search_root}" ]] || return 0

  find "${search_root}" \
    -maxdepth 2 \
    -type f \
    -iname '*.xapk' \
    -printf '%T@\t%p\n' 2>/dev/null |
    sort -nr |
    cut -f 2- |
    head -n 10
}

kbc_ui_read_xapk_version() {
  local xapk_path="$1"
  local manifest_json
  local version_name

  [[ -f "${xapk_path}" ]] || return 1
  manifest_json="$(unzip -p "${xapk_path}" manifest.json 2>/dev/null)" || return 1
  version_name="$(printf '%s' "${manifest_json}" | jq -r '.version_name // empty' 2>/dev/null)" || return 1
  [[ -n "${version_name}" ]] || return 1
  printf '%s' "${version_name}"
}

kbc_ui_select_xapk() {
  local files=()
  local index
  local answer
  local manual_path
  local version_name

  while true; do
    mapfile -t files < <(kbc_ui_discover_xapks)
    if ((${#files[@]} == 0)); then
      printf 'DownloadフォルダにXAPKが見つかりません。\n' >&2
      printf '先にブラウザなどで本家XAPK（.xapk）をDownloadへ保存してください。\n' >&2
    else
      printf '元になるXAPKを選んでください。\n' >&2
      printf '通常は、いちばん新しいファイルを選びます。\n\n' >&2
      for index in "${!files[@]}"; do
        if version_name="$(kbc_ui_read_xapk_version "${files[index]}")"; then
          printf '  %d. v%s  %s\n' \
            "$((index + 1))" \
            "${version_name}" \
            "$(basename -- "${files[index]}")" >&2
        else
          printf '  %d. 版不明  %s\n' \
            "$((index + 1))" \
            "$(basename -- "${files[index]}")" >&2
        fi
      done
    fi
    printf '  m. 別の保存場所にあるXAPKを指定\n' >&2
    printf '  b. 戻る\n' >&2
    printf '番号: ' >&2
    IFS= read -r answer

    case "${answer}" in
      b|B) return 2 ;;
      m|M)
        manual_path="$(kbc_prompt 'XAPKの保存場所')"
        if [[ -z "${manual_path}" ]]; then
          kbc_warn "保存場所を入力してください。"
          continue
        fi
        if [[ ! -f "${manual_path}" || "${manual_path,,}" != *.xapk ]]; then
          kbc_warn "拡張子が.xapkのファイルを指定してください。"
          continue
        fi
        printf '%s' "${manual_path}"
        return 0
        ;;
    esac

    if [[ "${answer}" =~ ^[0-9]+$ ]] &&
      ((answer >= 1 && answer <= ${#files[@]})); then
      printf '%s' "${files[answer - 1]}"
      return 0
    fi
    kbc_warn "一覧にある番号、m、bのどれかを入力してください。"
  done
}

kbc_ui_select_icon() {
  local answer
  local manual_path

  while true; do
    printf 'アプリアイコンを選んでください。\n' >&2
    printf '迷った場合は、公式アイコンのままで大丈夫です。\n\n' >&2
    printf '  0. 公式アイコンを使う（おすすめ）\n' >&2
    printf '  1. KBCオリジナルを使う\n' >&2
    printf '  2. PNGファイルを指定する\n' >&2
    printf '  b. 戻る\n' >&2
    printf '番号 [0]: ' >&2
    IFS= read -r answer
    answer="${answer:-0}"

    case "${answer}" in
      0)
        printf ''
        return 0
        ;;
      1)
        if ! kbc_validate_png_icon "${KBC_ORIGINAL_ICON_PATH}"; then
          kbc_warn 'KBCオリジナルアイコンはまだ追加されていません。公式か指定PNGを選んでください。'
          continue
        fi
        printf '%s' "${KBC_ORIGINAL_ICON_PATH}"
        return 0
        ;;
      b|B)
        return 2
        ;;
      2)
        manual_path="$(kbc_prompt 'PNGファイルの保存場所')"
        if [[ -z "${manual_path}" || ! -f "${manual_path}" ]]; then
          kbc_warn "指定したファイルが見つかりません。"
          continue
        fi
        if ! kbc_validate_png_icon "${manual_path}"; then
          kbc_warn "PNG形式の画像を指定してください。"
          continue
        fi
        printf '%s' "${manual_path}"
        return 0
        ;;
    esac

    kbc_warn '0、1、2、bのどれかを入力してください。'
  done
}

kbc_ui_print_registry() {
  local index=1
  local package_name
  local app_name
  local version_code
  local version_name
  local abi
  local source_hash
  local updated_at
  local icon_path

  printf '  0. 本家にゃんこ大戦争\n'
  while IFS=$'\t' read -r \
    package_name \
    app_name \
    version_code \
    version_name \
    abi \
    source_hash \
    updated_at \
    icon_path; do
    printf '  %d. %s  v%s\n' \
      "${index}" \
      "${app_name}" \
      "${version_name}"
    ((index += 1))
  done < <(kbc_registry_list)
}

kbc_ui_select_clone_record() {
  local records=()
  local answer

  mapfile -t records < <(kbc_registry_list)
  if ((${#records[@]} == 0)); then
    kbc_warn "まだクローンが作成されていません。"
    return 2
  fi

  local index
  local package_name
  local app_name
  local version_code
  local version_name
  local abi
  local source_hash
  local updated_at
  local icon_path
  for index in "${!records[@]}"; do
    IFS=$'\t' read -r \
      package_name \
      app_name \
      version_code \
      version_name \
      abi \
      source_hash \
      updated_at \
      icon_path <<<"${records[index]}"
    printf '  %d. %s  v%s\n' \
      "$((index + 1))" \
      "${app_name}" \
      "${version_name}" >&2
  done

  while true; do
    printf '  b. 戻る\n' >&2
    printf '番号: ' >&2
    IFS= read -r answer
    if [[ "${answer}" =~ ^[Bb]$ ]]; then
      return 2
    fi
    if [[ "${answer}" =~ ^[0-9]+$ ]] &&
      ((answer >= 1 && answer <= ${#records[@]})); then
      printf '%s' "${records[answer - 1]}"
      return 0
    fi
    kbc_warn "一覧にある番号か、bを入力してください。"
  done
}

kbc_ui_create_clone() {
  local identity
  local default_package
  local default_suffix
  local default_name
  local source
  local package_suffix
  local package_name
  local app_name
  local icon_path
  local icon_label
  local output_dir
  local output_path

  kbc_ui_title "新しいクローンを作る"
  identity="$(kbc_registry_next_identity)"
  IFS=$'\t' read -r default_package default_name <<<"${identity}"
  default_suffix="${default_package#"${KBC_PACKAGE_PREFIX}"}"

  kbc_ui_step 1 4 "元になるXAPK"
  source="$(kbc_ui_select_xapk)"

  kbc_ui_step 2 4 "アプリ名と識別ID"
  app_name="$(kbc_ui_prompt_app_name "${default_name}")"
  printf '\n'
  package_suffix="$(kbc_ui_prompt_package_suffix "${default_suffix}")"
  package_name="$(kbc_package_from_suffix "${package_suffix}")"

  kbc_ui_step 3 4 "アプリアイコン"
  icon_path="$(kbc_ui_select_icon)"
  icon_label="$(kbc_ui_icon_label "${icon_path}")"
  output_dir="$(kbc_default_output_dir)"
  output_path="${output_dir}/${package_suffix//./-}.apk"

  kbc_ui_step 4 4 "内容の確認"
  printf 'アプリ名 : %s\n' "${app_name}"
  printf '識別ID   : %s\n' "${package_name}"
  printf 'アイコン : %s\n' "${icon_label}"
  printf '元データ : %s\n' "$(basename -- "${source}")"
  printf '保存先   : %s\n\n' "${output_path}"
  kbc_confirm "この内容で作成しますか？" "y" || return 2

  kbc_build_clone \
    "${source}" \
    "${package_name}" \
    "${app_name}" \
    "${output_path}" \
    "${icon_path}"
  if kbc_confirm "Androidのインストーラーを開きますか？" "y"; then
    kbc_android_install_apk "${KBC_BUILD_OUTPUT}"
  fi
}

kbc_ui_update_clone() {
  local record
  local package_name
  local app_name
  local current_version_code
  local current_version_name
  local current_abi
  local source_hash
  local updated_at
  local icon_path
  local icon_reselected=false
  local source
  local output_dir
  local output_path

  kbc_ui_title "作ったクローンを更新する"
  kbc_ui_step 1 4 "更新するアプリ"
  record="$(kbc_ui_select_clone_record)"
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

  kbc_ui_step 2 4 "新しいXAPK"
  source="$(kbc_ui_select_xapk)"

  kbc_ui_step 3 4 "名前とアイコン"
  printf '現在のアプリ名: %s\n' "${app_name}"
  if kbc_confirm "アプリ名を変更しますか？" "n"; then
    app_name="$(kbc_ui_prompt_app_name "${app_name}")"
  fi
  if [[ -n "${icon_path}" ]]; then
    printf '現在のアイコン: %s\n' "$(kbc_ui_icon_label "${icon_path}")"
    if [[ ! -f "${icon_path}" ]]; then
      kbc_warn "保存済みアイコンが見つからないため、選び直してください。"
      icon_path="$(kbc_ui_select_icon)"
      icon_reselected=true
    fi
  else
    printf '現在のアイコン: 公式アイコン\n'
  fi
  if [[ "${icon_reselected}" == false ]] &&
    kbc_confirm "アプリアイコンを変更しますか？" "n"; then
    icon_path="$(kbc_ui_select_icon)"
  fi
  output_dir="$(kbc_default_output_dir)"
  output_path="${output_dir}/${package_name##*.}.apk"

  kbc_ui_step 4 4 "内容の確認"
  printf 'アプリ名 : %s\n' "${app_name}"
  printf '現在の版 : v%s\n' "${current_version_name}"
  printf '識別ID   : %s\n' "${package_name}"
  printf 'アイコン : %s\n' "$(kbc_ui_icon_label "${icon_path}")"
  printf '元データ : %s\n\n' "$(basename -- "${source}")"
  kbc_confirm "この内容で更新しますか？" "y" || return 2
  kbc_build_clone \
    "${source}" \
    "${package_name}" \
    "${app_name}" \
    "${output_path}" \
    "${icon_path}"

  if ((KBC_BUILD_VERSION_CODE < current_version_code)); then
    kbc_warn "入力版のversionCodeが登録版より古いため、Androidが上書きを拒否する可能性があります。"
  elif ((KBC_BUILD_VERSION_CODE == current_version_code)); then
    kbc_warn "登録済みと同じversionCodeです。"
  fi

  if kbc_confirm "Androidの更新インストーラーを開きますか？" "y"; then
    kbc_android_install_apk "${KBC_BUILD_OUTPUT}"
  fi
}

kbc_ui_manage_apps() {
  local records=()
  local selection
  local package_name
  local app_name
  local action
  local record

  mapfile -t records < <(kbc_registry_list)
  kbc_ui_print_registry
  printf '番号: '
  IFS= read -r selection
  [[ "${selection}" =~ ^[0-9]+$ ]] ||
    kbc_die "番号を入力してください"

  if ((selection == 0)); then
    package_name="${KBC_ORIGINAL_PACKAGE}"
    app_name="本家にゃんこ大戦争"
  else
    ((selection >= 1 && selection <= ${#records[@]})) ||
      kbc_die "選択範囲外です"
    record="${records[selection - 1]}"
    IFS=$'\t' read -r package_name app_name _ <<<"${record}"
  fi

  printf '\n%s\n' "${app_name}"
  printf '%s\n' "${package_name}"
  printf '  1. 起動\n'
  printf '  2. Androidのアプリ情報\n'
  printf '  3. アンインストール画面\n'
  if [[ "${package_name}" == "${KBC_ORIGINAL_PACKAGE}" ]]; then
    printf '  4. Playストアを開く\n'
  fi
  printf '  0. 戻る\n'
  printf '番号: '
  IFS= read -r action

  case "${action}" in
    1) kbc_android_launch_app "${package_name}" ;;
    2) kbc_android_open_app_details "${package_name}" ;;
    3) kbc_android_request_uninstall "${package_name}" ;;
    4)
      [[ "${package_name}" == "${KBC_ORIGINAL_PACKAGE}" ]] ||
        kbc_die "この操作は本家専用です"
      kbc_android_open_store "${package_name}"
      ;;
    0) return 0 ;;
    *) kbc_die "不明な操作です" ;;
  esac
}

kbc_ui_show_list() {
  kbc_ui_print_registry
  printf '\n'
  kbc_android_warn_package_query_limit
}

kbc_ui_update_tool() {
  kbc_ui_title "ツールを最新版へ更新する"
  printf '署名鍵、作成済みアイコン、クローン台帳はそのまま残ります。\n\n'
  KBC_UPDATE_PERFORMED=false
  kbc_command_self_update
  if [[ "${KBC_UPDATE_PERFORMED}" == true ]]; then
    return 10
  fi
}

kbc_ui_main() {
  kbc_configure_termux_integration
  if [[ -t 0 ]]; then
    stty iutf8 2>/dev/null || true
  fi

  while true; do
    kbc_ui_header
    printf '  1. 新しいクローンを作る\n'
    printf '  2. 作ったクローンを更新する\n'
    printf '  3. アプリを開く・削除する\n'
    printf '  4. 作ったクローンの一覧\n'
    printf '  5. ツールが動くか確認する\n'
    printf '  6. このツールを更新する\n'
    printf '  0. 終了\n\n'
    printf '番号: '

    local action
    IFS= read -r action
    case "${action}" in
      1) kbc_ui_run_screen kbc_ui_create_clone ;;
      2) kbc_ui_run_screen kbc_ui_update_clone ;;
      3) kbc_ui_run_screen kbc_ui_manage_apps ;;
      4) kbc_ui_run_screen kbc_ui_show_list ;;
      5) kbc_ui_run_screen kbc_command_doctor ;;
      6) kbc_ui_run_screen kbc_ui_update_tool ;;
      0) return 0 ;;
      *) kbc_warn "0から6の番号を入力してください"; sleep 1 ;;
    esac
  done
}
