#!/usr/bin/env bash

nginx_source_config() { printf '%s\n' "${BENCH_PATH}/config/nginx.conf"; }

nginx_site_status() {
  curl --silent --show-error --output /dev/null --write-out '%{http_code}' \
    --resolve "${SITE_NAME}:80:127.0.0.1" --max-time 10 "http://${SITE_NAME}/" 2>/dev/null
}

nginx_site_healthy() {
  local status
  status="$(nginx_site_status || true)"
  [[ "$status" =~ ^(200|204|301|302|303|307|308)$ ]]
}

module_description() { printf '%s\n' "Configure Nginx reverse proxy"; }

module_check() {
  [[ -f "$(nginx_source_config)" && -f "$NGINX_CONFIG_TARGET" ]] || return 1
  cmp -s "$(nginx_source_config)" "$NGINX_CONFIG_TARGET" || return 1
  nginx -t >/dev/null 2>&1 || return 1
  systemctl is-active --quiet nginx || return 1
  nginx_site_healthy
}

module_apply() {
  local source changed=0 default_link="/etc/nginx/sites-enabled/default" backup="" had_existing=0
  run_bench "Generate Nginx production configuration" setup nginx
  source="$(nginx_source_config)"
  [[ -s "$source" ]] || fatal "Bench did not generate Nginx configuration."
  if [[ -f "$NGINX_CONFIG_TARGET" ]]; then
    backup="$(mktemp)"
    register_temp_path "$backup"
    cp -a "$NGINX_CONFIG_TARGET" "$backup"
    had_existing=1
  fi
  if atomic_install_file "$source" "$NGINX_CONFIG_TARGET" 0644 root root; then
    changed=1
  fi
  if ! nginx -t >>"$LOG_FILE" 2>&1; then
    if ((had_existing)); then cp -a "$backup" "$NGINX_CONFIG_TARGET"; else rm -f -- "$NGINX_CONFIG_TARGET"; fi
    fatal "Nginx rejected the generated configuration; the previous configuration was restored."
  fi
  if [[ -L "$default_link" && "$(readlink -f "$default_link")" == "/etc/nginx/sites-available/default" ]]; then
    unlink "$default_link"
    changed=1
    log_info "Disabled the Ubuntu default Nginx site"
  fi
  run_command "Enable and start Nginx" systemctl enable --now nginx
  if ((changed)); then
    run_command "Reload Nginx configuration" systemctl reload nginx
  fi
}

module_verify() {
  local status
  nginx -t >>"$LOG_FILE" 2>&1 || fatal "Nginx configuration validation failed."
  systemctl is-active --quiet nginx || fatal "Nginx is not active."
  systemctl is-enabled --quiet nginx || fatal "Nginx is not enabled."
  status="$(nginx_site_status || true)"
  [[ "$status" =~ ^(200|204|301|302|303|307|308)$ ]] ||
    fatal "Site failed Nginx HTTP verification with status ${status:-unreachable}."
}
