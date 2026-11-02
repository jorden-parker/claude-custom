#!/usr/bin/env bash
set -u
cd "$(dirname "$0")" || exit 1
failures=0

check() {
  local label="$1"
  shift
  if ! "$@"; then
    echo "FAIL: $label"
    failures=$((failures + 1))
  fi
}

check "load_user is defined in lib/users.sh" grep -q '^load_user() {' lib/users.sh
check "bin/greet calls load_user" grep -q 'load_user' bin/greet
check "bin/whoami-by-id calls load_user" grep -q 'load_user' bin/whoami-by-id
check "fetch_user is gone" test -z "$(grep -rl 'fetch_user' lib bin)"
check "greet still prints the name" test "$(bash bin/greet 1)" = "hello, ada"
check "whoami-by-id still prints the name" test "$(bash bin/whoami-by-id 2)" = "2 is grace"
check "an unknown id still says unknown" test "$(bash bin/greet 9)" = "hello, unknown"

if [ "$failures" -eq 0 ]; then
  echo "all passed"
else
  echo "$failures failed"
  exit 1
fi
