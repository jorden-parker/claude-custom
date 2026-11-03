#!/usr/bin/env bash
set -u
hooks="$(cd "$(dirname "$0")" && pwd)"
sandbox="$(mktemp -d)"
trap 'rm -rf "$sandbox"' EXIT
failures=0

expect_eq() {
  if [ "$3" != "$2" ]; then
    echo "FAIL: $1 (want '$2', got '$3')"
    failures=$((failures + 1))
  fi
}

default_of() {
  python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); from profile_env import catalogue_default; print(catalogue_default(sys.argv[2]))' "$1" "$2" 2>&1 | tail -1
}

expect_eq "the handoff threshold defaults to the catalogue's 70" 70 "$(default_of "$hooks" CLAUDE_OLLAMA_HANDOFF_PCT)"
expect_eq "the after-edit test mode defaults to the catalogue's suggest" suggest "$(default_of "$hooks" CLAUDE_OLLAMA_TEST_AFTER_EDIT)"

mkdir -p "$sandbox/shared/hooks"
cp "$hooks/profile_env.py" "$sandbox/shared/hooks/"
printf '%s' '[{"key":"CLAUDE_OLLAMA_HANDOFF_PCT","kind":"integer","default":"55"}]' > "$sandbox/shared/profile-env.json"
expect_eq "the default comes from shared/profile-env.json beside the hooks folder" 55 "$(default_of "$sandbox/shared/hooks" CLAUDE_OLLAMA_HANDOFF_PCT)"
expect_eq "a key the catalogue lacks is an error" "KeyError: 'CLAUDE_OLLAMA_MISSING'" "$(default_of "$sandbox/shared/hooks" CLAUDE_OLLAMA_MISSING)"

if [ "$failures" -eq 0 ]; then
  echo "all passed"
else
  echo "$failures failed"
  exit 1
fi
