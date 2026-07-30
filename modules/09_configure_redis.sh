#!/usr/bin/env bash

redis_config_files() {
  find "${BENCH_PATH}/config" -maxdepth 1 -type f -name 'redis_*.conf' -print | sort
}

redis_managed_files() {
  find "${BENCH_PATH}/config" -maxdepth 1 -type f \( -name 'redis_*.conf' -o -name '*.acl' \) -print | sort
}

redis_path_under() {
  local path="${1:?path required}" parent="${2:?parent required}"
  [[ "$path" == /* && "$path" != *'/../'* && "$path" != *'/./'* && "$path" != */.. && "$path" != */. ]] || return 1
  [[ "$path" == "$parent" || "$path" == "${parent}/"* ]]
}

redis_configs_valid() {
  local config bind port dir pidfile aclfile legacy count=0
  legacy="${BENCH_PARENT}/.frappe-deployer-${BENCH_NAME}.staging"
  while IFS= read -r config; do
    [[ -n "$config" ]] || continue
    count=$((count + 1))
    bind="$(awk '$1 == "bind" {print $2; exit}' "$config")"
    port="$(awk '$1 == "port" {print $2; exit}' "$config")"
    dir="$(awk '$1 == "dir" {print $2; exit}' "$config")"
    pidfile="$(awk '$1 == "pidfile" {print $2; exit}' "$config")"
    aclfile="$(awk '$1 == "aclfile" {print $2; exit}' "$config")"
    [[ "$bind" == "127.0.0.1" || "$bind" == "localhost" ]] || return 1
    [[ "$port" =~ ^[0-9]+$ && "$port" -ge 1024 && "$port" -le 65535 ]] || return 1
    redis_path_under "$dir" "${BENCH_PATH}/config" || return 1
    redis_path_under "$pidfile" "${BENCH_PATH}/config/pids" || return 1
    if [[ -n "$aclfile" ]]; then
      redis_path_under "$aclfile" "${BENCH_PATH}/config" || return 1
      [[ -f "$aclfile" && ! -L "$aclfile" && "$(stat -c '%U:%G' "$aclfile")" == "${DEFAULT_DEPLOY_USER}:${DEFAULT_DEPLOY_USER}" ]] || return 1
    fi
    ! grep -Fq -- "$legacy" "$config" || return 1
    [[ "$(stat -c '%U:%G' "$config")" == "${DEFAULT_DEPLOY_USER}:${DEFAULT_DEPLOY_USER}" ]] || return 1
  done < <(redis_config_files)
  ((count >= 2))
}

module_description() { printf '%s\n' "Configure Bench Redis instances"; }

module_check() {
  redis_configs_valid || return 1
  [[ -f "${BENCH_PATH}/sites/common_site_config.json" ]] || return 1
  jq -e '.redis_cache and .redis_queue' "${BENCH_PATH}/sites/common_site_config.json" >/dev/null
}

module_apply() {
  local config backup status=0
  backup="$(mktemp -d)"
  register_temp_path "$backup"
  while IFS= read -r config; do cp -a -- "$config" "$backup/"; done < <(redis_managed_files)
  run_bench "Generate Bench Redis configuration" setup redis || status=$?
  while IFS= read -r config; do
    chmod 0640 "$config"
    chown "$DEFAULT_DEPLOY_USER:$DEFAULT_DEPLOY_USER" "$config"
  done < <(redis_managed_files)
  if ((status == 0)) && redis_configs_valid; then rm -rf -- "$backup"; return 0; fi
  ((status != 0)) || status=1
  while IFS= read -r config; do rm -f -- "$config"; done < <(redis_managed_files)
  find "$backup" -maxdepth 1 -type f -exec cp -a -- {} "${BENCH_PATH}/config/" \;
  log_error "Bench Redis configuration regeneration failed; restored the previous files (exit ${status})."
  return "$status"
}

module_verify() {
  local cache_url queue_url
  redis_configs_valid || fatal "Bench Redis configuration is missing, unsafe, or invalid."
  cache_url="$(jq -r '.redis_cache // empty' "${BENCH_PATH}/sites/common_site_config.json")"
  queue_url="$(jq -r '.redis_queue // empty' "${BENCH_PATH}/sites/common_site_config.json")"
  [[ "$cache_url" == redis://127.0.0.1:* || "$cache_url" == redis://localhost:* ]] ||
    fatal "Redis cache must use a local endpoint; found ${cache_url}."
  [[ "$queue_url" == redis://127.0.0.1:* || "$queue_url" == redis://localhost:* ]] ||
    fatal "Redis queue must use a local endpoint; found ${queue_url}."
  [[ "$cache_url" != "$queue_url" ]] || fatal "Redis cache and queue cannot share the same endpoint."
}
