#!/usr/bin/env bash

TEMP_PATHS=()

require_root() {
  [[ "$EUID" -eq 0 ]] || fatal "Run this command as root (use sudo)."
}

require_command() {
  command -v "${1:?command required}" >/dev/null 2>&1 || fatal "Required command not found: $1"
}

register_temp_path() { TEMP_PATHS+=("${1:?temporary path required}"); }

cleanup() {
  local path
  for path in "${TEMP_PATHS[@]}"; do
    [[ -e "$path" ]] && rm -f -- "$path"
  done
}

on_error() {
  local exit_code=$? line="${1:-unknown}" command="${2:-unknown}"
  trap - ERR
  log_error "Stage '${CURRENT_STAGE_NAME}' failed at line ${line} (exit ${exit_code}): $(redact "$command")"
  [[ -n "$LOG_FILE" ]] && log_error "See log: ${LOG_FILE}"
  exit "$exit_code"
}

install_traps() {
  trap 'on_error "$LINENO" "$BASH_COMMAND"' ERR
  trap cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
}

run_command() {
  local description="${1:?description required}"
  shift
  log_info "$description"
  log_debug "Command: $(printf '%q ' "$@")"
  "$@" >>"$LOG_FILE" 2>&1
}

run_sensitive_command() {
  local description="${1:?description required}"
  shift
  log_info "$description"
  "$@" >>"$LOG_FILE" 2>&1
}

retry_command() {
  local attempts="${1:?attempt count required}" delay="${2:?delay required}" description="${3:?description required}"
  shift 3
  local attempt=1
  until run_command "${description} (attempt ${attempt}/${attempts})" "$@"; do
    ((attempt >= attempts)) && return 1
    sleep "$delay"
    attempt=$((attempt + 1))
  done
}

version_major() { "${1:?command required}" --version 2>&1 | sed -En 's/[^0-9]*([0-9]+).*/\1/p' | head -n1; }

atomic_install_file() {
  local source="${1:?source required}" target="${2:?target required}" mode="${3:-0644}" owner="${4:-root}" group="${5:-root}"
  local target_dir temp
  target_dir="$(dirname "$target")"
  install -d -m 0755 "$target_dir"
  temp="$(mktemp "${target_dir}/.$(basename "$target").XXXXXX")"
  register_temp_path "$temp"
  install -o "$owner" -g "$group" -m "$mode" "$source" "$temp"
  if [[ -f "$target" ]] && cmp -s "$temp" "$target"; then
    rm -f -- "$temp"
    return 1
  fi
  mv -f "$temp" "$target"
  return 0
}

run_as_deploy_user() {
  local description="${1:?description required}"
  shift
  run_command "$description" runuser --user "$DEFAULT_DEPLOY_USER" -- "$@"
}

run_bench() {
  local description="${1:?description required}"
  shift
  run_command "$description" runuser --user "$DEFAULT_DEPLOY_USER" -- \
    env --chdir="$BENCH_PATH" HOME="/home/${DEFAULT_DEPLOY_USER}" \
    PATH="/usr/local/bin:/usr/bin:/bin" "$BENCH_LINK" "$@"
}

run_sensitive_bench() {
  local description="${1:?description required}"
  shift
  run_sensitive_command "$description" runuser --user "$DEFAULT_DEPLOY_USER" -- \
    env --chdir="$BENCH_PATH" HOME="/home/${DEFAULT_DEPLOY_USER}" \
    PATH="/usr/local/bin:/usr/bin:/bin" "$BENCH_LINK" "$@"
}
