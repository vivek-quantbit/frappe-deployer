#!/usr/bin/env bash

mariadb_client_file() {
  local output_variable="${1:?output variable required}" file escaped_password
  file="$(mktemp)"
  chmod 0600 "$file"
  register_temp_path "$file"
  escaped_password="${DB_ROOT_PASSWORD//\\/\\\\}"
  escaped_password="${escaped_password//\"/\\\"}"
  {
    printf '[client]\n'
    printf 'user=root\n'
    printf 'password="%s"\n' "$escaped_password"
    printf 'protocol=socket\n'
  } >"$file"
  printf -v "$output_variable" '%s' "$file"
}

mariadb_password_works() {
  local client_file
  mariadb_client_file client_file
  mariadb --defaults-extra-file="$client_file" --batch --skip-column-names -e 'SELECT 1' 2>/dev/null | grep -qx '1'
}

module_description() { printf '%s\n' "Configure and secure MariaDB"; }

module_check() {
  [[ -f "$MARIADB_CONFIG_TARGET" ]] || return 1
  cmp -s "$MARIADB_CONFIG_SOURCE" "$MARIADB_CONFIG_TARGET" || return 1
  systemctl is-active --quiet mariadb || return 1
  mariadb_password_works || return 1
  local client_file
  mariadb_client_file client_file
  [[ "$(mariadb --defaults-extra-file="$client_file" --batch --skip-column-names -e 'SELECT @@character_set_server')" == "utf8mb4" ]] || return 1
}

configure_root_password() {
  local escaped_password sql_file
  escaped_password="${DB_ROOT_PASSWORD//\\/\\\\}"
  escaped_password="${escaped_password//\'/\\\'}"
  sql_file="$(mktemp)"
  chmod 0600 "$sql_file"
  register_temp_path "$sql_file"
  {
    printf "ALTER USER 'root'@'localhost' IDENTIFIED BY '%s';\n" "$escaped_password"
    printf "DELETE FROM mysql.user WHERE User='';\n"
    printf "DROP DATABASE IF EXISTS test;\n"
    printf "DELETE FROM mysql.db WHERE Db='test' OR Db LIKE 'test\\_%%';\n"
    printf 'FLUSH PRIVILEGES;\n'
  } >"$sql_file"

  if mariadb --protocol=socket --user=root <"$sql_file" >>"$LOG_FILE" 2>&1; then
    return 0
  fi
  local client_file
  mariadb_client_file client_file
  mariadb --defaults-extra-file="$client_file" <"$sql_file" >>"$LOG_FILE" 2>&1 ||
    fatal "Could not authenticate as MariaDB root using socket or supplied password."
}

module_apply() {
  local changed=0
  if atomic_install_file "$MARIADB_CONFIG_SOURCE" "$MARIADB_CONFIG_TARGET" 0644 root root; then
    changed=1
  fi
  mariadbd --verbose --help >>"$LOG_FILE" 2>&1 || fatal "MariaDB rejected the managed configuration."
  if ((changed)); then
    run_command "Restart MariaDB with Frappe configuration" systemctl restart mariadb
  else
    run_command "Start MariaDB" systemctl start mariadb
  fi
  log_info "Configure MariaDB root authentication and remove unsafe defaults"
  configure_root_password
}

module_verify() {
  local client_file charset collation row_format anonymous_count test_count
  systemctl is-active --quiet mariadb || fatal "MariaDB is not active."
  mariadb_password_works || fatal "MariaDB root password authentication failed."
  mariadb_client_file client_file
  charset="$(mariadb --defaults-extra-file="$client_file" --batch --skip-column-names -e 'SELECT @@character_set_server')"
  collation="$(mariadb --defaults-extra-file="$client_file" --batch --skip-column-names -e 'SELECT @@collation_server')"
  row_format="$(mariadb --defaults-extra-file="$client_file" --batch --skip-column-names -e 'SELECT @@innodb_default_row_format')"
  anonymous_count="$(mariadb --defaults-extra-file="$client_file" --batch --skip-column-names -e "SELECT COUNT(*) FROM mysql.user WHERE User=''")"
  test_count="$(mariadb --defaults-extra-file="$client_file" --batch --skip-column-names -e "SELECT COUNT(*) FROM information_schema.schemata WHERE schema_name='test'")"
  [[ "$charset" == "utf8mb4" ]] || fatal "MariaDB server character set is ${charset}, expected utf8mb4."
  [[ "$collation" == "utf8mb4_unicode_ci" ]] || fatal "MariaDB collation is ${collation}, expected utf8mb4_unicode_ci."
  [[ "${row_format,,}" == "dynamic" ]] || fatal "MariaDB row format is ${row_format}, expected dynamic."
  [[ "$anonymous_count" == "0" && "$test_count" == "0" ]] || fatal "MariaDB unsafe defaults were not fully removed."
}
