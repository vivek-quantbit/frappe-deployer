#!/usr/bin/env bash
set -uo pipefail

readonly PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
source "${PROJECT_ROOT}/tests/test_helper.sh"
source "${PROJECT_ROOT}/lib/logger.sh"

secret='A-very-secret-value!'
register_secret "$secret"
redacted="$(redact "before ${secret} after")"
assert_equal "registered secret is redacted" 'before [REDACTED] after' "$redacted"
assert_equal "ordinary text is unchanged" 'ordinary output' "$(redact 'ordinary output')"

finish_tests

