#!/usr/bin/env bash
set -u
hook="$(dirname "$0")/rule-cards.py"
repo="$(cd "$(dirname "$0")/../.." && pwd -P)"
failures=0
sandbox="$(mktemp -d)"
trap 'rm -rf "$sandbox"' EXIT
export HOME="$sandbox/home"
export CLAUDE_CONFIG_DIR="$sandbox/config"
export CLAUDE_OLLAMA_RULE_CARDS_DIR="$sandbox/cards"
mkdir -p "$HOME" "$sandbox/cards" "$sandbox/project/web/console/src"

card() {
  local id="$1" body="$2"
  shift 2
  {
    echo '---'
    echo 'triggers:'
    printf '  - %s\n' "$@"
    echo '---'
    printf '%s\n' "$body"
  } > "$CLAUDE_OLLAMA_RULE_CARDS_DIR/$id.md"
}

card shell "Shell scripts stay bash 3.2 compatible; run shellcheck on them." "suffix: .sh"
card go "Run gofmt and go vet; test with table tests." "suffix: .go" "command: go test"
card console "Console: no raw colours in TS; palettes live in globals.css." "path: web/console/"
card commit "Commit messages follow conventional commits: feat:, fix:, chore:." "command: git commit"
card pnpm "Run pnpm as pnpm -C DIR install|add|test; never exec or dlx." "command: pnpm"
card write "Name a new file by what it holds." "tool: Write"
printf -- '---\ntriggers:\n---\nA body without a trigger.\n' > "$sandbox/cards/broken.md"
printf -- '---\ntriggers:\n  - suffix: .rs\n---\n' > "$sandbox/cards/empty.md"

context_for() {
  local session="$1" tool="$2" input="$3"
  python3 -c '
import json, sys
print(json.dumps({"session_id": sys.argv[1], "hook_event_name": "PreToolUse", "cwd": sys.argv[4], "tool_name": sys.argv[2], "tool_input": json.loads(sys.argv[3])}))' "$session" "$tool" "$input" "$sandbox/project" \
    | python3 "$hook" 2>>"$sandbox/stderr" | python3 -c '
import json, sys
raw = sys.stdin.read()
print(json.loads(raw)["hookSpecificOutput"].get("additionalContext", "") if raw.strip() else "")'
}

expect_eq() {
  local label="$1" want="$2" got="$3"
  if [ "$got" != "$want" ]; then
    echo "FAIL: $label (want '$want', got '$got')"
    failures=$((failures + 1))
  fi
}

expect_contains() {
  local label="$1" want="$2" got="$3"
  case "$got" in
    *"$want"*) ;;
    *) echo "FAIL: $label (missing '$want' in '$got')"; failures=$((failures + 1)) ;;
  esac
}

expect_eq "a suffix card is delivered on the first edit of a matching file" \
  "Shell scripts stay bash 3.2 compatible; run shellcheck on them." "$(context_for s1 Edit '{"file_path": "bin/deploy.sh", "old_string": "a", "new_string": "b"}')"
expect_eq "the same card is not delivered twice in a session" "" "$(context_for s1 Edit '{"file_path": "bin/other.sh", "old_string": "a", "new_string": "b"}')"
expect_contains "another session gets the card again" "bash 3.2" "$(context_for s2 Write '{"file_path": "bin/other.sh", "content": "x"}')"
expect_eq "a file with no matching suffix gets nothing" "" "$(context_for s1 Edit '{"file_path": "README.md", "old_string": "a", "new_string": "b"}')"
expect_eq "a path card matches a Read inside the folder, with an absolute path under cwd" \
  "Console: no raw colours in TS; palettes live in globals.css." "$(context_for s1 Read "{\"file_path\": \"$sandbox/project/web/console/src/page.tsx\"}")"
expect_eq "a command card matches the head of a later segment" \
  "Commit messages follow conventional commits: feat:, fix:, chore:." "$(context_for s1 Bash '{"command": "git add -A && git commit -m \"feat: x\""}')"
expect_eq "a command inside an argument is not a match" "" "$(context_for s3 Bash '{"command": "echo git commit"}')"
expect_eq "a one-word command trigger matches the first word" \
  "Run pnpm as pnpm -C DIR install|add|test; never exec or dlx." "$(context_for s1 Bash '{"command": "pnpm -C web/console test"}')"
expect_eq "a command trigger on a go card fires on go test" \
  "Run gofmt and go vet; test with table tests." "$(context_for s1 Bash '{"command": "cd go && go test ./..."}')"
expect_eq "a tool card matches by tool name" "Name a new file by what it holds." "$(context_for s1 Write '{"file_path": "notes.txt", "content": "x"}')"
expect_eq "the state lives under the Claude config dir" yes "$([ -f "$CLAUDE_CONFIG_DIR/cache/rule-cards/s1.json" ] && echo yes || echo no)"
stale_state="$CLAUDE_CONFIG_DIR/cache/rule-cards/stale.json"
printf '{"delivered": []}' > "$stale_state"
touch -t 202001010000 "$stale_state"
context_for s6 Write '{"file_path": "notes.txt", "content": "x"}' > /dev/null
expect_eq "a new session's first delivery prunes week-old state" no "$([ -e "$stale_state" ] && echo yes || echo no)"
expect_contains "a card without triggers is reported on stderr" "broken.md" "$(cat "$sandbox/stderr")"
expect_contains "a card without a body is reported on stderr" "empty.md" "$(cat "$sandbox/stderr")"
expect_eq "the hook never denies" 0 "$(printf '{"session_id":"s9","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"git commit"}}' | python3 "$hook" 2>/dev/null | grep -c permissionDecision)"

mkdir -p "$sandbox/cards2"
export CLAUDE_OLLAMA_RULE_CARDS_DIR="$sandbox/cards2"
filler="$(printf 'x%.0s' $(seq 1 500))"
card console "P $filler" "path: web/console/"
card tsx "S $filler" "suffix: .tsx"
card write "T $filler" "tool: Write"
card commit "C $filler" "command: git commit"
expect_eq "--match orders path before suffix before tool and stops at the byte cap" "console
tsx" "$(python3 "$hook" --match Write '{"file_path": "web/console/a.tsx", "content": ""}')"
first="$(context_for s4 Write '{"file_path": "web/console/a.tsx", "content": ""}')"
expect_eq "the first call carries the two most specific cards" "P $filler

S $filler" "$first"
expect_eq "the next call carries the card that did not fit" "T $filler" "$(context_for s4 Write '{"file_path": "web/console/b.tsx", "content": ""}')"
expect_eq "--match prints nothing when no card matches" "" "$(python3 "$hook" --match Read '{"file_path": "a.rs"}')"

export CLAUDE_OLLAMA_RULE_CARDS_DIR="$sandbox/cards"
export CLAUDE_OLLAMA_RULE_CARDS=0
expect_eq "CLAUDE_OLLAMA_RULE_CARDS=0 turns the hook off" "" "$(context_for s5 Edit '{"file_path": "off.sh", "old_string": "a", "new_string": "b"}')"
expect_eq "the switched-off hook writes no state" no "$([ -e "$CLAUDE_CONFIG_DIR/cache/rule-cards/s5.json" ] && echo yes || echo no)"
expect_eq "--match ignores the switch" "shell" "$(python3 "$hook" --match Edit '{"file_path": "off.sh"}' 2>/dev/null)"
expect_eq "--list ignores the switch" yes "$(python3 "$hook" --list 2>/dev/null | grep -q '^shell:' && echo yes || echo no)"
unset CLAUDE_OLLAMA_RULE_CARDS
expect_contains "the hook is on again without the switch" "bash 3.2" "$(context_for s5 Edit '{"file_path": "off.sh", "old_string": "a", "new_string": "b"}')"
listed="$(python3 "$hook" --list 2>"$sandbox/list-stderr")"
expect_eq "--list exits 1 when a card is malformed" 1 "$(python3 "$hook" --list >/dev/null 2>&1; echo $?)"
expect_contains "--list names a malformed card on stderr" "broken.md" "$(cat "$sandbox/list-stderr")"
expect_eq "--list prints each good card with its triggers" "commit: command git commit
console: path web/console/
go: suffix .go, command go test
pnpm: command pnpm
shell: suffix .sh
write: tool Write" "$listed"
rm "$sandbox/cards/broken.md" "$sandbox/cards/empty.md"
expect_eq "--list exits 0 with only good cards" 0 "$(python3 "$hook" --list >/dev/null 2>&1; echo $?)"

unset CLAUDE_OLLAMA_RULE_CARDS_DIR
export CLAUDE_CUSTOM_HOME="$repo"
expect_eq "without the override the cards come from CLAUDE_CUSTOM_HOME" 0 "$(python3 "$hook" --list >/dev/null 2>&1; echo $?)"
expect_contains "the repo's shell card fires on a .sh edit" "bash 3.2" "$(cat "$repo/ollama/rule-cards/$(python3 "$hook" --match Edit '{"file_path": "x.sh"}' | head -n 1).md")"

if [ "$failures" -eq 0 ]; then
  echo "all passed"
else
  exit 1
fi
