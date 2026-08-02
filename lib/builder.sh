#!/data/data/com.termux/files/usr/bin/bash

KBC_BUILD_RUN_DIR=""
KBC_BUILD_KEEP_WORK=false
KBC_BUILD_VERSION_CODE=""
KBC_BUILD_VERSION_NAME=""
KBC_BUILD_ABI=""
KBC_BUILD_SOURCE_HASH=""
KBC_BUILD_OUTPUT=""
KBC_BUILD_ICON_PATH=""
KBC_BUILD_TEMPLATE_DIR=""

kbc_build_cleanup() {
  if [[ -z "${KBC_BUILD_RUN_DIR}" || ! -d "${KBC_BUILD_RUN_DIR}" ]]; then
    return 0
  fi

  if [[ "${KBC_BUILD_KEEP_WORK}" == true ]]; then
    kbc_info "中間ファイル: ${KBC_BUILD_RUN_DIR}"
    return 0
  fi

  if [[ "${KBC_BUILD_RUN_DIR}" == "${KBC_CACHE_DIR}/work/"* ]]; then
    rm -rf -- "${KBC_BUILD_RUN_DIR}"
  else
    kbc_warn "安全のため中間ディレクトリを削除しませんでした: ${KBC_BUILD_RUN_DIR}"
  fi
}

kbc_read_xapk_metadata() {
  local xapk_path="$1"
  local manifest_json

  manifest_json="$(unzip -p "${xapk_path}" manifest.json 2>/dev/null)" ||
    kbc_die "XAPK内のmanifest.jsonを読み込めません"

  printf '%s' "${manifest_json}" |
    jq -er '[
      .package_name,
      (.version_code | tostring),
      .version_name,
      (
        [
          .split_apks[]?.id
          | select(
              . == "config.arm64_v8a"
              or . == "config.armeabi_v7a"
              or . == "config.x86"
              or . == "config.x86_64"
            )
          | sub("^config\\."; "")
          | if . == "arm64_v8a" then "arm64-v8a"
            elif . == "armeabi_v7a" then "armeabi-v7a"
            else .
            end
        ][0] // "unknown"
      )
    ] | @tsv' ||
    kbc_die "XAPKのメタデータ形式を解釈できません"
}

kbc_prepare_xapk() {
  local source="$1"
  local destination="${KBC_BUILD_RUN_DIR}/input.xapk"
  local prepared_path
  local magic

  if [[ "${source}" =~ ^https?:// ]]; then
    kbc_info "XAPKをダウンロードします"
    curl \
      --fail \
      --location \
      --retry 3 \
      --continue-at - \
      --output "${destination}" \
      "${source}"
    prepared_path="${destination}"
  else
    [[ -f "${source}" ]] || kbc_die "XAPKが見つかりません: ${source}"
    # 150 MB前後のXAPKを毎回複製せず、その場で読み込む。
    prepared_path="$(realpath -m "${source}")"
  fi

  magic="$(od -An -tx1 -N4 "${prepared_path}" | tr -d ' \n')"
  [[ "${magic}" == "504b0304" ]] ||
    kbc_die "入力はZIP/XAPK形式ではありません"

  printf '%s' "${prepared_path}"
}

kbc_template_is_ready() {
  local template_dir="$1"
  local source_hash="$2"
  local ready_hash

  [[ -f "${template_dir}/.ready" ]] || return 1
  [[ -f "${template_dir}/decoded/AndroidManifest.xml" ]] || return 1
  ready_hash="$(tr -d '\r\n' <"${template_dir}/.ready")"
  [[ "${ready_hash}" == "${source_hash}" ]] || return 1
  grep -q "package=\"${KBC_ORIGINAL_PACKAGE}\"" \
    "${template_dir}/decoded/AndroidManifest.xml"
}

kbc_prune_template_cache() {
  local template_root="$1"
  local keep_dir="$2"
  local candidate_dir

  [[ "${template_root}" == "${KBC_CACHE_DIR}/templates" ]] ||
    kbc_die "キャッシュ削除範囲が正しくありません: ${template_root}"
  [[ "${keep_dir}" == "${template_root}/"* ]] ||
    kbc_die "保持するキャッシュの場所が正しくありません: ${keep_dir}"

  while IFS= read -r -d '' candidate_dir; do
    [[ "${candidate_dir}" == "${template_root}/"* ]] ||
      kbc_die "キャッシュ削除先が範囲外です: ${candidate_dir}"
    [[ "${candidate_dir}" != "${keep_dir}" ]] || continue
    rm -rf -- "${candidate_dir}"
  done < <(
    find "${template_root}" \
      -mindepth 1 \
      -maxdepth 1 \
      -type d \
      -print0
  )
}

kbc_prepare_decoded_template() {
  local input_xapk="$1"
  local source_hash="$2"
  local template_root="${KBC_CACHE_DIR}/templates"
  local template_dir="${template_root}/${source_hash}"
  local staging_dir="${KBC_BUILD_RUN_DIR}/template"
  local merged_apk="${staging_dir}/merged.apk"
  local decoded_dir="${staging_dir}/decoded"
  local signatures_dir

  [[ "${source_hash}" =~ ^[A-F0-9]{64}$ ]] ||
    kbc_die "入力XAPKのSHA-256が正しくありません"
  mkdir -p "${template_root}"

  if kbc_template_is_ready "${template_dir}" "${source_hash}"; then
    kbc_info "展開済みデータを再利用します"
    touch "${template_dir}" 2>/dev/null || true
    KBC_BUILD_TEMPLATE_DIR="${template_dir}/decoded"
    return 0
  fi

  mkdir -p "${staging_dir}"
  kbc_info "初回のみ: split APKを統合しています"
  java "-Xmx${KBC_JAVA_HEAP:-3g}" -jar "${KBC_APKEDITOR_PATH}" m \
    -i "${input_xapk}" \
    -o "${merged_apk}" \
    -f

  kbc_info "初回のみ: Manifestとリソースを展開しています"
  java "-Xmx${KBC_JAVA_HEAP:-3g}" -jar "${KBC_APKEDITOR_PATH}" d \
    -t xml \
    -dex \
    -i "${merged_apk}" \
    -o "${decoded_dir}" \
    -f

  signatures_dir="${decoded_dir}/signatures"
  if [[ -d "${signatures_dir}" && "${signatures_dir}" == "${staging_dir}/"* ]]; then
    rm -rf -- "${signatures_dir}"
  fi
  rm -f -- "${merged_apk}"

  # 再利用元を誤って上書きした場合は、書込みエラーにして破損を防ぐ。
  find "${decoded_dir}" -type f -exec chmod a-w {} +
  printf '%s\n' "${source_hash}" >"${staging_dir}/.ready"

  if [[ -e "${template_dir}" ]]; then
    [[ "${template_dir}" == "${template_root}/"* ]] ||
      kbc_die "古いキャッシュの場所が正しくありません: ${template_dir}"
    rm -rf -- "${template_dir}"
  fi
  mv "${staging_dir}" "${template_dir}"
  kbc_prune_template_cache "${template_root}" "${template_dir}"
  KBC_BUILD_TEMPLATE_DIR="${template_dir}/decoded"
}

kbc_materialize_decoded_template() {
  local template_dir="$1"
  local destination_dir="$2"

  [[ -d "${template_dir}" ]] ||
    kbc_die "展開済みキャッシュが見つかりません"
  [[ "${destination_dir}" == "${KBC_BUILD_RUN_DIR}/"* ]] ||
    kbc_die "作業用展開先が範囲外です: ${destination_dir}"

  # 同じファイルシステムではハードリンクを使い、約170 MBの複製を省く。
  if cp -al -- "${template_dir}" "${destination_dir}" 2>/dev/null; then
    return 0
  fi

  if [[ -e "${destination_dir}" ]]; then
    rm -rf -- "${destination_dir}"
  fi
  kbc_warn "高速コピーを利用できないため、通常コピーへ切り替えます。"
  cp -a -- "${template_dir}" "${destination_dir}"
}

kbc_patch_manifest() {
  local manifest_path="$1"
  local clone_package="$2"
  local app_name="$3"
  local escaped_name
  local sed_name

  [[ -f "${manifest_path}" ]] ||
    kbc_die "AndroidManifest.xmlがありません"
  grep -q "package=\"${KBC_ORIGINAL_PACKAGE}\"" "${manifest_path}" ||
    kbc_die "対象はJP版にゃんこ大戦争のXAPKではありません"

  escaped_name="$(kbc_escape_xml_attribute "${app_name}")"
  sed_name="$(kbc_escape_sed_replacement "${escaped_name}")"

  # 実装クラス名を維持し、Android上で衝突する識別子だけ変更する。
  sed -i \
    -e "s|package=\"${KBC_ORIGINAL_PACKAGE}\"|package=\"${clone_package}\"|" \
    -e "s|android:name=\"${KBC_ORIGINAL_PACKAGE}\\.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION\"|android:name=\"${clone_package}.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION\"|g" \
    -e "s|android:authorities=\"${KBC_ORIGINAL_PACKAGE}|android:authorities=\"${clone_package}|g" \
    -e "0,/android:label=\"[^\"]*\"/s||android:label=\"${sed_name}\"|" \
    "${manifest_path}"

  grep -q "package=\"${clone_package}\"" "${manifest_path}" ||
    kbc_die "パッケージ名の変更に失敗しました"
  grep -q "android:label=\"${escaped_name}\"" "${manifest_path}" ||
    kbc_die "アプリ名の変更に失敗しました"
}

kbc_patch_icon() {
  local decoded_dir="$1"
  local icon_path="$2"
  local resources_dir="${decoded_dir}/resources"
  local target_path
  local target_count=0
  local target_hash
  local source_hash

  kbc_require_png_icon "${icon_path}"
  [[ -d "${resources_dir}" ]] ||
    kbc_die "展開済みリソースが見つかりません"
  source_hash="$(sha256sum "${icon_path}" | awk '{print toupper($1)}')"

  # 通常アイコンとアダプティブアイコンの前景を同じ指定PNGへ差し替える。
  while IFS= read -r -d '' target_path; do
    [[ "${target_path}" == "${resources_dir}/"* ]] ||
      kbc_die "アイコンの書換え先が作業領域外です: ${target_path}"
    rm -f -- "${target_path}"
    cp -- "${icon_path}" "${target_path}"
    target_hash="$(sha256sum "${target_path}" | awk '{print toupper($1)}')"
    [[ "${target_hash}" == "${source_hash}" ]] ||
      kbc_die "アイコンの書換え検証に失敗しました: ${target_path}"
    ((target_count += 1))
  done < <(
    find "${resources_dir}" \
      -type f \
      \( -name 'icon.png' -o -name 'icon_foreground.png' \) \
      -print0
  )

  ((target_count > 0)) ||
    kbc_die "APK内のアプリアイコンを特定できませんでした"
}

kbc_ensure_signing_key() {
  local password

  mkdir -p "${KBC_KEYSTORE_DIR}"
  if [[ ! -f "${KBC_PASSWORD_PATH}" ]]; then
    umask 077
    od -An -N24 -tx1 /dev/urandom | tr -d ' \n' >"${KBC_PASSWORD_PATH}"
    printf '\n' >>"${KBC_PASSWORD_PATH}"
  fi

  password="$(tr -d '\r\n' <"${KBC_PASSWORD_PATH}")"
  [[ -n "${password}" ]] ||
    kbc_die "署名用パスワードを読み込めません"
  export KBC_KEY_PASSWORD="${password}"

  if [[ ! -f "${KBC_KEYSTORE_PATH}" ]]; then
    kbc_info "更新用の署名鍵を作成します"
    keytool -genkeypair \
      -keystore "${KBC_KEYSTORE_PATH}" \
      -storepass:env KBC_KEY_PASSWORD \
      -keypass:env KBC_KEY_PASSWORD \
      -alias "${KBC_KEY_ALIAS}" \
      -keyalg RSA \
      -keysize 3072 \
      -validity 10000 \
      -dname "CN=KBC clone, O=KBC, C=JP" \
      -noprompt
    chmod 600 "${KBC_KEYSTORE_PATH}" "${KBC_PASSWORD_PATH}"
  fi
}

kbc_align_apk() {
  local input_apk="$1"
  local output_apk="$2"
  local help_text

  help_text="$(zipalign -h 2>&1 || true)"
  if grep -q -- '-P' <<<"${help_text}"; then
    zipalign -P 16 -f 4 "${input_apk}" "${output_apk}"
  else
    zipalign -p -f 4 "${input_apk}" "${output_apk}"
  fi
}

kbc_check_abi_compatibility() {
  local archive_abi="$1"
  local device_abis

  [[ "${archive_abi}" != "unknown" ]] || return 0
  device_abis="$(kbc_android_device_abis)"
  [[ -n "${device_abis}" ]] || return 0

  if [[ ",${device_abis}," != *",${archive_abi},"* ]]; then
    kbc_warn "XAPKのABI ${archive_abi} は、この端末 ${device_abis} に対応していません。"
    return 1
  fi
}

kbc_build_clone() {
  local source="$1"
  local clone_package="$2"
  local app_name="$3"
  local output_path="$4"
  local icon_path="${5:-}"
  local input_xapk
  local metadata
  local source_package
  local template_dir
  local decoded_dir
  local unsigned_apk
  local aligned_apk
  local signatures_dir
  local output_directory
  local managed_icon_path=""

  kbc_require_clone_package "${clone_package}"
  [[ -n "${app_name}" ]] || kbc_die "アプリ名を入力してください"
  if [[ -n "${icon_path}" ]]; then
    kbc_require_png_icon "${icon_path}"
  fi
  [[ -f "${KBC_APKEDITOR_PATH}" ]] ||
    kbc_die "APKEditorがありません。先にinstall.shを実行してください"

  mkdir -p "${KBC_CACHE_DIR}/work"
  KBC_BUILD_RUN_DIR="$(mktemp -d "${KBC_CACHE_DIR}/work/run.XXXXXX")"
  input_xapk="$(kbc_prepare_xapk "${source}")"

  metadata="$(kbc_read_xapk_metadata "${input_xapk}")"
  IFS=$'\t' read -r \
    source_package \
    KBC_BUILD_VERSION_CODE \
    KBC_BUILD_VERSION_NAME \
    KBC_BUILD_ABI <<<"${metadata}"

  [[ "${source_package}" == "${KBC_ORIGINAL_PACKAGE}" ]] ||
    kbc_die "対象パッケージが違います: ${source_package}"
  [[ "${KBC_BUILD_VERSION_CODE}" =~ ^[0-9]+$ ]] ||
    kbc_die "versionCodeが不正です"

  kbc_info "入力: v${KBC_BUILD_VERSION_NAME} (${KBC_BUILD_VERSION_CODE}) / ${KBC_BUILD_ABI}"
  kbc_check_abi_compatibility "${KBC_BUILD_ABI}" || true

  KBC_BUILD_SOURCE_HASH="$(sha256sum "${input_xapk}" | awk '{print toupper($1)}')"
  kbc_prepare_decoded_template \
    "${input_xapk}" \
    "${KBC_BUILD_SOURCE_HASH}"
  template_dir="${KBC_BUILD_TEMPLATE_DIR}"
  decoded_dir="${KBC_BUILD_RUN_DIR}/decoded"
  unsigned_apk="${KBC_BUILD_RUN_DIR}/clone-unsigned.apk"
  aligned_apk="${KBC_BUILD_RUN_DIR}/clone-aligned.apk"

  kbc_materialize_decoded_template "${template_dir}" "${decoded_dir}"

  kbc_info "1/3 アプリの設定を反映しています"
  kbc_patch_manifest \
    "${decoded_dir}/AndroidManifest.xml" \
    "${clone_package}" \
    "${app_name}"
  if [[ -n "${icon_path}" ]]; then
    kbc_patch_icon "${decoded_dir}" "${icon_path}"
  fi

  signatures_dir="${decoded_dir}/signatures"
  if [[ -d "${signatures_dir}" && "${signatures_dir}" == "${KBC_BUILD_RUN_DIR}/"* ]]; then
    rm -rf -- "${signatures_dir}"
  fi

  kbc_info "2/3 APKを再構築しています"
  java "-Xmx${KBC_JAVA_HEAP:-3g}" -jar "${KBC_APKEDITOR_PATH}" b \
    -i "${decoded_dir}" \
    -o "${unsigned_apk}" \
    -f

  kbc_info "3/3 APKを整列・署名しています"
  kbc_ensure_signing_key
  kbc_align_apk "${unsigned_apk}" "${aligned_apk}"

  output_directory="$(dirname -- "${output_path}")"
  mkdir -p "${output_directory}"
  KBC_BUILD_OUTPUT="$(realpath -m "${output_path}")"
  apksigner sign \
    --ks "${KBC_KEYSTORE_PATH}" \
    --ks-key-alias "${KBC_KEY_ALIAS}" \
    --ks-pass env:KBC_KEY_PASSWORD \
    --key-pass env:KBC_KEY_PASSWORD \
    --v4-signing-enabled false \
    --out "${KBC_BUILD_OUTPUT}" \
    "${aligned_apk}"
  zipalign -c -v 4 "${KBC_BUILD_OUTPUT}" >/dev/null
  apksigner verify --verbose "${KBC_BUILD_OUTPUT}" >/dev/null

  if [[ -n "${icon_path}" ]]; then
    managed_icon_path="$(kbc_store_icon "${icon_path}" "${clone_package}")"
  fi
  KBC_BUILD_ICON_PATH="${managed_icon_path}"
  kbc_registry_upsert \
    "${clone_package}" \
    "${app_name}" \
    "${KBC_BUILD_VERSION_CODE}" \
    "${KBC_BUILD_VERSION_NAME}" \
    "${KBC_BUILD_ABI}" \
    "${KBC_BUILD_SOURCE_HASH}" \
    "$(kbc_timestamp)" \
    "${managed_icon_path}"

  kbc_success "${KBC_BUILD_OUTPUT}"
  kbc_build_cleanup
  KBC_BUILD_RUN_DIR=""
}
