#!/usr/bin/env bash
set -uo pipefail

readonly PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
source "${PROJECT_ROOT}/tests/test_helper.sh"
source "${PROJECT_ROOT}/lib/common.sh"

root="$(mktemp -d)"; trap 'rm -rf -- "$root"' EXIT
DEFAULT_DEPLOY_USER="$(id -un)"
BENCH_PARENT="$root/home/frappe"; BENCH_NAME=production; BENCH_PATH="${BENCH_PARENT}/${BENCH_NAME}"
mkdir -p "$BENCH_PATH/config/pids" "$BENCH_PATH/sites"
printf '{"redis_cache":"redis://127.0.0.1:13000","redis_queue":"redis://127.0.0.1:11000"}\n' >"$BENCH_PATH/sites/common_site_config.json"
register_temp_path() { :; }
log_error() { :; }
source "${PROJECT_ROOT}/modules/09_configure_redis.sh"

write_redis_configs() {
  local base="${1:?base required}"
  printf 'bind 127.0.0.1\nport 13000\ndir %s/config\npidfile %s/config/pids/cache.pid\naclfile %s/config/cache.acl\n' "$base" "$base" "$base" >"$BENCH_PATH/config/redis_cache.conf"
  printf 'bind 127.0.0.1\nport 11000\ndir %s/config\npidfile %s/config/pids/queue.pid\n' "$base" "$base" >"$BENCH_PATH/config/redis_queue.conf"
  : >"$BENCH_PATH/config/cache.acl"
}

write_redis_configs "$BENCH_PATH"
assert_success "final-path Redis configuration is valid" redis_configs_valid
write_redis_configs "${BENCH_PARENT}/.frappe-deployer-production.staging"
assert_failure "Redis staging paths make stage 09 invalid" module_check

run_bench() { write_redis_configs "$BENCH_PATH"; }
assert_success "Redis regeneration succeeds" module_apply
assert_success "regenerated Redis paths point only to BENCH_PATH" redis_configs_valid
assert_failure "regenerated Redis configs contain no staging path" grep -Fq "${BENCH_PARENT}/.frappe-deployer-production.staging" "$BENCH_PATH/config/redis_cache.conf" "$BENCH_PATH/config/redis_queue.conf"

printf 'original cache\n' >"$BENCH_PATH/config/redis_cache.conf"
printf 'original queue\n' >"$BENCH_PATH/config/redis_queue.conf"
run_bench() { write_redis_configs "/unknown/path"; }
assert_failure "invalid Redis regeneration is rejected" module_apply
assert_equal "Redis rollback restores previous cache config" "original cache" "$(<"$BENCH_PATH/config/redis_cache.conf")"
assert_equal "Redis rollback restores previous queue config" "original queue" "$(<"$BENCH_PATH/config/redis_queue.conf")"

finish_tests
