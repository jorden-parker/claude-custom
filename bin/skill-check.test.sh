#!/usr/bin/env bash
set -u
repo="$(cd "$(dirname "$0")/.." && pwd -P)"
skill_check="$repo/bin/skill-check"
sandbox="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$sandbox"' EXIT
project="$sandbox/project"
mkdir -p "$project" "$sandbox/bin"
failures=0

check() {
  local label="$1"
  shift
  if ! "$@"; then
    echo "FAIL: $label"
    failures=$((failures + 1))
  fi
}

cat >"$sandbox/bin/claude" <<'EOF'
#!/usr/bin/env bash
[ "$1" = "--version" ] && echo "2.1.316 (Claude Code)"
EOF
cat >"$sandbox/bin/launcher" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$PWD" "$*" "no-index=${CLAUDE_OLLAMA_NO_INDEX:-}" "drafts=${CLAUDE_OLLAMA_OPEN_DRAFTS:-}" >"$LAUNCH_RECORD"
echo '{"type":"system","subtype":"hook_started"}'
echo '{"type":"system","subtype":"init","skills":["deploy","handoff",7]}'
echo "launcher keeps running" >&2
sleep 60
EOF
cat >"$sandbox/bin/launcher-no-init" <<'EOF'
#!/usr/bin/env bash
echo "model qwen3.8-27b-cc is missing" >&2
echo "pull it with: claude-ollama prepare 27b" >&2
exit 1
EOF
cat >"$sandbox/bin/launcher-slow" <<'EOF'
#!/usr/bin/env bash
sleep 60
EOF
chmod +x "$sandbox/bin/"*
export PATH="$sandbox/bin:$PATH" CLAUDE_BIN="$sandbox/bin/claude" LAUNCH_RECORD="$sandbox/launch.txt"

started="$(date +%s)"
output="$(CLAUDE_OLLAMA_LAUNCHER="$sandbox/bin/launcher" "$skill_check" --size 35b "$project")"
status=$?
elapsed=$(( $(date +%s) - started ))
check "a found init line exits 0" [ "$status" = 0 ]
check "the skills come from the init line, strings only" \
  [ "$(printf '%s' "$output" | jq -c '.skills')" = '["deploy","handoff"]' ]
check "the claude version is reported" \
  [ "$(printf '%s' "$output" | jq -r '.claude_version')" = "2.1.316 (Claude Code)" ]
check "no error is reported" [ "$(printf '%s' "$output" | jq -r '.error')" = null ]
check "the launcher runs in the folder" [ "$(sed -n 1p "$LAUNCH_RECORD")" = "$project" ]
check "the launcher gets the size and the print flags" \
  [ "$(sed -n 2p "$LAUNCH_RECORD")" = "35b -p hi --max-turns 1 --output-format stream-json --verbose" ]
check "the launch skips the indexer and the draft opener" \
  [ "$(sed -n 3,4p "$LAUNCH_RECORD" | tr '\n' ' ')" = "no-index=1 drafts=0 " ]
check "the launcher is stopped once the init line arrived" [ "$elapsed" -lt 20 ]
launcher_stopped() {
  ! pgrep -f "$sandbox/bin/launcher" >/dev/null
}
check "the launcher's sleep was killed with it" launcher_stopped

output="$(CLAUDE_OLLAMA_LAUNCHER="$sandbox/bin/launcher-no-init" "$skill_check" "$project")"
status=$?
check "an exit without init exits 1" [ "$status" = 1 ]
check "the error carries the stderr tail" \
  [ "$(printf '%s' "$output" | jq -r '.error')" = "claude exited before its session started: model qwen3.8-27b-cc is missing | pull it with: claude-ollama prepare 27b" ]
check "skills are null on failure" [ "$(printf '%s' "$output" | jq -c '.skills')" = null ]

output="$(CLAUDE_OLLAMA_LAUNCHER="$sandbox/bin/launcher-slow" "$skill_check" --timeout 1 "$project")"
check "a silent launcher times out" \
  [ "$(printf '%s' "$output" | jq -r '.error')" = "no session started within 1s" ]

output="$(CLAUDE_OLLAMA_LAUNCHER="$sandbox/bin/launcher" "$skill_check" "$sandbox/missing")"
status=$?
check "a missing folder exits 1 without launching" [ "$status" = 1 ]
check "a missing folder is named" \
  [ "$(printf '%s' "$output" | jq -r '.error')" = "$sandbox/missing is not a folder" ]

output="$(CLAUDE_OLLAMA_LAUNCHER="$sandbox/bin/no-such-launcher" "$skill_check" "$project")"
check "a launcher that cannot start is reported" \
  grep -q "could not start $sandbox/bin/no-such-launcher" <<<"$(printf '%s' "$output" | jq -r '.error')"

if [ "$failures" = 0 ]; then
  echo "all passed"
else
  exit 1
fi
