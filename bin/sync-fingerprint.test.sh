#!/usr/bin/env bash
set -u
repo="$(cd "$(dirname "$0")/.." && pwd -P)"
failures=0
sandboxes=""

remove_sandboxes() {
  local dir
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
  [ "$2" = "$3" ] || fail "$1: expected [$2] got [$3]"
}

check_ne() {
  [ "$2" != "$3" ] || fail "$1: both are [$2]"
}

check_that() {
  local name="$1"
  shift
  "$@" || fail "$name"
}

sha256_stdin() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | cut -d' ' -f1
  else
    sha256sum | cut -d' ' -f1
  fi
}

base_27b="$(sed -n 's/^FROM //p' "$repo/ollama/Modelfile.27b")"
pin_27b="$(jq -r --arg name "$base_27b" '.[$name]' "$repo/ollama/model-digests.json")"

write_tags() {
  jq -n --arg base "$base_27b" --arg digest "$1" \
    '{models: [{name: $base, digest: $digest}, {name: "qwen3.8-27b-cc:latest", digest: "sha256:cc27"}]}' > "$sandbox/tags.json"
}

new_sandbox() {
  sandbox="$(made="$(mktemp -d "${TMPDIR:-/tmp}/sync-fingerprint-test.XXXXXX")" && cd "$made" && pwd -P)" || exit 1
  sandboxes="$sandboxes $sandbox"
  export HOME="$sandbox/home"
  mkdir -p "$HOME" "$sandbox/stubbin" "$sandbox/repo/bin" "$sandbox/repo/ollama" "$sandbox/repo/shared/hooks"
  cp "$repo/bin/sync-fingerprint" "$sandbox/repo/bin/"
  cp "$repo"/ollama/settings.*.json "$repo"/ollama/Modelfile.* "$repo/ollama/model-digests.json" "$sandbox/repo/ollama/"
  cp "$repo"/shared/hooks/*.py "$repo"/shared/hooks/*.sh "$sandbox/repo/shared/hooks/"
  git -C "$sandbox/repo" init -q
  git -C "$sandbox/repo" add -A
  git -C "$sandbox/repo" -c user.name=t -c user.email=t@t commit -qm initial
  unset STUB_CURL_EXIT STUB_OLLAMA_PID STUB_OLLAMA_ENV
  write_tags "$pin_27b"
  cat > "$sandbox/stubbin/curl" <<EOF
#!/bin/sh
[ "\${STUB_CURL_EXIT:-0}" = 0 ] || exit "\$STUB_CURL_EXIT"
case "\$*" in *api/tags*) cat "$sandbox/tags.json" ;; esac
EOF
  cat > "$sandbox/stubbin/pgrep" <<'EOF'
#!/bin/sh
[ -n "${STUB_OLLAMA_PID:-}" ] || exit 1
echo "$STUB_OLLAMA_PID"
EOF
  cat > "$sandbox/stubbin/ps" <<'EOF'
#!/bin/sh
echo "ollama serve ${STUB_OLLAMA_ENV:-}"
EOF
  cat > "$sandbox/stubbin/claude" <<'EOF'
#!/bin/sh
echo "2.1.260 (Claude Code)"
echo "second line"
EOF
  chmod +x "$sandbox/stubbin"/*
  export PATH="$sandbox/stubbin:$PATH"
  fingerprint="$sandbox/repo/bin/sync-fingerprint"
}

run_capture() {
  "$@" >"$sandbox/out" 2>"$sandbox/err"
}

field() {
  jq -r "$1" "$sandbox/out"
}

new_sandbox
STUB_OLLAMA_PID=42 STUB_OLLAMA_ENV="OLLAMA_FLASH_ATTENTION=1 OLLAMA_KV_CACHE_TYPE=q8_0 OLLAMA_MAX_LOADED_MODELS=2" run_capture "$fingerprint"
check_eq "sync-fingerprint exit status" 0 "$?"
check_eq "commit is the repo HEAD" "$(git -C "$sandbox/repo" rev-parse HEAD)" "$(field .commit)"
check_eq "a clean tree is not dirty" false "$(field .dirty)"
check_eq "the 27b model is named" qwen3.8-27b-cc "$(field '.models["27b"].name')"
check_eq "the 27b model digest comes from /api/tags" sha256:cc27 "$(field '.models["27b"].digest')"
check_eq "the 27b base matches its pin" ok "$(field '.models["27b"].pin')"
check_eq "the 35b model is missing when /api/tags lacks it" missing "$(field '.models["35b"].digest')"
check_eq "server env holds the running OLLAMA_* values" q8_0 "$(field '.server_env.OLLAMA_KV_CACHE_TYPE')"
check_eq "server env holds every OLLAMA_* value" 3 "$(field '.server_env | length')"
check_eq "hooks are hashed by basename" "$(sha256_stdin < "$repo/shared/hooks/tdd-guard.py")" "$(field '.hooks["tdd-guard.py"]')"
check_eq "hook tests are left out" null "$(field '.hooks["tdd-guard.test.sh"]')"
check_eq "sandbox is the hash of the rendered 27b sandbox block" "$(jq -cS .sandbox "$repo/ollama/settings.27b.json" | sha256_stdin)" "$(field .sandbox)"
check_eq "claude_version is the first line of claude --version" "2.1.260 (Claude Code)" "$(field .claude_version)"
check_eq "host is the short hostname" "$(hostname -s)" "$(field .host)"
check_that "ts is a utc iso timestamp" grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' <<< "$(field .ts)"
check_eq "fingerprint is the sha256 of the canonical JSON without host, ts and itself" \
  "$(jq -cS 'del(.host, .ts, .fingerprint)' "$sandbox/out" | sha256_stdin)" "$(field .fingerprint)"
first_fingerprint="$(field .fingerprint)"
sleep 1
STUB_OLLAMA_PID=42 STUB_OLLAMA_ENV="OLLAMA_FLASH_ATTENTION=1 OLLAMA_KV_CACHE_TYPE=q8_0 OLLAMA_MAX_LOADED_MODELS=2" run_capture "$fingerprint"
check_eq "the fingerprint is the same across two runs" "$first_fingerprint" "$(field .fingerprint)"

printf '\nprint("changed")\n' >> "$sandbox/repo/shared/hooks/tdd-guard.py"
STUB_OLLAMA_PID=42 STUB_OLLAMA_ENV="OLLAMA_FLASH_ATTENTION=1 OLLAMA_KV_CACHE_TYPE=q8_0 OLLAMA_MAX_LOADED_MODELS=2" run_capture "$fingerprint"
check_ne "a changed hook changes the fingerprint" "$first_fingerprint" "$(field .fingerprint)"
check_eq "a changed tracked file flips dirty" true "$(field .dirty)"
git -C "$sandbox/repo" checkout -q -- shared/hooks/tdd-guard.py
: > "$sandbox/repo/untracked.txt"
STUB_OLLAMA_PID=42 STUB_OLLAMA_ENV="OLLAMA_FLASH_ATTENTION=1 OLLAMA_KV_CACHE_TYPE=q8_0 OLLAMA_MAX_LOADED_MODELS=2" run_capture "$fingerprint"
check_eq "an untracked file does not flip dirty" false "$(field .dirty)"
check_eq "and the fingerprint is back" "$first_fingerprint" "$(field .fingerprint)"

STUB_CURL_EXIT=7 run_capture "$fingerprint"
check_eq "with ollama down the model digest is missing" missing "$(field '.models["27b"].digest')"
check_eq "with ollama down the pin is missing" missing "$(field '.models["27b"].pin')"
check_eq "with ollama down the server env is empty" '{}' "$(jq -c .server_env "$sandbox/out")"
check_ne "ollama down changes the fingerprint" "$first_fingerprint" "$(field .fingerprint)"

write_tags sha256:other
run_capture "$fingerprint"
check_eq "a base digest off its pin is a mismatch" mismatch "$(field '.models["27b"].pin')"

printf '#!/bin/sh\nexit 127\n' > "$sandbox/stubbin/claude"
run_capture "$fingerprint"
check_eq "claude_version is null when claude does not answer" null "$(field .claude_version)"

beacon="$HOME/.local/share/claude-custom/console/beacon/$(hostname -s).json"
run_capture "$fingerprint" --out "$beacon"
check_eq "--out exit status" 0 "$?"
check_that "--out prints nothing" test ! -s "$sandbox/out"
check_eq "--out writes the fingerprint" "$(hostname -s)" "$(jq -r .host "$beacon")"
check_eq "--out writes a 0600 file" 600 "$(stat -c %a "$beacon" 2>/dev/null || stat -f %Lp "$beacon")"
check_eq "--out makes a 0700 folder" 700 "$(stat -c %a "$(dirname "$beacon")" 2>/dev/null || stat -f %Lp "$(dirname "$beacon")")"

run_capture "$fingerprint" --summary "$beacon"
check_eq "--summary exit status" 0 "$?"
check_that "--summary prints the short commit" grep -qxF "commit: $(git -C "$sandbox/repo" rev-parse --short=7 HEAD)" "$sandbox/out"
check_that "--summary prints dirty" grep -qxF "dirty: false" "$sandbox/out"
check_that "--summary prints claude_version" grep -qxF "claude_version: none" "$sandbox/out"
check_that "--summary prints a short models hash" grep -qE '^models: [0-9a-f]{12}$' "$sandbox/out"
check_that "--summary prints a short server_env hash" grep -qE '^server_env: [0-9a-f]{12}$' "$sandbox/out"
check_that "--summary prints a short hooks hash" grep -qE '^hooks: [0-9a-f]{12}$' "$sandbox/out"
check_that "--summary prints a short sandbox hash" grep -qxF "sandbox: $(jq -r '.sandbox[:12]' "$beacon")" "$sandbox/out"
check_that "--summary prints the short fingerprint" grep -qxF "fingerprint: $(jq -r '.fingerprint[:12]' "$beacon")" "$sandbox/out"

jq --arg ts "$(jq -rn 'now - 7320 | todate')" '.ts = $ts' "$beacon" > "$sandbox/old.json"
run_capture "$fingerprint" --age "$sandbox/old.json"
check_eq "--age prints hours for an old beacon" 2h "$(cat "$sandbox/out")"
jq --arg ts "$(jq -rn 'now - 90 | todate')" '.ts = $ts' "$beacon" > "$sandbox/old.json"
run_capture "$fingerprint" --age "$sandbox/old.json"
check_eq "--age prints minutes for a recent beacon" 1m "$(cat "$sandbox/out")"
jq --arg ts "$(jq -rn 'now - 300000 | todate')" '.ts = $ts' "$beacon" > "$sandbox/old.json"
run_capture "$fingerprint" --age "$sandbox/old.json"
check_eq "--age prints days for a week-old beacon" 3d "$(cat "$sandbox/out")"

run_capture "$fingerprint" --bogus
check_eq "an unknown flag exits 2" 2 "$?"

if [ "$failures" -eq 0 ]; then
  echo "all passed"
else
  echo "$failures failed"
  exit 1
fi
