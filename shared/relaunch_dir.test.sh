#!/usr/bin/env bash
set -u
here="$(cd "$(dirname "$0")" && pwd)"
module="$here/relaunch_dir.py"
failures=0
sandbox="$(mktemp -d)"
root="$sandbox/relaunch"
sleeper_pids=""
cleanup() {
  local pid
  for pid in $sleeper_pids; do kill "$pid" 2>/dev/null; done
  rm -rf "$sandbox"
}
trap cleanup EXIT

mkdir -p "$sandbox/stubbin"
cat > "$sandbox/stubbin/ps" <<'EOF'
#!/bin/sh
echo "${STUB_PS_COMM:-/usr/local/bin/node}"
EOF
chmod +x "$sandbox/stubbin/ps"
export PATH="$sandbox/stubbin:$PATH"
unset CLAUDE_OLLAMA_RELAUNCH_DIR

expect() {
  if [ "$2" = "$3" ]; then return 0; fi
  echo "FAIL: $1"
  echo "  expected: $2"
  echo "  actual:   $3"
  failures=$((failures + 1))
}

contains() {
  case "$1" in
    *"$2"*) echo yes ;;
    *) echo no ;;
  esac
}

cli() {
  python3 "$module" "$@"
}

start_sleeper() {
  sleeper_pid="$(sleep 60 >/dev/null 2>&1 & echo $!)"
  sleeper_pids="$sleeper_pids $sleeper_pid"
}

sleeper_alive() {
  sleep 0.2
  kill -0 "$sleeper_pid" 2>/dev/null && echo yes || echo no
}

dead_pid() {
  local pid
  pid="$(sh -c 'echo $$')"
  echo "$pid"
}

mode_of() {
  stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"
}

own="$$"
dead="$(dead_pid)"
mkdir -p "$root/$dead" "$root/not-a-pid"
start_sleeper
live="$sleeper_pid"
mkdir -p "$root/$live"
dir="$(cli prepare --root "$root" --pid "$own")"
expect "prepare prints the folder for the pid" "$root/$own" "$dir"
expect "prepare makes the folder private" 700 "$(mode_of "$dir")"
expect "prepare makes the root private" 700 "$(mode_of "$root")"
expect "prepare removes a dead launcher's folder" no "$([ -d "$root/$dead" ] && echo yes || echo no)"
expect "prepare keeps a live launcher's folder" yes "$([ -d "$root/$live" ] && echo yes || echo no)"
expect "prepare keeps a folder that is not a pid" yes "$([ -d "$root/not-a-pid" ] && echo yes || echo no)"

for name in relaunch ladder ladder-up embed-off heartbeat-fast; do : > "$dir/$name"; done
cli prepare --root "$root" --pid "$own" >/dev/null
leftover="$(ls "$dir")"
expect "prepare clears every signal file" "" "$leftover"

cli --dir "$dir" request ladder '{"rung":"context-down","context":49152,"reason":"3 truncations"}'
expect "request writes a private file" 600 "$(mode_of "$dir/ladder")"
cli --dir "$dir" has ladder
expect "has finds a pending request" 0 "$?"
taken="$(cli --dir "$dir" take ladder)"
expect "take prints the request" '{"rung": "context-down", "context": 49152, "reason": "3 truncations"}' "$taken"
expect "take consumes the request" no "$([ -e "$dir/ladder" ] && echo yes || echo no)"
cli --dir "$dir" take ladder >/dev/null
expect "take of a missing request fails" 1 "$?"
cli --dir "$dir" has ladder
expect "has misses a consumed request" 1 "$?"

CLAUDE_OLLAMA_RELAUNCH_DIR="$dir" cli request relaunch '{"note":"/n.md","prompt":"fix it","percent":71}'
taken="$(CLAUDE_OLLAMA_RELAUNCH_DIR="$dir" cli take relaunch)"
expect "the env var names the folder" '{"note": "/n.md", "prompt": "fix it", "percent": 71}' "$taken"

cli --dir "$dir" request relaunch '{"note":"/n.md","prompt":"","percent":null}'
taken="$(cli --dir "$dir" take relaunch)"
expect "a relaunch without a percent is valid" '{"note": "/n.md", "prompt": "", "percent": null}' "$taken"

error="$(cli --dir "$dir" request ladder '{"rung":"context-down","reason":"x"}' 2>&1)"
expect "request refuses a missing field" 2 "$?"
expect "the refusal names the field" yes "$(contains "$error" context)"
expect "a refused request writes nothing" no "$([ -e "$dir/ladder" ] && echo yes || echo no)"
cli --dir "$dir" request ladder-up '{"rung":"embeddings-off","reason":"x","extra":1}' 2>/dev/null
expect "request refuses an unknown field" 2 "$?"
cli --dir "$dir" request ladder '{"rung":"context-down","context":"big","reason":"x"}' 2>/dev/null
expect "request refuses a wrong type" 2 "$?"
cli --dir "$dir" request embed-off '{}' 2>/dev/null
expect "request refuses a flag" 2 "$?"
cli --dir "$dir" request bogus '{}' 2>/dev/null
expect "request refuses an unknown name" 2 "$?"

printf '{"rung": "context-' > "$dir/ladder"
error="$(cli --dir "$dir" take ladder 2>&1)"
expect "take of a malformed request fails" 1 "$?"
expect "a malformed request is removed" no "$([ -e "$dir/ladder" ] && echo yes || echo no)"
expect "a malformed request is reported" yes "$(contains "$error" ladder)"

cli --dir "$dir" raise embed-off
cli --dir "$dir" has embed-off
expect "raise sets a flag" 0 "$?"
expect "a flag survives being read" yes "$([ -e "$dir/embed-off" ] && echo yes || echo no)"
cli --dir "$dir" lower embed-off
cli --dir "$dir" has embed-off
expect "lower clears a flag" 1 "$?"
cli --dir "$dir" raise ladder 2>/dev/null
expect "raise refuses a request" 2 "$?"

expect "path names a signal file" "$dir/heartbeat-fast" "$(cli --dir "$dir" path heartbeat-fast)"

cli --root "$root" --pid "$live" request ladder-up '{"rung":"embeddings-off","reason":"promoted"}'
expect "root and pid name another launcher's folder" yes "$([ -e "$root/$live/ladder-up" ] && echo yes || echo no)"
error="$(cli --root "$root" --pid "$dead" request ladder-up '{"rung":"embeddings-off","reason":"promoted"}' 2>&1)"
expect "a request to a missing folder fails" 3 "$?"
expect "the failure names the folder" yes "$(contains "$error" "$root/$dead")"
cli has ladder 2>/dev/null
expect "no folder at all is a usage error" 2 "$?"

start_sleeper
cli --dir "$dir" claude-pid "$sleeper_pid"
expect "claude-pid records the pid" "$sleeper_pid" "$(cat "$dir/claude.pid")"

signal() {
  python3 - "$here" "$dir" <<'EOF'
import sys
sys.path.insert(0, sys.argv[1])
from relaunch_dir import RelaunchDir
RelaunchDir(sys.argv[2]).terminate_claude()
EOF
}

STUB_PS_COMM=/usr/bin/vim signal
expect "terminate spares a process that is not claude" yes "$(sleeper_alive)"
STUB_PS_COMM=/usr/local/bin/node signal
expect "terminate stops a node process" no "$(sleeper_alive)"
rm -f "$dir/claude.pid"
signal
expect "terminate without a pid file is quiet" 0 "$?"

imported="$(CLAUDE_OLLAMA_RELAUNCH_DIR="$dir" python3 - "$here" <<'EOF'
import sys
sys.path.insert(0, sys.argv[1])
from relaunch_dir import RelaunchDir
folder = RelaunchDir.from_env()
folder.request("ladder-up", {"rung": "context-down", "reason": "quiet"})
print(folder.has("ladder-up"), folder.take("ladder-up")["rung"], folder.has("ladder-up"))
EOF
)"
expect "the module works through import" "True context-down False" "$imported"
expect "from_env is None without the env var" None "$(python3 -c "import sys; sys.path.insert(0, '$here'); from relaunch_dir import RelaunchDir; print(RelaunchDir.from_env())")"

if [ "$failures" -eq 0 ]; then
  echo "all passed"
else
  exit 1
fi
