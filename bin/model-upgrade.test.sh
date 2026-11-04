#!/usr/bin/env bash
set -u
repo_dir="$(cd "$(dirname "$0")/.." && pwd -P)"
check_script="$repo_dir/bin/model-upgrade"
. "$repo_dir/shared/testing/stub-llama-lib.sh"
tmp="$(mktemp -d)"
failures=0
trap 'stop_stub_llama; rm -rf "$tmp"' EXIT

pinned_revision="$(jq -r '.["27b"].gguf.revision' "$repo_dir/ollama/sizes.json")"
weights_file="$(jq -r '.["27b"].gguf.file' "$repo_dir/ollama/sizes.json")"
repo_name="$(jq -r '.["27b"].gguf.repo' "$repo_dir/ollama/sizes.json")"
new_revision=dddddddddddddddddddddddddddddddddddddddd
new_sha="$(printf 'new-weights' | shasum -a 256 | cut -c1-64)"

stubs="$tmp/stubs"
mkdir -p "$stubs"

cat > "$stubs/curl" <<EOF
#!/bin/sh
out=""
url=""
while [ \$# -gt 0 ]; do
  case "\$1" in
    -o) out="\$2"; shift ;;
    http*) url="\$1" ;;
  esac
  shift
done
echo "curl \$url" >> "\$CURL_CALLS"
[ -n "\${STUB_HF_DOWN:-}" ] && exit 22
revision="${new_revision}"
[ -n "\${STUB_HF_CURRENT:-}" ] && revision="${pinned_revision}"
case "\$url" in
  */api/models/${repo_name}/revision/main) printf '{"sha":"%s"}' "\$revision" ;;
  */api/models/${repo_name}/tree/*) printf '[{"path":"${weights_file}","lfs":{"oid":"${new_sha}"}}]' ;;
  */${repo_name}/resolve/*/${weights_file})
    [ -n "\${STUB_DOWNLOAD_FAIL:-}" ] && exit 22
    if [ -n "\${STUB_BAD_DOWNLOAD:-}" ]; then printf 'tampered' > "\$out"; else printf 'new-weights' > "\$out"; fi ;;
  *) exit 22 ;;
esac
EOF

cat > "$stubs/ollama-profiles" <<'EOF'
#!/bin/sh
echo "ollama-profiles $1${2:+ $2}" >> "$CALLS"
presets="$HOME/.claude-ollama/presets/models.ini"
[ "${2:-}" = --out ] && presets="$3"
mkdir -p "$(dirname "$presets")"
printf '[*]\njinja = true\n\n[qwen3.8-27b-cc]\nmodel = /weights/Qwen3.8-27B-UD-Q4_K_XL.gguf\nctx-size = 65536\nreasoning = off\n\n[qwen3.8-27b-cc@think]\nmodel = /weights/Qwen3.8-27B-UD-Q4_K_XL.gguf\nreasoning = on\n' > "$presets"
echo changed
EOF

cat > "$stubs/ollama-agent" <<'EOF'
#!/bin/sh
echo "ollama-agent $*" >> "$CALLS"
EOF

cat > "$stubs/ollama-models" <<'EOF'
#!/bin/sh
echo "ollama-models $*" >> "$CALLS"
[ -z "${STUB_PIN_FAIL:-}" ]
EOF

cat > "$stubs/speed-check" <<'EOF'
#!/bin/sh
echo "speed-check $*" >> "$CALLS"
cp "$HOME/.claude-ollama/presets/models.ini" "$RUN_DIR/presets-during.ini"
if [ -n "${STUB_NO_THINKING:-}" ]; then
  echo "Thinking off: FAIL (qwen3.8-27b-cc@next think 500 -> 40)"
  exit 1
fi
echo "Thinking off: PASS (qwen3.8-27b-cc@next think 500 -> 0)"
EOF

cat > "$stubs/ollama-cache-probe" <<'EOF'
#!/bin/sh
echo "ollama-cache-probe $*" >> "$CALLS"
[ -z "${STUB_PROBE_FAIL:-}" ] || exit 3
echo "{\"cache_reused\": ${STUB_CACHE_REUSED:-true}}"
EOF

cat > "$stubs/pr-review-eval" <<'EOF'
#!/bin/sh
echo "pr-review-eval $*" >> "$CALLS"
echo "{\"scenarios\": {}, \"total\": {\"caught\": 4, \"bugs\": 4, \"false_blockers\": 0, \"verdicts_ok\": 6, \"unparsable\": ${STUB_UNPARSABLE:-0}}}"
EOF

cat > "$stubs/task-eval" <<'EOF'
#!/bin/sh
echo "task-eval $*" >> "$CALLS"
echo "{\"model\": \"qwen3.8-27b-cc@next\", \"size\": \"27b\", \"runs\": [], \"total\": {\"green\": ${STUB_TASK_GREEN:-5}, \"runs\": 5, \"median_seconds\": ${STUB_TASK_MEDIAN:-40.0}, \"p90_seconds\": 60.0}}"
EOF

chmod +x "$stubs"/*

printf '{"models": {"qwen3.8-27b-cc": {}}}\n' > "$tmp/stub-state.json"
start_stub_llama "$tmp/stub-state.json" || exit 1
server_url="$LLAMA_SERVER_URL"

fail() {
  echo "FAIL: $1"
  failures=$((failures + 1))
}

has() {
  grep -qF -- "$1" "$run_dir/$2"
}

upgrade_args=(27b)

baseline_dir=""

run_upgrade() {
  run_dir="$(mktemp -d "$tmp/run.XXXXXX")"
  export RUN_DIR="$run_dir"
  export CALLS="$run_dir/calls.log"
  export CURL_CALLS="$run_dir/curl.log"
  : > "$CALLS"
  mkdir -p "$run_dir/home" "$run_dir/weights"
  printf 'old-weights' > "$run_dir/weights/$weights_file"
  [ -z "$baseline_dir" ] || cp -R "$baseline_dir" "$run_dir/home/bench-results"
  env PATH="$stubs:$PATH" HOME="$run_dir/home" HF_ENDPOINT="https://hf.test" \
    LLAMA_SERVER_URL="$server_url" CLAUDE_OLLAMA_WEIGHTS_DIR="$run_dir/weights" \
    MODEL_UPGRADE_MODELS="$stubs/ollama-models" MODEL_UPGRADE_SPEED_CHECK="$stubs/speed-check" \
    MODEL_UPGRADE_PROBE="$stubs/ollama-cache-probe" MODEL_UPGRADE_EVAL="$stubs/pr-review-eval" \
    MODEL_UPGRADE_TASK_EVAL="$stubs/task-eval" MODEL_UPGRADE_PROFILES="$stubs/ollama-profiles" \
    MODEL_UPGRADE_AGENT="$stubs/ollama-agent" \
    "$@" "$check_script" ${upgrade_args[@]+"${upgrade_args[@]}"} > "$run_dir/out" 2> "$run_dir/err"
  status=$?
}

weights_are() {
  [ "$(cat "$run_dir/weights/$weights_file" 2>/dev/null)" = "$1" ]
}

pass_calls="$(printf '%s\n' \
  "ollama-profiles --user-presets --out" \
  "ollama-agent -apply" \
  "speed-check --thinking-only --model qwen3.8-27b-cc@next" \
  "ollama-cache-probe qwen3.8-27b-cc@next --json" \
  "ollama-models pin 27b --revision $new_revision" \
  "ollama-profiles --user-presets" \
  "ollama-agent -apply")"

fail_calls="$(printf '%s\n' \
  "ollama-profiles --user-presets --out" \
  "ollama-agent -apply" \
  "speed-check --thinking-only --model qwen3.8-27b-cc@next" \
  "ollama-cache-probe qwen3.8-27b-cc@next --json" \
  "ollama-profiles --user-presets" \
  "ollama-agent -apply")"

upgrade_args=(nosuch)
run_upgrade
[ "$status" -eq 2 ] || fail "an unknown size exits 2 (got $status)"
has "unknown size nosuch" err || fail "an unknown size names the problem"

upgrade_args=(27b)
run_upgrade LLAMA_SERVER_URL=http://127.0.0.1:9
[ "$status" -eq 2 ] || fail "a stopped llama-server exits 2 (got $status)"
has "llama-server is not answering at http://127.0.0.1:9" err || fail "a stopped llama-server says to start it"
[ -s "$CALLS" ] && fail "a stopped llama-server runs nothing"

run_upgrade STUB_HF_DOWN=1
[ "$status" -eq 2 ] || fail "an unanswered Hugging Face API exits 2 (got $status)"
has "has no main revision at https://hf.test" err || fail "an unanswered API says to check the network"
[ -s "$CALLS" ] && fail "an unanswered API runs nothing"

run_upgrade STUB_HF_CURRENT=1
[ "$status" -eq 0 ] || fail "a current size exits 0 (got $status)"
has "27b is current at ${pinned_revision:0:12}; nothing to upgrade" out || fail "a current size says there is nothing to upgrade"
grep -q '/resolve/' "$CURL_CALLS" && fail "a current size downloads nothing"

upgrade_args=(27b --force)
run_upgrade STUB_HF_CURRENT=1
[ "$status" -eq 0 ] || fail "--force upgrades a current size (got $status)"
grep -qxF "curl https://hf.test/$repo_name/resolve/$pinned_revision/$weights_file" "$CURL_CALLS" || fail "--force downloads the pinned revision"
upgrade_args=(27b)

run_upgrade
[ "$status" -eq 0 ] || fail "a behind size that passes exits 0 (got $status)"
[ "$(cat "$CALLS")" = "$pass_calls" ] || fail "a pass stages the preset, checks, pins and restores in order"
grep -qxF "curl https://hf.test/$repo_name/resolve/$new_revision/$weights_file" "$CURL_CALLS" || fail "the candidate is the repo's newest revision"
grep -qxF '[qwen3.8-27b-cc@next]' "$run_dir/presets-during.ini" || fail "the checks run against an @next preset"
grep -qxF "model = $run_dir/weights/$weights_file.next" "$run_dir/presets-during.ini" || fail "the @next preset loads the downloaded file"
grep -qxF 'ctx-size = 65536' "$run_dir/presets-during.ini" || fail "the @next preset keeps the size's settings"
[ "$(stat -f %Lp "$run_dir/home/.claude-ollama/presets/models.ini" 2>/dev/null || stat -c %a "$run_dir/home/.claude-ollama/presets/models.ini")" = 600 ] || fail "the staged preset file is private"
grep -qF '@next' "$run_dir/home/.claude-ollama/presets/models.ini" && fail "the @next preset is gone afterwards"
weights_are new-weights || fail "a pass moves the candidate over the current file"
[ -e "$run_dir/weights/$weights_file.next" ] && fail "a pass leaves no candidate behind"
has "thinking: PASS" out || fail "a pass prints the thinking verdict"
has "cache: reused" out || fail "a pass prints the cache verdict"
has "eval: skipped" out || fail "without --eval the verdict says the eval was skipped"
has "Next: git add ollama/sizes.json ollama/model-digests.json && git commit -m 'chore: pin 27b at dddddddddddd'" out || fail "a pass prints the git commands"
grep -q "\"revision\": \"$new_revision\"" "$run_dir"/home/bench-results/upgrade-27b-*.json || fail "the report keeps the candidate revision"

run_upgrade STUB_BAD_DOWNLOAD=1
[ "$status" -eq 1 ] || fail "a download with the wrong sha256 exits 1 (got $status)"
has "sha256" err || fail "a wrong sha256 names the hashes"
[ -e "$run_dir/weights/$weights_file.next" ] && fail "a wrong sha256 keeps no candidate"
[ -e "$run_dir/weights/$weights_file.next.part" ] && fail "a wrong sha256 keeps no partial file"
[ -s "$CALLS" ] && fail "a wrong sha256 stages no preset"
weights_are old-weights || fail "a wrong sha256 keeps the current file"

run_upgrade STUB_DOWNLOAD_FAIL=1
[ "$status" -eq 1 ] || fail "a failed download exits 1 (got $status)"
has "model-upgrade stopped" err || fail "a failed download says the upgrade stopped"

run_upgrade STUB_NO_THINKING=1
[ "$status" -eq 1 ] || fail "a failed thinking check exits 1 (got $status)"
has "thinking: FAIL" out || fail "a failed thinking check prints FAIL"
has "Not pinning; 27b stays at ${pinned_revision:0:12}." out || fail "a failed thinking check says it is not pinning"
[ "$(cat "$CALLS")" = "$fail_calls" ] || fail "a failed check restores the presets and pins nothing"
[ -e "$run_dir/weights/$weights_file.next" ] && fail "a failed check removes the candidate"
weights_are old-weights || fail "a failed check keeps the current file"

upgrade_args=(27b --keep)
run_upgrade STUB_NO_THINKING=1
[ "$status" -eq 1 ] || fail "--keep with a failed check exits 1 (got $status)"
[ -e "$run_dir/weights/$weights_file.next" ] || fail "--keep leaves the candidate for inspection"
weights_are old-weights || fail "--keep still keeps the current file"
upgrade_args=(27b)

upgrade_args=(27b --eval)
run_upgrade
[ "$status" -eq 0 ] || fail "--eval passes a clean review (got $status)"
grep -qxF 'pr-review-eval --model qwen3.8-27b-cc@next --json' "$CALLS" || fail "--eval runs the review eval on the candidate"
has "eval: 4 of 4 bugs caught, 0 false blockers, 0 unparsable" out || fail "--eval prints the eval verdict"
grep -qxF 'task-eval --model qwen3.8-27b-cc@next --json' "$CALLS" || fail "--eval runs the task eval on the candidate"
has "tasks: 5/5 green, median 40.0s (no baseline)" out || fail "--eval without a baseline only records the task eval"
grep -q '"task_eval"' "$run_dir"/home/bench-results/upgrade-27b-*.json || fail "the report keeps the task eval"

write_baseline() {
  printf '{"model": "%s", "size": "27b", "runs": [], "total": {"green": %s, "runs": 5, "median_seconds": %s, "p90_seconds": 70.0}}\n' "$2" "$3" "$4" > "$baseline_dir/task-eval-$1.json"
}

baseline_dir="$tmp/baselines"
mkdir -p "$baseline_dir"
write_baseline 20250101-000000 qwen3.8-27b-cc 5 100.0
write_baseline 20250102-000000 qwen3.8-27b-cc 5 40.0
write_baseline 20250103-000000 qwen3.8-27b-cc@next 5 10.0
run_upgrade
[ "$status" -eq 0 ] || fail "--eval passes when the task eval matches the newest baseline (got $status)"
has "tasks: 5/5 green, median 40.0s (baseline 5/5, 40.0s): PASS" out || fail "--eval names the current model's newest baseline"

run_upgrade STUB_TASK_GREEN=4
[ "$status" -eq 1 ] || fail "a green count below the baseline fails the upgrade (got $status)"
has "tasks: 4/5 green, median 40.0s (baseline 5/5, 40.0s): FAIL" out || fail "a dropped green count prints FAIL"

run_upgrade STUB_TASK_MEDIAN=50.0
[ "$status" -eq 0 ] || fail "a median 25% above the baseline still passes (got $status)"

run_upgrade STUB_TASK_MEDIAN=50.1
[ "$status" -eq 1 ] || fail "a median more than 25% above the baseline fails the upgrade (got $status)"
has "tasks: 5/5 green, median 50.1s (baseline 5/5, 40.0s): FAIL" out || fail "a slower median prints FAIL"

write_baseline 20250104-000000 qwen3.8-27b-cc 5 null
run_upgrade STUB_TASK_MEDIAN=90.0
[ "$status" -eq 0 ] || fail "a baseline with no green median only gates the green count (got $status)"
baseline_dir=""

run_upgrade STUB_UNPARSABLE=2
[ "$status" -eq 1 ] || fail "review replies that do not parse fail the upgrade (got $status)"
has "eval: 4 of 4 bugs caught, 0 false blockers, 2 unparsable" out || fail "unparsable review replies are counted"
upgrade_args=(27b)

run_upgrade STUB_CACHE_REUSED=false
[ "$status" -eq 1 ] || fail "a prompt cache that is not reused fails the upgrade (got $status)"
has "cache: not reused" out || fail "a prompt cache that is not reused says so"

run_upgrade STUB_PROBE_FAIL=1
[ "$status" -eq 1 ] || fail "a probe that crashes exits 1 (got $status)"
[ -e "$run_dir/weights/$weights_file.next" ] && fail "a probe that crashes removes the candidate"
grep -qxF 'ollama-profiles --user-presets' "$CALLS" || fail "a probe that crashes restores the presets"

run_upgrade STUB_PIN_FAIL=1
[ "$status" -eq 1 ] || fail "a failed pin exits 1 (got $status)"
has "ollama-models pin 27b" err || fail "a failed pin names the command to rerun"
grep -qxF 'ollama-profiles --user-presets' "$CALLS" || fail "a failed pin still restores the presets"

if [ "$failures" -eq 0 ]; then
  echo "all passed"
else
  echo "$failures failed"
  exit 1
fi
