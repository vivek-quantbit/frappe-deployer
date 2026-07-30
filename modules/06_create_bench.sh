#!/usr/bin/env bash

legacy_bench_staging_path() { printf '%s\n' "${BENCH_PARENT}/.frappe-deployer-${BENCH_NAME}.staging"; }

env_text_executables_reference() {
  local needle="${1:?path required}"
  find -P "${BENCH_PATH}/env/bin" -maxdepth 1 -type f -perm /111 -exec grep -IlF -- "$needle" {} + 2>/dev/null | grep -q .
}

gunicorn_shebang_valid() {
  local shebang
  IFS= read -r shebang <"${BENCH_PATH}/env/bin/gunicorn" || return 1
  [[ "$shebang" == "#!${BENCH_PATH}/env/bin/python" || "$shebang" == "#!${BENCH_PATH}/env/bin/python "* ]]
}

bench_base_layout_valid() {
  local apps
  [[ -d "${BENCH_PATH}/apps/frappe" && -x "${BENCH_PATH}/env/bin/python" && -f "${BENCH_PATH}/sites/apps.txt" ]] || return 1
  [[ "$(stat -c '%U:%G' "$BENCH_PATH")" == "${DEFAULT_DEPLOY_USER}:${DEFAULT_DEPLOY_USER}" ]] || return 1
  apps="$(sed '/^[[:space:]]*$/d' "${BENCH_PATH}/sites/apps.txt")"
  [[ "$apps" == frappe ]] || return 1
}

bench_layout_valid() {
  bench_base_layout_valid || return 1
  bench_env_contents_safe || return 1
  [[ -x "${BENCH_PATH}/env/bin/gunicorn" && ! -L "${BENCH_PATH}/env/bin/gunicorn" ]] || return 1
  "${BENCH_PATH}/env/bin/python" -c 'import frappe' >/dev/null 2>&1 || return 1
  "${BENCH_PATH}/env/bin/gunicorn" --version >/dev/null 2>&1 || return 1
  gunicorn_shebang_valid || return 1
  ! env_text_executables_reference "$(legacy_bench_staging_path)"
}

verify_bench_environment() {
  run_as_deploy_user "Verify Frappe import" env "HOME=/home/${DEFAULT_DEPLOY_USER}" \
    "$BENCH_PATH/env/bin/python" -c 'import frappe; print(frappe.__version__)' &&
    run_as_deploy_user "Verify Gunicorn executable" env "HOME=/home/${DEFAULT_DEPLOY_USER}" \
      "$BENCH_PATH/env/bin/gunicorn" --version
}

bench_env_contents_safe() {
  local link resolved
  [[ -d "${BENCH_PATH}/env" && ! -L "${BENCH_PATH}/env" ]] || return 1
  ! find -P "${BENCH_PATH}/env" -xdev \( ! -user "$DEFAULT_DEPLOY_USER" -o -type b -o -type c -o -type p -o -type s \) -print -quit | grep -q . || return 1
  while IFS= read -r -d '' link; do
    resolved="$(readlink -f -- "$link")" || return 1
    [[ "$resolved" == "${BENCH_PATH}/env/"* || "$resolved" == /usr/bin/python3 || "$resolved" == /usr/bin/python3.* ]] || return 1
  done < <(find -P "${BENCH_PATH}/env" -xdev -type l -print0)
}

legacy_env_repairable() {
  local legacy shebang
  bench_base_layout_valid || return 1
  bench_env_contents_safe || return 1
  [[ -d "${BENCH_PATH}/env" && ! -L "${BENCH_PATH}/env" && -x "${BENCH_PATH}/env/bin/gunicorn" ]] || return 1
  legacy="$(legacy_bench_staging_path)"
  env_text_executables_reference "$legacy" || return 1
  IFS= read -r shebang <"${BENCH_PATH}/env/bin/gunicorn" || return 1
  [[ "$shebang" == "#!${legacy}/env/bin/python" || "$shebang" == "#!${legacy}/env/bin/python "* ]]
}

module_description() { printf '%s\n' "Create Frappe bench"; }

bench_target_is_expected() {
  [[ "$BENCH_PATH" == "${BENCH_PARENT}/${BENCH_NAME}" && "$BENCH_PATH" != / && ! -L "$BENCH_PATH" ]]
}

bench_contents_safe() {
  [[ -d "$BENCH_PATH" && ! -L "$BENCH_PATH" ]] || return 1
  [[ "$(stat -c '%U:%G' "$BENCH_PATH")" == "${DEFAULT_DEPLOY_USER}:${DEFAULT_DEPLOY_USER}" ]] || return 1
  ! find -P "$BENCH_PATH" -xdev \( ! -user "$DEFAULT_DEPLOY_USER" -o -type l -o -type b -o -type c -o -type p -o -type s \) -print -quit | grep -q .
}

quarantine_partial_bench() {
  local quarantine
  bench_target_is_expected || { fatal "Bench target path is suspicious; operator review required: ${BENCH_PATH}"; return 1; }
  bench_contents_safe || { fatal "Invalid Bench target has suspicious ownership or contents; operator review required."; return 1; }
  quarantine="${BENCH_PARENT}/.${BENCH_NAME}.quarantine-$(date -u +%Y%m%dT%H%M%S.%N)"
  [[ ! -e "$quarantine" ]] || fatal "Quarantine target already exists: ${quarantine}"
  mv -- "$BENCH_PATH" "$quarantine"
  log_warning "Moved interrupted Bench to quarantine: ${quarantine}"
}

recover_interrupted_bench() {
  local expected_marker="${BENCH_PARENT}/.frappe-deployer-${BENCH_NAME}.initializing"
  [[ "$BENCH_INIT_MARKER" == "$expected_marker" && -f "$BENCH_INIT_MARKER" && ! -L "$BENCH_INIT_MARKER" ]] || return 1
  if [[ -e "$BENCH_PATH" ]]; then
    stage_is_verified 06 && return 1
    quarantine_partial_bench || return 1
  fi
  rm -f -- "$BENCH_INIT_MARKER"
  BENCH_INIT_MARKER=""
}

module_check() {
  [[ -e "$BENCH_PATH" ]] || return 1
  if bench_layout_valid; then return 0; fi
  legacy_env_repairable && return 1
  bench_base_layout_valid && fatal "Existing Bench environment is invalid and is not a recognized installer relocation; operator review required: ${BENCH_PATH}"
  stage_is_verified 06 && fatal "Previously verified Bench is invalid; operator review required: ${BENCH_PATH}"
  return 1
}

repair_legacy_bench_env() {
  local original_env="${BENCH_PATH}/env" quarantine failed status=0
  quarantine="${BENCH_PARENT}/.${BENCH_NAME}.env-relocated-$(date -u +%Y%m%dT%H%M%S.%N)"
  failed="${BENCH_PARENT}/.${BENCH_NAME}.env-repair-failed-$(date -u +%Y%m%dT%H%M%S.%N)"
  mv -- "$original_env" "$quarantine"
  log_warning "Moved relocated Bench environment to quarantine: ${quarantine}"
  run_command "Recreate Bench Python environment" runuser --user "$DEFAULT_DEPLOY_USER" -- \
    env --chdir="$BENCH_PATH" "HOME=/home/${DEFAULT_DEPLOY_USER}" "PATH=${BENCH_COMMAND_PATH}" \
    "$BENCH_EXECUTABLE" setup env --python /usr/bin/python3 </dev/null || status=$?
  if ((status == 0)); then
    run_command "Reinstall Bench Python requirements" runuser --user "$DEFAULT_DEPLOY_USER" -- \
      env --chdir="$BENCH_PATH" "HOME=/home/${DEFAULT_DEPLOY_USER}" "PATH=${BENCH_COMMAND_PATH}" \
      "$BENCH_EXECUTABLE" setup requirements --python </dev/null || status=$?
  fi
  if ((status == 0)) && bench_layout_valid && verify_bench_environment; then
    log_success "Recreated relocated Bench environment at ${BENCH_PATH}/env"
    return 0
  fi
  ((status != 0)) || status=1
  [[ ! -e "$original_env" ]] || mv -- "$original_env" "$failed"
  mv -- "$quarantine" "$original_env"
  log_error "Bench environment repair failed; restored the original environment (exit ${status})."
  return "$status"
}

module_apply() {
  local marker="${BENCH_PARENT}/.frappe-deployer-${BENCH_NAME}.initializing"
  bench_target_is_expected || fatal "Bench target does not match the validated expected path."
  if [[ -e "$BENCH_PATH" ]] && legacy_env_repairable; then
    repair_legacy_bench_env || fatal "Could not repair the relocated Bench environment."
    return
  fi
  if [[ -e "$BENCH_PATH" ]]; then quarantine_partial_bench; fi
  [[ ! -e "$marker" || ( -f "$marker" && ! -L "$marker" && "$(stat -c %U "$marker")" == root ) ]] ||
    fatal "Bench initialization marker is suspicious; operator review required: ${marker}"
  install -d -o "$DEFAULT_DEPLOY_USER" -g "$DEFAULT_DEPLOY_USER" -m 0750 "$BENCH_PARENT"
  install -o root -g root -m 0600 /dev/null "$marker"
  BENCH_INIT_MARKER="$marker"
  # Bench must not inherit the installer's caller directory. EOF also prevents an interactive rollback prompt.
  run_command "Initialize ${FRAPPE_BRANCH} bench" runuser --user "$DEFAULT_DEPLOY_USER" -- \
    env --chdir="$BENCH_PARENT" "HOME=/home/${DEFAULT_DEPLOY_USER}" "PATH=${BENCH_COMMAND_PATH}" \
    "$BENCH_EXECUTABLE" init --frappe-branch "$FRAPPE_BRANCH" --python /usr/bin/python3 "$BENCH_PATH" </dev/null
  bench_layout_valid || fatal "Bench initialization did not produce the required Frappe-only layout."
  verify_bench_environment || fatal "Bench Python or Gunicorn verification failed."
  rm -f -- "$marker"
  BENCH_INIT_MARKER=""
}

module_verify() {
  bench_layout_valid || fatal "Bench initialization did not produce the required layout."
  [[ ! -e "${BENCH_PARENT}/.frappe-deployer-${BENCH_NAME}.initializing" ]] || fatal "Bench initialization marker remains."
  verify_bench_environment || fatal "Bench Python or Gunicorn verification failed."
}
