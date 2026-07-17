#!/usr/bin/env bash
set -uo pipefail

readonly PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
source "${PROJECT_ROOT}/tests/test_helper.sh"
source "${PROJECT_ROOT}/lib/constants.sh"
source "${PROJECT_ROOT}/lib/logger.sh"
source "${PROJECT_ROOT}/lib/validation.sh"

fatal() { exit 1; }

assert_success "valid bench name" validate_bench_name production_1
assert_success "valid hyphenated bench name" validate_bench_name production-bench
assert_failure "bench name rejects slash" validate_bench_name '../bench'
assert_failure "bench name rejects whitespace" validate_bench_name 'bad bench'
assert_failure "bench name rejects one character" validate_bench_name x

assert_success "valid fully-qualified site" validate_site_name frappe.example.com
assert_success "valid single-label site" validate_site_name localhost
assert_failure "site rejects uppercase" validate_site_name Frappe.example.com
assert_failure "site rejects underscore" validate_site_name frappe_site.example.com
assert_failure "site rejects empty label" validate_site_name frappe..example.com

assert_success "valid timezone" validate_timezone Asia/Kolkata
assert_failure "timezone rejects traversal" validate_timezone ../../etc/passwd
assert_failure "timezone rejects unknown value" validate_timezone Mars/Olympus

assert_success "password accepts twelve characters" validate_password Password '123456789012'
assert_failure "password rejects short value" validate_password Password 'short'
assert_failure "password rejects newline" validate_password Password $'long-password\nvalue'

assert_success "safe custom bench parent" validate_bench_parent /opt/frappe
assert_failure "bench parent must be absolute" validate_bench_parent relative/path
assert_failure "bench parent rejects traversal" validate_bench_parent /opt/../root
assert_failure "bench parent rejects system root" validate_bench_parent /
assert_failure "bench parent rejects broad opt" validate_bench_parent /opt

finish_tests
