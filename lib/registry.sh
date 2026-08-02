#!/data/data/com.termux/files/usr/bin/bash

kbc_registry_initialize() {
  mkdir -p "$(dirname -- "${KBC_REGISTRY_FILE}")"
  touch "${KBC_REGISTRY_FILE}"
  chmod 600 "${KBC_REGISTRY_FILE}" 2>/dev/null || true
}

kbc_registry_list() {
  kbc_registry_initialize
  awk -F '\t' 'NF >= 7 { print }' "${KBC_REGISTRY_FILE}"
}

kbc_registry_find() {
  local package_name="$1"
  kbc_registry_initialize
  awk -F '\t' -v package_name="${package_name}" \
    '$1 == package_name { print; found = 1; exit } END { if (!found) exit 1 }' \
    "${KBC_REGISTRY_FILE}"
}

kbc_registry_upsert() {
  local package_name
  local app_name
  local version_code
  local version_name
  local abi
  local source_hash
  local updated_at
  local icon_path
  local temporary_file

  package_name="$(kbc_sanitize_record_field "$1")"
  app_name="$(kbc_sanitize_record_field "$2")"
  version_code="$(kbc_sanitize_record_field "$3")"
  version_name="$(kbc_sanitize_record_field "$4")"
  abi="$(kbc_sanitize_record_field "$5")"
  source_hash="$(kbc_sanitize_record_field "$6")"
  updated_at="$(kbc_sanitize_record_field "$7")"
  icon_path="$(kbc_sanitize_record_field "${8:-}")"
  source_hash="${source_hash:--}"
  icon_path="${icon_path:--}"

  kbc_registry_initialize
  temporary_file="$(mktemp "${KBC_STATE_DIR}/registry.XXXXXX")"
  awk -F '\t' -v package_name="${package_name}" \
    '$1 != package_name { print }' \
    "${KBC_REGISTRY_FILE}" >"${temporary_file}"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "${package_name}" \
    "${app_name}" \
    "${version_code}" \
    "${version_name}" \
    "${abi}" \
    "${source_hash}" \
    "${updated_at}" \
    "${icon_path}" >>"${temporary_file}"
  mv "${temporary_file}" "${KBC_REGISTRY_FILE}"
  chmod 600 "${KBC_REGISTRY_FILE}" 2>/dev/null || true
}

kbc_registry_remove() {
  local package_name="$1"
  local temporary_file

  kbc_registry_initialize
  temporary_file="$(mktemp "${KBC_STATE_DIR}/registry.XXXXXX")"
  awk -F '\t' -v package_name="${package_name}" \
    '$1 != package_name { print }' \
    "${KBC_REGISTRY_FILE}" >"${temporary_file}"
  mv "${temporary_file}" "${KBC_REGISTRY_FILE}"
}

kbc_registry_next_identity() {
  local index=1
  local package_name
  local package_suffix
  local app_name

  while true; do
    if ((index == 1)); then
      package_suffix="${KBC_DEFAULT_PACKAGE_SUFFIX}"
      app_name="${KBC_DEFAULT_NAME}"
    else
      package_suffix="clone${index}"
      app_name="${KBC_DEFAULT_NAME} ${index}"
    fi
    package_name="$(kbc_package_from_suffix "${package_suffix}")"

    if ! kbc_registry_find "${package_name}" >/dev/null 2>&1; then
      printf '%s\t%s\n' "${package_name}" "${app_name}"
      return 0
    fi
    ((index += 1))
  done
}

kbc_registry_count() {
  kbc_registry_list | awk 'END { print NR + 0 }'
}
