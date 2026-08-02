#!/data/data/com.termux/files/usr/bin/bash

kbc_android_device_abis() {
  getprop ro.product.cpu.abilist 2>/dev/null || true
}

kbc_android_launch_app() {
  local package_name="$1"
  kbc_info "アプリを起動します: ${package_name}"
  # PackageManagerの一覧照会を避け、既知のActivityを明示起動する。
  am start -n \
    "${package_name}/jp.co.ponos.battlecats.MyActivity"
}

kbc_android_open_app_details() {
  local package_name="$1"
  am start \
    -a android.settings.APPLICATION_DETAILS_SETTINGS \
    -d "package:${package_name}"
}

kbc_android_request_uninstall() {
  local package_name="$1"
  am start \
    -a android.intent.action.DELETE \
    -d "package:${package_name}"
}

kbc_android_open_store() {
  local package_name="$1"
  local store_url="https://play.google.com/store/apps/details?id=${package_name}"

  if command -v termux-open-url >/dev/null 2>&1; then
    termux-open-url "${store_url}"
  else
    am start -a android.intent.action.VIEW -d "${store_url}"
  fi
}

kbc_android_install_apk() {
  local apk_path="$1"
  [[ -f "${apk_path}" ]] || kbc_die "APKが見つかりません: ${apk_path}"
  kbc_configure_termux_integration
  kbc_info "Androidのインストーラーを開きます"
  termux-open \
    --view \
    --content-type application/vnd.android.package-archive \
    "${apk_path}" ||
    kbc_die 'Androidのインストーラーを開けませんでした。Termuxの「不明なアプリのインストール」を許可してください'
}

kbc_android_warn_package_query_limit() {
  kbc_warn "Androidの制限により、Termux単体ではインストール状態を一覧取得できません。"
  kbc_warn "起動、アプリ情報、更新、アンインストールは管理画面から実行できます。"
}
