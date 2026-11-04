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

. "$repo/shared/testing/stub-llama-lib.sh"
file_27b="$(jq -r '.["27b"].gguf.file' "$repo/ollama/sizes.json")"
key_27b="$(jq -r '.["27b"].gguf | "\(.repo)/\(.file)"' "$repo/ollama/sizes.json")"
printf '{"models": {}, "build": 11429, "models_max": 2}\n' > "${TMPDIR:-/tmp}/sync-fingerprint-stub-$$.json"
start_stub_llama "${TMPDIR:-/tmp}/sync-fingerprint-stub-$$.json" || exit 1
server_url="$LLAMA_SERVER_URL"
trap 'stop_stub_llama; rm -f "${TMPDIR:-/tmp}/sync-fingerprint-stub-$$.json"; remove_sandboxes' EXIT

new_sandbox() {
  sandbox="$(made="$(mktemp -d "${TMPDIR:-/tmp}/sync-fingerprint-test.XXXXXX")" && cd "$made" && pwd -P)" || exit 1
  sandboxes="$sandboxes $sandbox"
  export HOME="$sandbox/home"
  mkdir -p "$HOME" "$sandbox/stubbin" "$sandbox/repo/bin/lib" "$sandbox/repo/ollama" "$sandbox/repo/shared/hooks" "$sandbox/weights"
  cp "$repo/bin/sync-fingerprint" "$repo/bin/ollama-models" "$sandbox/repo/bin/"
  cp "$repo"/bin/lib/*.sh "$sandbox/repo/bin/lib/"
  cp "$repo"/ollama/settings.*.json "$repo"/ollama/Modelfile.* "$repo"/ollama/sizes.json "$repo"/ollama/embedding.json "$repo"/ollama/server.ini "$sandbox/repo/ollama/"
  printf 'weights-27b' > "$sandbox/weights/$file_27b"
  jq --arg key "$key_27b" --arg sha "$(printf 'weights-27b' | sha256_stdin)" '.[$key] = $sha' "$repo/ollama/model-digests.json" > "$sandbox/repo/ollama/model-digests.json"
  cp "$repo"/shared/hooks/*.py "$repo"/shared/hooks/*.sh "$sandbox/repo/shared/hooks/"
  git -C "$sandbox/repo" init -q
  git -C "$sandbox/repo" add -A
  git -C "$sandbox/repo" -c user.name=t -c user.email=t@t commit -qm initial
  export CLAUDE_OLLAMA_WEIGHTS_DIR="$sandbox/weights" LLAMA_SERVER_URL="$server_url"
  export LLAMA_SERVER_PLIST="$sandbox/no-plist" LLAMA_SERVER_BIN="$sandbox/stubbin/llama-server"
  cat > "$sandbox/stubbin/llama-server" <<'EOF'
#!/bin/sh
echo "version: 0.6.0 (build 11000, commit abcdef123)"
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
run_capture "$fingerprint"
check_eq "sync-fingerprint exit status" 0 "$?"
check_eq "commit is the repo HEAD" "$(git -C "$sandbox/repo" rev-parse HEAD)" "$(field .commit)"
check_eq "a clean tree is not dirty" false "$(field .dirty)"
check_eq "the 27b model is named" qwen3.8-27b-cc "$(field '.models["27b"].name')"
check_eq "the 27b weights file is named" "$file_27b" "$(field '.models["27b"].file')"
check_eq "the 27b weights match their pin" ok "$(field '.models["27b"].pin')"
check_eq "the 35b weights are missing when the file is not there" missing "$(field '.models["35b"].pin')"
check_eq "pinned weights carry their pinned sha256 as the digest" "sha256:$(printf 'weights-27b' | sha256_stdin)" "$(field '.models["27b"].digest')"
check_eq "missing weights carry missing as the digest" missing "$(field '.models["35b"].digest')"
check_eq "the server section holds the running build" 11429 "$(field '.server_env.build')"
check_eq "the server settings hold the shared preset keys" q8_0 "$(field '.server_env.settings["cache-type-k"]')"
check_eq "the server settings hold models-max" 2 "$(field '.server_env.settings["models-max"]')"
check_eq "the server settings hold every [*] key plus models-max" "$(($(grep -c ' = ' "$repo/ollama/server.ini") + 1))" "$(field '.server_env.settings | length')"
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
run_capture "$fingerprint"
check_eq "the fingerprint is the same across two runs" "$first_fingerprint" "$(field .fingerprint)"

printf '\nprint("changed")\n' >> "$sandbox/repo/shared/hooks/tdd-guard.py"
run_capture "$fingerprint"
check_ne "a changed hook changes the fingerprint" "$first_fingerprint" "$(field .fingerprint)"
check_eq "a changed tracked file flips dirty" true "$(field .dirty)"
git -C "$sandbox/repo" checkout -q -- shared/hooks/tdd-guard.py
: > "$sandbox/repo/untracked.txt"
run_capture "$fingerprint"
check_eq "an untracked file does not flip dirty" false "$(field .dirty)"
check_eq "and the fingerprint is back" "$first_fingerprint" "$(field .fingerprint)"

LLAMA_SERVER_URL=http://127.0.0.1:9 run_capture "$fingerprint"
check_eq "with llama-server down the build comes from the binary" 11000 "$(field '.server_env.build')"
check_eq "with llama-server down models-max is the default" 2 "$(field '.server_env.settings["models-max"]')"
check_ne "llama-server down changes the fingerprint" "$first_fingerprint" "$(field .fingerprint)"

mkdir -p "$HOME/.claude-ollama/presets"
printf '[*]\ncache-type-k = f16\n\n[qwen3.8-27b-cc]\nctx-size = 1\n' > "$HOME/.claude-ollama/presets/models.ini"
run_capture "$fingerprint"
check_eq "the user presets file overrides a shared key" f16 "$(field '.server_env.settings["cache-type-k"]')"
check_eq "a preset section's keys stay out of the settings" null "$(field '.server_env.settings["ctx-size"]')"
rm -rf "$HOME/.claude-ollama/presets"

printf 'other-weights' > "$sandbox/weights/$file_27b"
run_capture "$fingerprint"
check_eq "weights off their pin are a mismatch" mismatch "$(field '.models["27b"].pin')"
check_eq "weights off their pin carry mismatch as the digest" mismatch "$(field '.models["27b"].digest')"

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
