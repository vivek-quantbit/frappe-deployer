#!/usr/bin/env bash

TESTS_RUN=0
TESTS_FAILED=0

pass() { TESTS_RUN=$((TESTS_RUN + 1)); printf 'PASS  %s\n' "$1"; }
fail() { TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1)); printf 'FAIL  %s\n' "$1" >&2; }

assert_success() {
  local description="${1:?description required}"
  shift
  if ( "$@" ) >/dev/null 2>&1; then pass "$description"; else fail "$description"; fi
}

assert_failure() {
  local description="${1:?description required}"
  shift
  if ( "$@" ) >/dev/null 2>&1; then fail "$description"; else pass "$description"; fi
}

assert_equal() {
  local description="${1:?description required}" expected="${2-}" actual="${3-}"
  if [[ "$expected" == "$actual" ]]; then pass "$description"; else fail "$description (expected '${expected}', got '${actual}')"; fi
}

finish_tests() {
  printf '\nTests: %d, failures: %d\n' "$TESTS_RUN" "$TESTS_FAILED"
  ((TESTS_FAILED == 0))
}
