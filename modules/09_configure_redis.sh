#!/usr/bin/env bash

redis_config_files() {
  find "${BENCH_PATH}/config" -maxdepth 1 -type f -name 'redis_*.conf' -print | sort
}

redis_configs_valid() {
  local config bind port count=0
  while IFS= read -r config; do
    [[ -n "$config" ]] || continue
    count=$((count + 1))
    bind="$(awk '$1 == "bind" {print $2; exit}' "$config")"
    port="$(awk '$1 == "port" {print $2; exit}' "$config")"
    [[ "$bind" == "127.0.0.1" || "$bind" == "localhost" ]] || return 1
    [[ "$port" =~ ^[0-9]+$ && "$port" -ge 1024 && "$port" -le 65535 ]] || return 1
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
  run_bench "Generate Bench Redis configuration" setup redis
  local config
  while IFS= read -r config; do
    chmod 0640 "$config"
    chown "$DEFAULT_DEPLOY_USER:$DEFAULT_DEPLOY_USER" "$config"
  done < <(redis_config_files)
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

