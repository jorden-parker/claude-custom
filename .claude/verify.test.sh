#!/usr/bin/env bash
set -u
verify="$(cd "$(dirname "$0")" && pwd)/verify"
failures=0
sandbox="$(mktemp -d)"
trap 'rm -rf "$sandbox"' EXIT

mkdir -p "$sandbox/.claude" "$sandbox/stubs"
cp "$verify" "$sandbox/.claude/verify"
cat > "$sandbox/stubs/make" <<STUB
#!/bin/sh
echo "make \$*" >> "$sandbox/run.log"
STUB
chmod +x "$sandbox/stubs/make"

add_test() {
  mkdir -p "$sandbox/$(dirname "$1")"
  printf '#!/bin/sh\necho "%s" >> "%s/run.log"\nexit %s\n' "$1" "$sandbox" "${2:-0}" > "$sandbox/$1"
  chmod +x "$sandbox/$1"
}

for test in shared/hooks/edit-check.test.sh shared/hooks/fallow-a.test.sh shared/hooks/fallow-b.test.sh \
  personal/install.test.sh bin/claude-ollama.test.sh bin/ollama-profiles.test.sh .claude/verify.test.sh \
  ollama/drafts/opener.test.sh shared/mcp/repo-tools.test.sh; do
  add_test "$test"
done

run_verify() {
  rm -f "$sandbox/run.log"
  PATH="$sandbox/stubs:$PATH" "$sandbox/.claude/verify" "$@" >/dev/null 2>&1
}

ran() {
  tr '\n' '|' < "$sandbox/run.log"
}

check_ran() {
  local label="$1" want="$2"
  shift 2
  run_verify "$@"
  if [ "$(ran)" != "$want" ]; then
    echo "FAIL: $label: expected [$want] got [$(ran)]"
    failures=$((failures + 1))
  fi
}

checks="make --no-print-directory check-json check-config check-profiles"

check_ran 'no files runs everything' 'make test|'
check_ran 'hook runs its sibling test' "$checks|shared/hooks/edit-check.test.sh|" shared/hooks/edit-check.py
check_ran 'a test file runs itself' "$checks|shared/hooks/edit-check.test.sh|" shared/hooks/edit-check.test.sh
check_ran 'script without extension' "$checks|bin/ollama-profiles.test.sh|" bin/ollama-profiles
check_ran 'file without a test runs checks only' "$checks|" README.md
check_ran 'tests run once' "$checks|shared/hooks/edit-check.test.sh|" shared/hooks/edit-check.py shared/hooks/edit-check.test.sh
check_ran 'go files run go tests' "$checks test-go|" go/internal/picker/ui/model.go
check_ran 'fallow lib runs every fallow test' "$checks|shared/hooks/fallow-a.test.sh|shared/hooks/fallow-b.test.sh|" shared/hooks/fallow-lib.sh
check_ran 'installer runs install and launcher tests' "$checks|bin/claude-ollama.test.sh|personal/install.test.sh|" bin/claude-custom
check_ran 'ollama config runs launcher tests' "$checks|bin/claude-ollama.test.sh|" ollama/sizes.json
check_ran 'personal files run install tests' "$checks|personal/install.test.sh|" personal/claude.sh
check_ran 'shared settings run install tests' "$checks|personal/install.test.sh|" shared/settings/hooks.json
check_ran 'draft opener runs its tests and the launcher tests' "$checks|bin/claude-ollama.test.sh|ollama/drafts/opener.test.sh|" ollama/drafts/opener.py
check_ran 'draft store runs the repo tools tests' "$checks|shared/mcp/repo-tools.test.sh|" shared/mcp/draft_store.py
check_ran 'verify runs its own test' "$checks|.claude/verify.test.sh|" .claude/verify
check_ran 'makefile runs everything' 'make test|' Makefile README.md

add_test personal/install.test.sh 1
run_verify personal/claude.sh
status=$?
[ "$status" -eq 1 ] || { echo "FAIL: failing test exits 1 (got $status)"; failures=$((failures + 1)); }
check_ran 'failing test does not stop the others' "$checks|bin/claude-ollama.test.sh|personal/install.test.sh|" bin/claude-custom

if [ "$failures" -eq 0 ]; then echo "all passed"; else echo "$failures failed"; exit 1; fi
