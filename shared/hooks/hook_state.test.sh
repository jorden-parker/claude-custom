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
  else
    echo "ok: $1"
  fi
}

py() {
  CLAUDE_CONFIG_DIR="$sandbox/config" python3 -c "import sys; sys.path.insert(0, '$hooks'); import hook_state; $1" 2>&1 | tail -1
}

expect_eq "a written state reads back" '{"a": 1}' "$(py 'p = hook_state.state_path("k", "s1"); hook_state.write_state(p, {"a": 1}); print(__import__("json").dumps(hook_state.read_state(p, {})))')"
expect_eq "a missing file reads as the empty state" '{"n": 0}' "$(py 'import json; print(json.dumps(hook_state.read_state(hook_state.state_path("k", "none"), {"n": 0})))')"

corrupt="$sandbox/config/cache/k/bad.json"
mkdir -p "$(dirname "$corrupt")"
printf 'not json' > "$corrupt"
expect_eq "a corrupt file reads as the empty state" '{"n": 0}' "$(py "import json; print(json.dumps(hook_state.read_state(__import__('pathlib').Path('$corrupt'), {'n': 0})))")"
printf '[1]' > "$corrupt"
expect_eq "a non-object file reads as the empty state" '{"n": 0}' "$(py "import json; print(json.dumps(hook_state.read_state(__import__('pathlib').Path('$corrupt'), {'n': 0})))")"

expect_eq "mutating a read state leaves the empty template alone" '{"l": []}' "$(py 'import json; e = {"l": []}; s = hook_state.read_state(hook_state.state_path("k", "none"), e); s["l"].append(1); print(json.dumps(e))')"

expect_eq "a hostile id stays inside the folder" "$sandbox/config/cache/k" "$(py 'print(hook_state.state_path("k", "../../x/y").parent)')"
expect_eq "an empty id is nosession" "nosession.json" "$(py 'print(hook_state.state_path("k", "").name)')"

py 'p = hook_state.state_path("k", "mode"); hook_state.write_state(p, {"a": 1})' > /dev/null
mode="$(python3 -c "import os; print(oct(os.stat('$sandbox/config/cache/k/mode.json').st_mode & 0o777))")"
expect_eq "the state file is 0600" "0o600" "$mode"
dirmode="$(python3 -c "import os; print(oct(os.stat('$sandbox/config/cache/k').st_mode & 0o777))")"
expect_eq "the state folder is 0700" "0o700" "$dirmode"

counter="$sandbox/config/cache/k/counter.json"
for _ in $(seq 20); do
  CLAUDE_CONFIG_DIR="$sandbox/config" python3 -c "
import sys
sys.path.insert(0, '$hooks')
import hook_state
p = hook_state.state_path('k', 'counter')
with hook_state.update_state(p, {'n': 0}) as s:
    s['n'] += 1
" &
done
wait
expect_eq "20 parallel updates all land" '{"n": 20}' "$(cat "$counter")"

old="$sandbox/config/cache/prune/old.json"
new="$sandbox/config/cache/prune/new.json"
oldsnap="$sandbox/config/cache/prune/old.snapshots"
mkdir -p "$(dirname "$old")" "$oldsnap"
printf '{}' > "$old"
printf '{}' > "$new"
touch -t 202001010000 "$old" "$oldsnap"
py 'hook_state.prune("prune")' > /dev/null
expect_eq "prune removes an old file" "missing" "$([ -e "$old" ] && echo present || echo missing)"
expect_eq "prune removes an old snapshots folder" "missing" "$([ -e "$oldsnap" ] && echo present || echo missing)"
expect_eq "prune keeps a new file" "present" "$([ -e "$new" ] && echo present || echo missing)"

if [ "$failures" -eq 0 ]; then
  echo "all passed"
else
  echo "$failures failed"
  exit 1
fi
