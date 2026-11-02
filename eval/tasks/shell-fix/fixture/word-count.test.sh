#!/usr/bin/env bash
set -u
cd "$(dirname "$0")" || exit 1
failures=0
sample="$(mktemp)"
trap 'rm -f "$sample"' EXIT

check() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" != "$actual" ]; then
    echo "FAIL: $label (expected $expected, got $actual)"
    failures=$((failures + 1))
  fi
}

printf 'one two three\nfour five\n' > "$sample"
check "two lines of words" 5 "$(bash ./word-count.sh "$sample")"
printf 'alpha\n' > "$sample"
check "one word" 1 "$(bash ./word-count.sh "$sample")"
printf 'a b c d e f g\n' > "$sample"
check "seven words on one line" 7 "$(bash ./word-count.sh "$sample")"

if [ "$failures" -eq 0 ]; then
  echo "all passed"
else
  echo "$failures failed"
  exit 1
fi
