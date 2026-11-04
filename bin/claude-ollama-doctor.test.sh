#!/usr/bin/env bash
set -u
repo="$(cd "$(dirname "$0")/.." && pwd -P)"
real_python3="$(command -v python3)"
failures=0
sandboxes=""
system_tools=""
healthy_server_env="OLLAMA_FLASH_ATTENTION=1 OLLAMA_KV_CACHE_TYPE=q8_0 OLLAMA_KEEP_ALIVE=30m OLLAMA_MAX_LOADED_MODELS=2 OLLAMA_NUM_PARALLEL=1"

remove_sandboxes() {
  local dir
  local PATH=/usr/bin:/bin
  for dir in $sandboxes; do
    chmod -R u+w "$dir" 2>/dev/null
    rm -rf "$dir"
  done
}

trap remove_sandboxes EXIT

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

pinned_tags() {
  jq '{models: [to_entries[] | {name: .key, digest: .value}]}' "$repo/ollama/model-digests.json"
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
  write_stub ollama <<EOF
#!/bin/sh
echo "\$*" >> "$sandbox/ollama.log"
if [ "\$1" = show ] && [ "\$3" = --verbose ]; then cat "$sandbox/show-verbose" 2>/dev/null; fi
[ "\$1" = show ] && exit "\${STUB_OLLAMA_SHOW_EXIT:-0}"
exit 0
EOF
  write_stub curl <<EOF
#!/bin/sh
case "\$*" in *api/tags*) cat "$sandbox/tags.json" ;; esac
exit "\${STUB_CURL_EXIT:-0}"
EOF
  write_stub pgrep <<'EOF'
#!/bin/sh
[ -n "${STUB_OLLAMA_PID:-}" ] && echo "$STUB_OLLAMA_PID"
EOF
  write_stub ps <<'EOF'
#!/bin/sh
echo "ollama serve ${STUB_OLLAMA_ENV:-}"
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
  unset STUB_OLLAMA_SHOW_EXIT STUB_OLLAMA_PID STUB_OLLAMA_ENV STUB_CURL_EXIT STUB_MEMSIZE CLAUDE_OLLAMA_LEASE CLAUDE_OLLAMA_FIT
  export CLAUDE_OLLAMA_MANAGED_SETTINGS="$sandbox/managed-settings.json"
  export CLAUDE_OLLAMA_MEMINFO="$sandbox/no-meminfo"
  export CLAUDE_OLLAMA_INCIDENT_WATCHER="$sandbox/stubbin/incident-watcher"
  write_stubs
  pinned_tags > "$sandbox/tags.json"
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
  STUB_OLLAMA_PID=42 STUB_OLLAMA_ENV="$healthy_server_env" run_capture "$@" "${doctor:-$repo/bin/claude-ollama-doctor}" 27b
}

new_sandbox
run_doctor
check_eq "doctor healthy exit status" 0 "$?"
check_that "doctor reports jq" grep -qxF "ok   jq on PATH" "$sandbox/out"
check_that "doctor reports the main model" grep -qxF "ok   model qwen3.8-27b-cc" "$sandbox/out"
check_not "doctor no longer checks a side model" grep -q "side model" "$sandbox/out"
check_that "doctor reports the embedding model" grep -qxF "ok   embedding model qwen3-embedding:0.6b" "$sandbox/out"
check_that "doctor reports context sizes agree" grep -qxF "ok   num_ctx 65536 matches CLAUDE_CODE_MAX_CONTEXT_TOKENS 65536; Claude Code compacts at 44344 tokens" "$sandbox/out"
check_that "doctor reports hooks" grep -qxF "ok   hook stop-verify.py present" "$sandbox/out"
check_that "doctor reports reachability" grep -qxF "ok   ollama reachable at http://127.0.0.1:11434" "$sandbox/out"
check_that "doctor reports server env" grep -qxF "ok   server env OLLAMA_KV_CACHE_TYPE=q8_0" "$sandbox/out"
check_that "doctor reports no managed model allowlist" grep -qxF "ok   no managed availableModels restricts qwen3.8-27b-cc" "$sandbox/out"
check_that "doctor reports a base that matches its pin" grep -qxF "ok   digest qwen3.8:27b-mlx matches its pin" "$sandbox/out"
check_that "doctor reports the browser tools" grep -q 'browser tools' "$sandbox/out"
check_not "doctor never mentions sandbox-runtime" grep -q 'sandbox-runtime' "$sandbox/out"
check_not "doctor does not pull or create" grep -sqE '^(pull|create) ' "$sandbox/ollama.log"
jq '.models[0].digest = "0000"' "$sandbox/tags.json" > "$sandbox/tags.new" && mv "$sandbox/tags.new" "$sandbox/tags.json"
run_doctor
check_eq "doctor with a base that misses its pin exit status" 1 "$?"
check_that "doctor fails a base that misses its pin" grep -qF "fail digest qwen3.8:27b-mlx is 0000, not the pinned" "$sandbox/out"
pinned_tags > "$sandbox/tags.json"

run_doctor env HOMEBREW_PREFIX="$sandbox/brew"
check_that "doctor skips the classifier check without a server log" grep -qxF "ok   incident classifier not checked (no server log)" "$sandbox/out"
mkdir -p "$sandbox/brew/var/log"
cp "$repo/ollama/incidents/fixtures/server-log.txt" "$sandbox/brew/var/log/ollama.log"
real_watcher=(env CLAUDE_OLLAMA_INCIDENT_WATCHER="$repo/ollama/incidents/watcher.py" HOMEBREW_PREFIX="$sandbox/brew")
run_doctor "${real_watcher[@]}"
check_eq "doctor with a server log the classifier reads exit status" 0 "$?"
check_that "doctor reports the classifier matches the server log" grep -qxF "ok   incident classifier matches the server log (rules: 6)" "$sandbox/out"
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
done > "$sandbox/brew/var/log/ollama.log"
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
STUB_OLLAMA_SHOW_EXIT=1 STUB_OLLAMA_PID=42 run_capture "$repo/bin/claude-ollama-doctor" 27b
check_eq "doctor with missing models exit status" 1 "$?"
check_that "doctor fails the main model" grep -qxF "fail model qwen3.8-27b-cc missing (run claude-ollama 27b to pull and create it)" "$sandbox/out"
check_that "doctor fails the embedding model" grep -qxF "fail embedding model qwen3-embedding:0.6b missing (pick 'Set up embedding model' in claude-ollama)" "$sandbox/out"
check_that "doctor fails server env" grep -qxF "fail server env OLLAMA_FLASH_ATTENTION=1 not set on the running server" "$sandbox/out"
check_that "doctor names the fix for missing server env" grep -qxF "     fix: claude-custom agent -apply" "$sandbox/out"

new_sandbox
copy_repo "$sandbox/repo"
sed 's/num_ctx 65536/num_ctx 32768/' "$sandbox/repo/ollama/Modelfile.27b" > "$sandbox/Modelfile.27b"
mv "$sandbox/Modelfile.27b" "$sandbox/repo/ollama/Modelfile.27b"
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
STUB_CURL_EXIT=7 run_capture "$repo/bin/claude-ollama-doctor" 27b
check_eq "doctor with no server exit status" 1 "$?"
check_that "doctor fails when the server is unreachable" grep -qxF "fail ollama not reachable at http://127.0.0.1:11434 (brew services start ollama)" "$sandbox/out"
check_that "doctor fails when no server process runs" grep -qxF "fail ollama server not running (brew services start ollama)" "$sandbox/out"

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
pinned_tags | jq '.models |= map(if .name == "qwen3-embedding:0.6b" then . + {size: 644245094} else . end) | .models += [{name: "qwen3.8-27b-cc", size: 17179869184}]' > "$sandbox/tags.json"
write_stub sysctl <<'EOF'
#!/bin/sh
echo "${STUB_MEMSIZE:-34359738368}"
EOF
write_stub vm_stat <<'EOF'
#!/bin/sh
printf 'Mach Virtual Memory Statistics: (page size of 16384 bytes)\nPages active:  100000.\nPages wired down: 100000.\n'
EOF
printf '  Model\n    architecture        qwen3\n\n  Metadata\n    qwen3.attention.head_count_kv       8\n    qwen3.attention.key_length          128\n    qwen3.block_count                   64\n' > "$sandbox/show-verbose"
run_doctor
check_that "doctor reports a fitting memory as ok" grep -qxF "ok   memory fit: model 16.0 GiB + kv 8.0 GiB + embedding 0.6 GiB = 24.6 GiB of 28.9 GiB free" "$sandbox/out"
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
