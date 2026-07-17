#!/usr/bin/env bash

validate_bench_name() {
  local value="${1:-}"
  [[ "$value" =~ ^[A-Za-z0-9][A-Za-z0-9_-]{1,62}$ ]] ||
    fatal "Invalid bench name. Use 2-63 letters, numbers, underscores, or hyphens."
}

validate_site_name() {
  local value="${1:-}"
  [[ ${#value} -le 253 ]] || fatal "Site name is longer than 253 characters."
  [[ "$value" =~ ^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)*[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$ ]] ||
    fatal "Invalid site name. Supply a lowercase DNS-compatible hostname."
}

validate_timezone() {
  local value="${1:-}"
  [[ -f "/usr/share/zoneinfo/${value}" && "$value" != *".."* ]] ||
    fatal "Invalid timezone: ${value}"
}

validate_password() {
  local label="${1:?label required}" value="${2:-}"
  [[ ${#value} -ge 12 ]] || fatal "${label} must contain at least 12 characters."
  [[ "$value" != *$'\n'* && "$value" != *$'\r'* ]] || fatal "${label} cannot contain line breaks."
}

validate_bench_parent() {
  local value="${1:-}" protected
  [[ "$value" == /* ]] || fatal "Bench path must be absolute."
  [[ "$value" != *".."* ]] || fatal "Bench path cannot contain '..'."
  for protected in "${PROTECTED_BENCH_PARENTS[@]}"; do
    [[ "$value" != "$protected" ]] || fatal "Unsafe bench path: ${value}"
  done
}

validate_inputs() {
  SITE_NAME="${SITE_NAME,,}"
  validate_bench_name "$BENCH_NAME"
  validate_site_name "$SITE_NAME"
  validate_timezone "$TIMEZONE"
  validate_bench_parent "$BENCH_PARENT"
  validate_password "Database root password" "$DB_ROOT_PASSWORD"
  validate_password "Site administrator password" "$ADMIN_PASSWORD"
}

