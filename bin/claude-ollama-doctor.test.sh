#!/usr/bin/env bash
set -u
repo="$(cd "$(dirname "$0")/.." && pwd -P)"
real_python3="$(command -v python3)"
failures=0
sandboxes=""
system_tools=""

remove_sandboxes() {
  local dir
  local PATH=/usr/bin:/bin
  for dir in $sandboxes; do
    chmod -R u+w "$dir" 2>/dev/null
    rm -rf "$dir"
  done
}

. "$repo/shared/testing/stub-llama-lib.sh"
stub_dir="$(made="$(mktemp -d)" && cd "$made" && pwd -P)" || exit 1
stub_state="$stub_dir/state.json"
sandboxes="$sandboxes $stub_dir"
trap 'stop_stub_llama; remove_sandboxes' EXIT

default_stub_state() {
  awk '/^\[/ && $0 != "[*]" { print substr($0, 2, length($0) - 2) }' "$repo/ollama/models.ini" |
    jq -Rn '{models_max: 2, models: ([inputs | {key: ., value: (if . == "qwen3-embedding-0.6b" then {aliases: ["qwen3-embedding:0.6b"]} else {} end)}] | from_entries)}'
}

stub_state_set() {
  jq "$1" "$stub_state" > "$stub_state.new" && mv "$stub_state.new" "$stub_state"
}

default_stub_state > "$stub_state"
start_stub_llama "$stub_state" || exit 1
stub_url="$LLAMA_SERVER_URL"

fail() {
  echo "FAIL: $1"
  failures=$((failures + 1))
}

check_eq() {
  if [ "$2" != "$3" ]; then
    fail "$1: expected [$2] got [$3]"
  fi
}

check_that() {
  local name="$1"
  shift
  "$@" || fail "$name"
}

check_not() {
  local name="$1"
  shift
  if "$@"; then
    fail "$name"
  fi
}

build_system_tools() {
  local entry name
  system_tools="$(made="$(mktemp -d)" && cd "$made" && pwd -P)" || exit 1
  sandboxes="$sandboxes $system_tools"
  for entry in /usr/bin/* /bin/*; do
    name="${entry##*/}"
    if [ -x "$entry" ] && [ ! -e "$system_tools/$name" ]; then
      ln -s "$entry" "$system_tools/$name"
    fi
  done
  ln -sf "$real_python3" "$system_tools/python3"
}

write_stub() {
  cat > "$sandbox/stubbin/$1"
  chmod +x "$sandbox/stubbin/$1"
}

write_stubs() {
  write_stub shasum <<EOF
#!/bin/sh
if [ -n "\${STUB_SHASUM_DIGEST:-}" ]; then
  echo "\$STUB_SHASUM_DIGEST  \$3"
  exit 0
fi
name="\${3##*/}"
echo "\$(jq -r --arg name "/\$name" 'to_entries[] | select(.key | endswith(\$name)) | .value' "$repo/ollama/model-digests.json" | head -n 1)  \$3"
EOF
  write_stub gguf-inspect <<EOF
#!/bin/sh
case "\$*" in *--json*) cat "$sandbox/inspect-json" 2>/dev/null ;; esac
exit 0
EOF
  write_stub incident-watcher <<'EOF'
#!/bin/sh
echo ok
EOF
}

new_sandbox() {
  sandbox="$(made="$(mktemp -d)" && cd "$made" && pwd -P)" || exit 1
  sandboxes="$sandboxes $sandbox"
  export HOME="$sandbox/home"
  mkdir -p "$HOME" "$sandbox/stubbin"
  unset NVM_DIR XDG_CONFIG_HOME CLAUDE_CONSOLE_STATE_DIRCLAUDE_TOOL_TELEMETRY CLAUDE_OLLAMA_TELEMETRY CMUX_SOCKET_PATH CLAUDE_OLLAMA_CMUX
  unset STUB_SHASUM_DIGEST STUB_MEMSIZE STUB_WIRED_LIMIT_MB CLAUDE_OLLAMA_LEASE CLAUDE_OLLAMA_FIT
  export CLAUDE_OLLAMA_MANAGED_SETTINGS="$sandbox/managed-settings.json"
  export CLAUDE_OLLAMA_MEMINFO="$sandbox/no-meminfo"
  export CLAUDE_OLLAMA_INCIDENT_WATCHER="$sandbox/stubbin/incident-watcher"
  export CLAUDE_OLLAMA_GGUF_INSPECT="$sandbox/stubbin/gguf-inspect"
  export LLAMA_SERVER_PLIST="$sandbox/no-agent.plist"
  export CLAUDE_OLLAMA_WEIGHTS_DIR="$sandbox/weights"
  write_stubs
  mkdir -p "$CLAUDE_OLLAMA_WEIGHTS_DIR"
  for weights_file in $(jq -r '.[] | .gguf.file // empty' "$repo/ollama/sizes.json") "$(jq -r .gguf.file "$repo/ollama/embedding.json")"; do
    : > "$CLAUDE_OLLAMA_WEIGHTS_DIR/$weights_file"
  done
  default_stub_state > "$stub_state"
  : > "$STUB_LLAMA_LOG"
  "$repo/bin/ollama-profiles" --user-presets >/dev/null
  [ -n "$system_tools" ] || build_system_tools
  export PATH="$sandbox/stubbin:$system_tools"
}

copy_repo() {
  mkdir -p "$1"
  cp -R "$repo/bin" "$repo/shared" "$repo/ollama" "$1/"
}

run_capture() {
  "$@" >"$sandbox/out" 2>"$sandbox/err"
}

run_doctor() {
  run_capture "$@" "${doctor:-$repo/bin/claude-ollama-doctor}" 27b
}

new_sandbox
run_doctor
check_eq "doctor healthy exit status" 0 "$?"
check_that "doctor reports jq" grep -qxF "ok   jq on PATH" "$sandbox/out"
check_that "doctor reports the server build and address" grep -qxF "ok   llama-server build 11429 on ${stub_url#http://}" "$sandbox/out"
check_that "doctor reports the size's preset" grep -qxF "ok   preset qwen3.8-27b-cc listed" "$sandbox/out"
check_that "doctor reports the embedding preset" grep -qxF "ok   preset qwen3-embedding:0.6b listed" "$sandbox/out"
check_that "doctor reports the weights match their pin" grep -qxF "ok   weights Qwen3.8-27B-UD-Q4_K_XL.gguf (sha256 matches)" "$sandbox/out"
check_that "doctor reports the embedding weights" grep -qxF "ok   embedding weights Qwen3-Embedding-0.6B-Q8_0.gguf (sha256 matches)" "$sandbox/out"
check_that "doctor reports the user presets are current" grep -qxF "ok   user presets current" "$sandbox/out"
check_that "doctor reports context sizes agree" grep -qxF "ok   num_ctx 65536 matches CLAUDE_CODE_MAX_CONTEXT_TOKENS 65536; Claude Code compacts at 44344 tokens" "$sandbox/out"
check_that "doctor reports hooks" grep -qxF "ok   hook stop-verify.py present" "$sandbox/out"
check_that "doctor reports no managed model allowlist" grep -qxF "ok   no managed availableModels restricts qwen3.8-27b-cc" "$sandbox/out"
check_that "doctor reports the browser tools" grep -q 'browser tools' "$sandbox/out"
check_not "doctor never mentions sandbox-runtime" grep -q 'sandbox-runtime' "$sandbox/out"
check_not "doctor loads no model" grep -q '"/models/load"' "$STUB_LLAMA_LOG"
STUB_SHASUM_DIGEST=0000 run_doctor
check_eq "doctor with weights that miss their pin exit status" 1 "$?"
check_that "doctor fails weights that miss their pin" grep -qxF "fail weights Qwen3.8-27B-UD-Q4_K_XL.gguf does not match its pin (claude-ollama prepare 27b)" "$sandbox/out"

run_doctor
check_that "doctor skips the classifier check without a server log" grep -qxF "ok   incident classifier not checked (no server log)" "$sandbox/out"
server_log="$HOME/.claude-ollama/logs/llama-server.log"
mkdir -p "${server_log%/*}"
cp "$repo/ollama/incidents/fixtures/llama-server-log.txt" "$server_log"
real_watcher=(env CLAUDE_OLLAMA_INCIDENT_WATCHER="$repo/ollama/incidents/watcher.py")
run_doctor "${real_watcher[@]}"
check_eq "doctor with a server log the classifier reads exit status" 0 "$?"
check_that "doctor reports the classifier matches the server log" grep -qxF "ok   incident classifier matches the server log (rules: 7)" "$sandbox/out"
check_that "doctor counts the rule cards" grep -qxF "ok   rule cards: $(ls "$repo"/ollama/rule-cards/*.md | wc -l | tr -d ' ')" "$sandbox/out"
mkdir -p "$sandbox/cards"
printf -- '---\ntriggers:\n---\nno trigger\n' > "$sandbox/cards/broken.md"
printf -- '---\ntriggers:\n  - suffix: .sh\n---\nshell\n' > "$sandbox/cards/shell.md"
run_doctor "${real_watcher[@]}" CLAUDE_OLLAMA_RULE_CARDS_DIR="$sandbox/cards"
check_eq "doctor with a malformed rule card exit status" 0 "$?"
check_that "doctor warns about a malformed rule card" grep -qxF "warn rule cards: 1 ok, skipping broken.md: no triggers" "$sandbox/out"
check_that "doctor says the session's skills fit the listing budget" grep -qE '^ok   skill listing: fits: [0-9]+ of [0-9]+ chars, [0-9]+ skills$' "$sandbox/out"
mkdir -p "$HOME/.claude/skills/wordy"
printf -- '---\nname: wordy\ndescription: %s\n---\nbody\n' "$(printf 'w%.0s' $(seq 1 1600))" > "$HOME/.claude/skills/wordy/SKILL.md"
for i in $(seq 12); do cp -R "$HOME/.claude/skills/wordy" "$HOME/.claude/skills/wordy$i" && sed -i.bak "s/^name: wordy$/name: wordy$i/" "$HOME/.claude/skills/wordy$i/SKILL.md"; done
run_doctor "${real_watcher[@]}"
check_eq "doctor with too many skills for the listing exit status" 0 "$?"
check_that "doctor warns when the session's skills overflow the listing budget" \
  grep -qE '^warn skill listing: over: [0-9]+ of [0-9]+ chars, [0-9]+ skills; some reach the model as a bare name \(remove skills from ~/.claude/skills\)$' "$sandbox/out"
rm -rf "$HOME/.claude/skills"
for i in $(seq 60); do
  printf 'time=2026-11-02T15:00:%02d.000Z level=INFO source=sched.go:1 msg="runner did a new thing" model=qwen3.8-27b-cc\n' "$((i % 60))"
done > "$server_log"
run_doctor "${real_watcher[@]}"
check_eq "doctor with a server log no rule matches exit status" 1 "$?"
check_that "doctor fails when the classifier is blind to the server log" grep -qxF "fail incident classifier is blind to the server log format (update ollama/incidents/watcher.py rules)" "$sandbox/out"
check_that "doctor skips the guard lint without a telemetry log" grep -qxF "ok   guards: not checked (no telemetry log)" "$sandbox/out"
mkdir -p "$HOME/.claude-ollama/telemetry"
{
  for _ in $(seq 30); do echo '{"time":1,"session":"c","kind":"deny","hook":"read-range-guard","tool":"Read","reason":"a.py has 900 lines"}'; done
  for _ in $(seq 7); do echo '{"time":1,"session":"c","kind":"friction","hook":"read-range-guard","tool":"Read","reason":"plan reset after 4 near-identical Read denials","fingerprint":"aa"}'; done
} > "$HOME/.claude-ollama/telemetry/tool-calls.jsonl"
run_doctor
check_that "doctor skips the guard lint while telemetry is off" grep -qxF "ok   guards: not checked (no telemetry log)" "$sandbox/out"
CLAUDE_OLLAMA_TELEMETRY=1 run_doctor
check_that "doctor warns about a guard the telemetry flags" grep -qxF "warn guards: read-range-guard: message unclear or rule too strict: a.py has 900 lines" "$sandbox/out"
head -n 3 "$HOME/.claude-ollama/telemetry/tool-calls.jsonl" > "$sandbox/few.jsonl"
mv "$sandbox/few.jsonl" "$HOME/.claude-ollama/telemetry/tool-calls.jsonl"
CLAUDE_OLLAMA_TELEMETRY=1 run_doctor
check_that "doctor reports no flagged guard" grep -qxF "ok   guards: none flagged" "$sandbox/out"
check_that "doctor reports nothing to drop without a proxy log" grep -qxF "ok   tool budget: nothing to drop" "$sandbox/out"
mkdir -p "$HOME/.local/share/claude-custom/console/proxy"
budget_ts="$("$real_python3" -c 'from datetime import datetime, timezone; print(datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z"))')"
for _ in $(seq 20); do
  printf '{"ts":"%s","request_id":"r","sections":2,"stable_sections":2,"diverged_at":null,"offset":null,"diff":null,"prompt_bytes":10,"ledger":{"system":1,"tools":{"Bash":1500,"WebFetch":2048},"messages":1}}\n' "$budget_ts"
done > "$HOME/.local/share/claude-custom/console/proxy/requests.jsonl"
run_doctor
check_that "doctor warns about a tool schema nothing calls" grep -qxF "warn tool budget: drop WebFetch (saves 2.0 KiB per request): claude-ollama tool-budget" "$sandbox/out"

new_sandbox
rm -f "$CLAUDE_OLLAMA_WEIGHTS_DIR/Qwen3.8-27B-UD-Q4_K_XL.gguf" "$CLAUDE_OLLAMA_WEIGHTS_DIR/Qwen3-Embedding-0.6B-Q8_0.gguf"
run_doctor
check_eq "doctor with missing weights exit status" 1 "$?"
check_that "doctor fails missing weights" grep -qxF "fail weights Qwen3.8-27B-UD-Q4_K_XL.gguf missing (claude-ollama prepare 27b)" "$sandbox/out"
check_that "doctor warns about missing embedding weights" grep -qxF "warn embedding weights Qwen3-Embedding-0.6B-Q8_0.gguf missing (claude-ollama prepare-embedding)" "$sandbox/out"

new_sandbox
stub_state_set 'del(.models["qwen3.8-27b-cc"])'
run_doctor
check_eq "doctor with the preset missing from the router exit status" 1 "$?"
check_that "doctor fails a preset the router lacks" grep -qxF "fail preset qwen3.8-27b-cc not in llama-server's /models (claude-custom agent -apply)" "$sandbox/out"

new_sandbox
stub_state_set '.build = 9100'
run_doctor
check_eq "doctor with an old llama-server exits 0" 0 "$?"
check_that "doctor warns about a build below 9200" grep -qxF "warn llama-server build 9100 on ${stub_url#http://} is below 9200 (brew upgrade llama.cpp)" "$sandbox/out"

new_sandbox
rm -f "$HOME/.claude-ollama/presets/models.ini"
run_doctor
check_eq "doctor with stale user presets exits 0" 0 "$?"
check_that "doctor warns about stale user presets" grep -qxF "warn user presets stale: run claude-custom agent -apply" "$sandbox/out"

new_sandbox
copy_repo "$sandbox/repo"
sed 's/^ctx-size = 65536$/ctx-size = 32768/' "$sandbox/repo/ollama/models.ini" > "$sandbox/models.ini"
mv "$sandbox/models.ini" "$sandbox/repo/ollama/models.ini"
doctor="$sandbox/repo/bin/claude-ollama-doctor" run_doctor
check_eq "doctor with mismatched context sizes exit status" 1 "$?"
check_that "doctor fails mismatched context sizes" grep -qxF "fail num_ctx 32768 is below CLAUDE_CODE_MAX_CONTEXT_TOKENS 65536 (run bin/ollama-profiles)" "$sandbox/out"

new_sandbox
copy_repo "$sandbox/repo"
rm "$sandbox/repo/shared/hooks/edit-check.py"
doctor="$sandbox/repo/bin/claude-ollama-doctor" run_doctor
check_eq "doctor with a missing hook exit status" 1 "$?"
check_that "doctor fails a missing hook" grep -qxF "fail hook edit-check.py missing or not executable in shared/hooks" "$sandbox/out"

new_sandbox
echo '{"availableModels":["qwen3.8-27b-cc","opus"]}' > "$CLAUDE_OLLAMA_MANAGED_SETTINGS"
run_doctor
check_eq "doctor with the model in the managed allowlist exit status" 0 "$?"
check_that "doctor reports the managed allowlist allows the model" grep -qxF "ok   managed availableModels allows qwen3.8-27b-cc" "$sandbox/out"
echo '{"availableModels":["opus"]}' > "$CLAUDE_OLLAMA_MANAGED_SETTINGS"
run_doctor
check_eq "doctor with the model missing from the managed allowlist exits 0" 0 "$?"
check_that "doctor warns the managed allowlist lacks the model" grep -qxF "warn managed availableModels lacks qwen3.8-27b-cc (ask your admin to add it; Claude Code substitutes a [1m] variant)" "$sandbox/out"

new_sandbox
stub_state_set '.health_status = 503'
run_doctor
check_eq "doctor with no server exit status" 1 "$?"
check_that "doctor fails when the server is not answering" grep -qxF "fail llama-server not answering at $stub_url (claude-custom agent -apply, then claude-ollama logs)" "$sandbox/out"
check_not "doctor checks no preset without a server" grep -q "preset qwen3.8-27b-cc" "$sandbox/out"

new_sandbox
nojq="$sandbox/nojq"
mkdir -p "$nojq"
for tool in /usr/bin/* /bin/*; do
  [ "${tool##*/}" = jq ] || ln -sf "$tool" "$nojq/"
done
PATH="$sandbox/stubbin:$nojq" run_capture "$repo/bin/claude-ollama-doctor" 27b
check_eq "doctor without jq exit status" 1 "$?"
check_that "doctor without jq says jq is required" grep -qxF "claude-ollama: jq is required (brew install jq)" "$sandbox/err"

run_capture "$repo/bin/claude-ollama-doctor" 9b
check_eq "doctor with an unknown size exit status" 2 "$?"
check_that "doctor names the sizes it knows" grep -qF "claude-ollama-doctor: unknown size '9b' (sizes: " "$sandbox/err"
run_capture "$repo/bin/claude-ollama-doctor"
check_eq "doctor without a size exit status" 2 "$?"

new_sandbox
export XDG_CONFIG_HOME="$sandbox/xdg"
mkdir -p "$XDG_CONFIG_HOME/claude-custom/profiles"
printf '%s' '{"context":32768}' > "$XDG_CONFIG_HOME/claude-custom/profiles/ollama-27b.json"
run_doctor
check_eq "doctor with a context override exits 0" 0 "$?"
check_that "doctor agrees with the override context" grep -qxF "ok   num_ctx 32768 matches CLAUDE_CODE_MAX_CONTEXT_TOKENS 32768; Claude Code compacts at 11576 tokens" "$sandbox/out"
check_that "doctor names the profile and its overrides" grep -q "^ok   profile $XDG_CONFIG_HOME/claude-custom/profiles/ollama-27b.json: " "$sandbox/out"
fetch_list="$XDG_CONFIG_HOME/claude-custom/fetch-domains"
printf 'docs.python.org\n' > "$fetch_list"
run_doctor
check_that "doctor says web fetch is on for the listed domains" grep -qxF "ok   web fetch on for: docs.python.org" "$sandbox/out"
settings_dir="$HOME/.claude-ollama/launch-settings"
mkdir -p "$settings_dir"
sleep 30 &
live_pid=$!
printf '{"live":true}' > "$settings_dir/$live_pid.json"
cp "$settings_dir/$live_pid.json" "$sandbox/live-before.json"
run_doctor
check_eq "doctor leaves a live launch's settings alone" "$(cat "$sandbox/live-before.json")" "$(cat "$settings_dir/$live_pid.json")"
kill "$live_pid" 2>/dev/null
wait "$live_pid" 2>/dev/null
rm -f "$fetch_list"
run_doctor
check_that "doctor says web fetch is off without a fetch list" grep -qxF "ok   web fetch off (no domains in $fetch_list)" "$sandbox/out"

new_sandbox
lease_dir="$HOME/.claude-ollama/lease"
holder_pid="$(sleep 60 >/dev/null 2>&1 & echo $!)"
mkdir -p "$lease_dir"
printf '{"name":"session","model":"qwen3.6-35b-cc","num_ctx":null,"rung":null,"started":"2026-01-01T00:00:00Z"}\n' > "$lease_dir/$holder_pid.json"
run_doctor
check_that "doctor reports the live lease holder" grep -qxF "ok   lease held by session (pid $holder_pid, model qwen3.6-35b-cc)" "$sandbox/out"
kill "$holder_pid" 2>/dev/null
wait "$holder_pid" 2>/dev/null
run_doctor
check_that "doctor reports a stale lease whose pid is dead" grep -qxF "warn stale lease session (pid $holder_pid) removed" "$sandbox/out"
run_doctor
check_that "doctor reports no lease holders" grep -qxF "ok   no lease holders" "$sandbox/out"
run_doctor env CLAUDE_OLLAMA_LEASE=0
check_not "CLAUDE_OLLAMA_LEASE=0 skips the lease check" grep -q "lease holders" "$sandbox/out"

new_sandbox
dd if=/dev/zero of="$CLAUDE_OLLAMA_WEIGHTS_DIR/Qwen3.8-27B-UD-Q4_K_XL.gguf" bs=1 count=0 seek=17179869184 2>/dev/null
dd if=/dev/zero of="$CLAUDE_OLLAMA_WEIGHTS_DIR/Qwen3-Embedding-0.6B-Q8_0.gguf" bs=1 count=0 seek=644245094 2>/dev/null
write_stub sysctl <<'EOF'
#!/bin/sh
case "$*" in
  *iogpu.wired_limit_mb*) echo "${STUB_WIRED_LIMIT_MB:-0}" ;;
  *) echo "${STUB_MEMSIZE:-34359738368}" ;;
esac
EOF
write_stub vm_stat <<'EOF'
#!/bin/sh
printf 'Mach Virtual Memory Statistics: (page size of 16384 bytes)\nPages active:  100000.\nPages wired down: 100000.\n'
EOF
printf '%s\n' '{"architecture":"qwen3","metadata":{"qwen3.block_count":64,"qwen3.attention.head_count_kv":8,"qwen3.attention.key_length":128,"qwen3.attention.value_length":128}}' > "$sandbox/inspect-json"
run_doctor
check_that "doctor reports a fitting memory as ok" grep -qxF "ok   memory fit: model 16.0 GiB + kv 8.0 GiB + embedding 0.6 GiB = 24.6 GiB of 28.9 GiB free" "$sandbox/out"
check_that "doctor reads a zero wired limit as the default share of RAM" grep -qxF "ok   GPU wired limit 24.0 GiB (the default, 75% of RAM) covers model + kv 24.0 GiB" "$sandbox/out"
run_doctor env STUB_WIRED_LIMIT_MB=20480
check_eq "doctor with a low wired limit exits 0" 0 "$?"
check_that "doctor warns when model and kv exceed the wired limit and prints the command" grep -qxF "warn GPU wired limit 20.0 GiB is below model + kv 24.0 GiB; raise it with: sudo sysctl iogpu.wired_limit_mb=26624" "$sandbox/out"
run_doctor env STUB_MEMSIZE=29276800000
check_that "doctor warns when the models do not fit" grep -qxF "warn memory fit: model 16.0 GiB + kv 8.0 GiB + embedding 0.6 GiB = 24.6 GiB of 24.2 GiB free (0.4 GiB short)" "$sandbox/out"
run_doctor env CLAUDE_OLLAMA_FIT=0
check_not "doctor skips the fit with CLAUDE_OLLAMA_FIT=0" grep -q "memory fit" "$sandbox/out"
rm -f "$sandbox/stubbin/sysctl"
run_doctor
check_that "doctor warns when the fit cannot be computed" grep -qxF "warn memory fit: ollama lease: cannot read the free memory" "$sandbox/out"

new_sandbox
launch_beacon="$HOME/.local/share/claude-custom/console/beacon/$(hostname -s).json"
run_doctor
check_that "doctor warns when no beacon exists" grep -qxF "warn beacon: none yet (written at the next launch)" "$sandbox/out"
mkdir -p "$(dirname "$launch_beacon")"
jq -n --arg commit "$(git -C "$repo" rev-parse HEAD)" --arg ts "$(jq -rn 'now - 7200 | todate')" '{commit: $commit, ts: $ts}' > "$launch_beacon"
run_doctor
check_that "doctor reports a beacon at HEAD with its age" grep -qxF "ok   beacon: 2h ago, commit matches" "$sandbox/out"
jq -n --arg ts "$(jq -rn 'now - 60 | todate')" '{commit: "abc1234def5678", ts: $ts}' > "$launch_beacon"
run_doctor
check_that "doctor reports a beacon behind HEAD" \
  grep -qxF "warn beacon: stale, commit abc1234 vs HEAD $(git -C "$repo" rev-parse --short=7 HEAD): run claude-custom update" "$sandbox/out"

new_sandbox
run_doctor env CLAUDE_OLLAMA_CMUX=0
check_that "doctor reports the browser tools off by switch" grep -qxF "ok   browser tools off (CLAUDE_OLLAMA_CMUX=0)" "$sandbox/out"
check_that "doctor warns when gh is not logged in" grep -qF "warn gh is not logged in to github.com" "$sandbox/out"

new_sandbox
nvm_versions="$HOME/.nvm/versions/node"
for nvm_version in v20.11.0 v22.9.0; do
  mkdir -p "$nvm_versions/$nvm_version/bin"
  printf '#!/bin/sh\necho %s\n' "$nvm_version" > "$nvm_versions/$nvm_version/bin/node"
  chmod +x "$nvm_versions/$nvm_version/bin/node"
done
mkdir -p "$sandbox/nvm-project"
echo "20" > "$sandbox/nvm-project/.nvmrc"
(cd "$sandbox/nvm-project" && run_doctor)
check_that "doctor reports the nvm node the session gets" grep -qxF "ok   node $nvm_versions/v20.11.0/bin/node (nvm 20 from $sandbox/nvm-project/.nvmrc)" "$sandbox/out"
rm -rf "$HOME/.nvm"
run_doctor
check_that "doctor reports the PATH node without nvm" grep -qx "ok   node .*/node (no nvm)\|warn node: none on PATH" "$sandbox/out"

if [ "$failures" -eq 0 ]; then
  echo "all passed"
else
  echo "$failures failed"
  exit 1
fi
