#!/usr/bin/env bash

declare -a REGISTERED_SECRETS=()
LOG_FILE=""

register_secret() {
  local secret="${1:-}"
  [[ -n "$secret" ]] && REGISTERED_SECRETS+=("$secret")
}

redact() {
  local value="${1:-}"
  local secret
  for secret in "${REGISTERED_SECRETS[@]}"; do
    [[ -n "$secret" ]] && value="${value//${secret}/[REDACTED]}"
  done
  printf '%s' "$value"
}

log_init() {
  local log_dir="${1:?log directory required}"
  install -d -m 0750 "$log_dir"
  LOG_FILE="${log_dir}/deploy-$(date '+%Y%m%d-%H%M%S').log"
  install -m 0640 /dev/null "$LOG_FILE"
}

_log() {
  local level="${1:?level required}"
  shift
  local message timestamp line
  message="$(redact "$*")"
  timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
  line="[${timestamp}] [${level}] ${message}"
  printf '%s\n' "$line" >&2
  [[ -n "$LOG_FILE" ]] && printf '%s\n' "$line" >>"$LOG_FILE"
}

log_debug() { [[ "${FRAPPE_DEPLOYER_DEBUG:-0}" == "1" ]] && _log DEBUG "$@" || true; }
log_info() { _log INFO "$@"; }
log_success() { _log OK "$@"; }
log_warning() { _log WARN "$@"; }
log_error() { _log ERROR "$@"; }
fatal() { log_error "$@"; exit 1; }

