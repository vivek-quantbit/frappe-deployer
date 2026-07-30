#!/usr/bin/env bash

TEMP_PATHS=()
ACTIVE_CHILD_PID=""
ACTIVE_CHILD_DESCRIPTION=""
BENCH_INIT_MARKER=""
COMMAND_HEARTBEAT_SECONDS="${COMMAND_HEARTBEAT_SECONDS:-15}"

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
    [[ ! -e "$path" ]] || { if [[ -d "$path" ]]; then rm -rf -- "$path"; else rm -f -- "$path"; fi; }
  done
  if [[ -n "$BENCH_INIT_MARKER" ]] && declare -F recover_interrupted_bench >/dev/null; then
    recover_interrupted_bench || true
  fi
}

format_elapsed() {
  local seconds="${1:?seconds required}"
  printf '%02d:%02d:%02d' "$((seconds / 3600))" "$(((seconds % 3600) / 60))" "$((seconds % 60))"
}

cancel_active_command() {
  local signal="${1:?signal required}" status="${2:?status required}"
  trap - INT TERM
  if [[ -n "$ACTIVE_CHILD_PID" ]] && kill -0 "$ACTIVE_CHILD_PID" 2>/dev/null; then
    log_warning "Cancellation requested; stopping: ${ACTIVE_CHILD_DESCRIPTION}"
    kill -s "$signal" -- "-${ACTIVE_CHILD_PID}" 2>/dev/null || kill -s "$signal" "$ACTIVE_CHILD_PID" 2>/dev/null || true
    wait "$ACTIVE_CHILD_PID" 2>/dev/null || true
  else
    log_warning "Cancellation requested."
  fi
  ACTIVE_CHILD_PID=""
  exit "$status"
}

on_error() {
  local exit_code=$? line="${1:-unknown}" command="${2:-unknown}"
  # ERR traps are inherited by command-substitution subshells because the CLI
  # enables errtrace. Let the parent command report the failure exactly once.
  if ((BASH_SUBSHELL > 0)); then
    return "$exit_code"
  fi
  trap - ERR
  log_error "Stage '${CURRENT_STAGE_NAME}' failed at line ${line} (exit ${exit_code}): $(redact "$command")" || true
  if [[ -n "$LOG_FILE" ]]; then
    log_error "See log: ${LOG_FILE}" || true
  fi
  exit "$exit_code"
}

install_traps() {
  trap 'on_error "$LINENO" "$BASH_COMMAND"' ERR
  trap cleanup EXIT
  trap 'cancel_active_command INT 130' INT
  trap 'cancel_active_command TERM 143' TERM
}

_run_command() {
  local stream_output="${1:?stream flag required}"
  shift
  local description="${1:?description required}"
  shift
  local started now status fifo tee_pid next_heartbeat
  started="$(date +%s)"
  next_heartbeat=$((started + COMMAND_HEARTBEAT_SECONDS))
  log_info "$description"
  if [[ "$stream_output" == 1 ]]; then
    log_debug "Command: $(printf '%q ' "$@")"
  fi
  fifo="$(mktemp "${TMPDIR:-/tmp}/frappe-deployer-output.XXXXXX")"
  rm -f -- "$fifo"
  mkfifo -m 0600 "$fifo"
  if [[ "$stream_output" == 1 ]]; then
    tee -a "$LOG_FILE" <"$fifo" &
  elif [[ "$stream_output" == 2 ]]; then
    cat <"$fifo" >/dev/null &
  else
    cat >>"$LOG_FILE" <"$fifo" &
  fi
  tee_pid=$!
  setsid "$@" >"$fifo" 2>&1 &
  ACTIVE_CHILD_PID=$!
  ACTIVE_CHILD_DESCRIPTION="$description"
  rm -f -- "$fifo"
  while kill -0 "$ACTIVE_CHILD_PID" 2>/dev/null; do
    sleep 0.1 & wait $! || true
    now="$(date +%s)"
    if kill -0 "$ACTIVE_CHILD_PID" 2>/dev/null && ((now >= next_heartbeat)); then
      log_info "Still running: ${description} (elapsed $(format_elapsed "$((now - started))"))"
      next_heartbeat=$((now + COMMAND_HEARTBEAT_SECONDS))
    fi
  done
  if wait "$ACTIVE_CHILD_PID"; then status=0; else status=$?; fi
  ACTIVE_CHILD_PID=""
  ACTIVE_CHILD_DESCRIPTION=""
  wait "$tee_pid" || true
  now="$(date +%s)"
  if ((status == 0)); then
    log_info "Completed: ${description} (elapsed $(format_elapsed "$((now - started))"))"
  else
    log_error "Command failed: ${description} (exit ${status}, elapsed $(format_elapsed "$((now - started))"))"
  fi
  return "$status"
}

run_command() {
  _run_command 1 "$@"
}

run_sensitive_command() {
  local description="${1:?description required}"
  shift
  _run_command 2 "$description" "$@"
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

bench_environment() {
  printf '%s\n' "HOME=/home/${DEFAULT_DEPLOY_USER}" "PATH=${BENCH_COMMAND_PATH}"
}

git_as_deploy_user() {
  runuser --user "$DEFAULT_DEPLOY_USER" -- env --chdir="${BENCH_PATH}/apps/frappe" \
    "HOME=/home/${DEFAULT_DEPLOY_USER}" PATH="/usr/local/bin:/usr/bin:/bin" git "$@"
}

run_bench_at() {
  local bench_path="${1:?bench path required}" description="${2:?description required}"
  shift 2
  run_command "$description" runuser --user "$DEFAULT_DEPLOY_USER" -- \
    env --chdir="$bench_path" "HOME=/home/${DEFAULT_DEPLOY_USER}" \
    "PATH=${BENCH_COMMAND_PATH}" "$BENCH_EXECUTABLE" "$@" </dev/null
}

run_bench() {
  local description="${1:?description required}"
  shift
  run_bench_at "$BENCH_PATH" "$description" "$@"
}

run_sensitive_bench() {
  local description="${1:?description required}"
  shift
  run_sensitive_command "$description" runuser --user "$DEFAULT_DEPLOY_USER" -- \
    env --chdir="$BENCH_PATH" "HOME=/home/${DEFAULT_DEPLOY_USER}" \
    "PATH=${BENCH_COMMAND_PATH}" "$BENCH_EXECUTABLE" "$@" </dev/null
}

bench_default_site() {
  jq -er '.default_site // empty' "${BENCH_PATH}/sites/common_site_config.json" 2>/dev/null
}
