#!/usr/bin/env bash

bench_layout_valid() {
  local apps
  [[ -d "${BENCH_PATH}/apps/frappe" && -x "${BENCH_PATH}/env/bin/python" && -f "${BENCH_PATH}/sites/apps.txt" ]] || return 1
  [[ "$(stat -c '%U:%G' "$BENCH_PATH")" == "${DEFAULT_DEPLOY_USER}:${DEFAULT_DEPLOY_USER}" ]] || return 1
  apps="$(sed '/^[[:space:]]*$/d' "${BENCH_PATH}/sites/apps.txt")"
  [[ "$apps" == frappe ]] || return 1
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
  stage_is_verified 06 && fatal "Previously verified Bench is invalid; operator review required: ${BENCH_PATH}"
  return 1
}

module_apply() {
  local marker="${BENCH_PARENT}/.frappe-deployer-${BENCH_NAME}.initializing"
  bench_target_is_expected || fatal "Bench target does not match the validated expected path."
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
  run_as_deploy_user "Verify Bench environment" env "HOME=/home/${DEFAULT_DEPLOY_USER}" \
    "$BENCH_PATH/env/bin/python" -c 'import frappe; print(frappe.__version__)'
  rm -f -- "$marker"
  BENCH_INIT_MARKER=""
}

module_verify() {
  bench_layout_valid || fatal "Bench initialization did not produce the required layout."
  [[ ! -e "${BENCH_PARENT}/.frappe-deployer-${BENCH_NAME}.initializing" ]] || fatal "Bench initialization marker remains."
  run_as_deploy_user "Verify Bench environment" env "HOME=/home/${DEFAULT_DEPLOY_USER}" \
    "$BENCH_PATH/env/bin/python" -c 'import frappe; print(frappe.__version__)'
}
