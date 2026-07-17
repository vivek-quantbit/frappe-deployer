#!/usr/bin/env bash

site_exists() { [[ -f "${BENCH_PATH}/sites/${SITE_NAME}/site_config.json" ]]; }

site_count() {
  find "${BENCH_PATH}/sites" -mindepth 2 -maxdepth 2 -name site_config.json -printf '%h\n' | wc -l
}

site_apps() {
  runuser --user "$DEFAULT_DEPLOY_USER" -- env --chdir="$BENCH_PATH" \
    "HOME=/home/${DEFAULT_DEPLOY_USER}" "PATH=${BENCH_COMMAND_PATH}" \
    "$BENCH_EXECUTABLE" --site "$SITE_NAME" list-apps 2>/dev/null | sed '/^[[:space:]]*$/d'
}

module_description() { printf '%s\n' "Create and configure Frappe site"; }

module_check() {
  site_exists || return 1
  [[ "$(site_count)" == "1" ]] || fatal "Phase 1 requires exactly one site in the bench."
  [[ "$(site_apps)" == "frappe" ]] || fatal "The existing site contains unexpected applications."
  return 1
}

module_apply() {
  if ! site_exists; then
    [[ "$(site_count)" == "0" ]] || fatal "A different site already exists in this Phase 1 bench."
    run_sensitive_bench "Create site ${SITE_NAME}" new-site "$SITE_NAME" \
      --db-root-username root \
      --db-root-password "$DB_ROOT_PASSWORD" \
      --admin-password "$ADMIN_PASSWORD" \
      --no-mariadb-socket
  fi
  run_bench "Set ${SITE_NAME} as the default site" use "$SITE_NAME"
  run_bench "Set site timezone to ${TIMEZONE}" --site "$SITE_NAME" set-config time_zone "$TIMEZONE"
  run_bench "Run site migrations" --site "$SITE_NAME" migrate
  run_bench "Enable site scheduler" --site "$SITE_NAME" enable-scheduler
}

module_verify() {
  local apps configured_timezone current_site
  site_exists || fatal "Site configuration was not created."
  [[ "$(site_count)" == "1" ]] || fatal "Expected exactly one site."
  apps="$(site_apps)"
  [[ "$apps" == "frappe" ]] || fatal "Expected only Frappe on the site; found: ${apps//$'\n'/, }"
  configured_timezone="$(jq -r '.time_zone // empty' "${BENCH_PATH}/sites/${SITE_NAME}/site_config.json")"
  [[ "$configured_timezone" == "$TIMEZONE" ]] || fatal "Site timezone is not configured correctly."
  jq -e '(.pause_scheduler // 0) == 0' "${BENCH_PATH}/sites/${SITE_NAME}/site_config.json" >/dev/null ||
    fatal "Site scheduler remains paused."
  current_site="$(tr -d '[:space:]' <"${BENCH_PATH}/sites/currentsite.txt")"
  [[ "$current_site" == "$SITE_NAME" ]] || fatal "Default site is ${current_site}, expected ${SITE_NAME}."
  run_bench "Verify site database access" --site "$SITE_NAME" execute frappe.get_installed_apps
}
