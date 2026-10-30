#!/usr/bin/env bash
set -u
repo_dir="$(cd "$(dirname "$0")/.." && pwd -P)"
check_script="$repo_dir/bin/model-upgrade"
tmp="$(mktemp -d)"
failures=0
trap 'rm -rf "$tmp"' EXIT

stubs="$tmp/stubs"
mkdir -p "$stubs"

cat > "$stubs/curl" <<'EOF'
#!/bin/sh
[ -n "${STUB_OLLAMA_DOWN:-}" ] && exit 7
echo '{"version":"0.40.8"}'
EOF

cat > "$stubs/ollama" <<'EOF'
#!/bin/sh
case "$1" in
  pull) echo "ollama $*" >> "$CALLS"; [ -z "${STUB_PULL_FAIL:-}" ] ;;
  create|cp|rm) echo "ollama $*" >> "$CALLS" ;;
esac
EOF

cat > "$stubs/ollama-models" <<'EOF'
#!/bin/sh
echo "ollama-models $*" >> "$CALLS"
if [ -n "${STUB_OUTDATED_CURRENT:-}" ]; then
  echo "current  $2"
  exit 0
fi
if [ -n "${STUB_OUTDATED_UNKNOWN:-}" ]; then
  echo "unknown  $2 (no manifest at https://registry.ollama.ai)"
  exit 0
fi
if [ -n "${STUB_OUTDATED_UNPINNED:-}" ]; then
  echo "unpinned $2 (not in ollama/model-digests.json)"
  exit 1
fi
echo "behind   $2 (registry abcdef123456, pin 5642e97495e1)"
exit 1
EOF

cat > "$stubs/speed-check" <<'EOF'
#!/bin/sh
echo "speed-check $*" >> "$CALLS"
if [ -n "${STUB_NO_THINKING:-}" ]; then
  echo "Plan 066 (thinking off): FAIL (qwen3.8-27b-cc-next think 500 -> 40)"
  exit 1
fi
echo "Plan 066 (thinking off): PASS (qwen3.8-27b-cc-next think 500 -> 0)"
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

chmod +x "$stubs"/*

fail() {
  echo "FAIL: $1"
  failures=$((failures + 1))
}

has() {
  grep -qF -- "$1" "$run_dir/$2"
}

upgrade_args=(27b)

run_upgrade() {
  run_dir="$(mktemp -d "$tmp/run.XXXXXX")"
  export CALLS="$run_dir/calls.log"
  : > "$CALLS"
  env PATH="$stubs:$PATH" HOME="$run_dir/home" \
    MODEL_UPGRADE_MODELS="$stubs/ollama-models" MODEL_UPGRADE_SPEED_CHECK="$stubs/speed-check" \
    MODEL_UPGRADE_PROBE="$stubs/ollama-cache-probe" MODEL_UPGRADE_EVAL="$stubs/pr-review-eval" \
    "$@" "$check_script" ${upgrade_args[@]+"${upgrade_args[@]}"} > "$run_dir/out" 2> "$run_dir/err"
  status=$?
}

pass_calls="$(printf '%s\n' \
  "ollama-models outdated qwen3.8:27b-mlx" \
  "ollama pull qwen3.8:27b-mlx" \
  "ollama create qwen3.8-27b-cc-next -f $repo_dir/ollama/Modelfile.27b" \
  "speed-check --thinking-only --model qwen3.8-27b-cc-next" \
  "ollama-cache-probe qwen3.8-27b-cc-next --json" \
  "ollama cp qwen3.8-27b-cc-next qwen3.8-27b-cc" \
  "ollama rm qwen3.8-27b-cc-next")"

fail_calls="$(printf '%s\n' \
  "ollama-models outdated qwen3.8:27b-mlx" \
  "ollama pull qwen3.8:27b-mlx" \
  "ollama create qwen3.8-27b-cc-next -f $repo_dir/ollama/Modelfile.27b" \
  "speed-check --thinking-only --model qwen3.8-27b-cc-next" \
  "ollama-cache-probe qwen3.8-27b-cc-next --json" \
  "ollama rm qwen3.8-27b-cc-next" \
  "ollama rm qwen3.8:27b-mlx")"

upgrade_args=(27b-gguf)
run_upgrade
[ "$status" -eq 2 ] || fail "a GGUF size exits 2 (got $status)"
has "GGUF sizes are pinned by file" err || fail "a GGUF size says to update sizes.json by hand"
[ -s "$CALLS" ] && fail "a GGUF size runs nothing"

upgrade_args=(nosuch)
run_upgrade
[ "$status" -eq 2 ] || fail "an unknown size exits 2 (got $status)"
has "unknown size nosuch" err || fail "an unknown size names the problem"

upgrade_args=(27b)
run_upgrade STUB_OLLAMA_DOWN=1
[ "$status" -eq 2 ] || fail "a stopped Ollama exits 2 (got $status)"
has "Ollama is not answering" err || fail "a stopped Ollama says to start it"
[ -s "$CALLS" ] && fail "a stopped Ollama runs nothing"

run_upgrade STUB_OUTDATED_CURRENT=1
[ "$status" -eq 0 ] || fail "a current base exits 0 (got $status)"
has "qwen3.8:27b-mlx is current; nothing to upgrade" out || fail "a current base says there is nothing to upgrade"
grep -q '^ollama ' "$CALLS" && fail "a current base pulls nothing"

upgrade_args=(27b --force)
run_upgrade STUB_OUTDATED_CURRENT=1
[ "$status" -eq 0 ] || fail "--force upgrades a current base (got $status)"
grep -qxF 'ollama pull qwen3.8:27b-mlx' "$CALLS" || fail "--force pulls a current base"
has "at 5642e97495e1" out || fail "--force on a current base pins the digest already pinned"
upgrade_args=(27b)

run_upgrade STUB_OUTDATED_UNKNOWN=1
[ "$status" -eq 2 ] || fail "a base with no registry manifest exits 2 (got $status)"
has "has no manifest in the registry" err || fail "a base with no registry manifest says to check the network"
grep -q '^ollama ' "$CALLS" && fail "a base with no registry manifest pulls nothing"

run_upgrade STUB_OUTDATED_UNPINNED=1
[ "$status" -eq 2 ] || fail "a base with no pin exits 2 (got $status)"
has "ollama-models outdated said: unpinned qwen3.8:27b-mlx" err || fail "a base with no pin quotes the outdated line"
grep -q '^ollama ' "$CALLS" && fail "a base with no pin pulls nothing"

run_upgrade
[ "$status" -eq 0 ] || fail "a behind base that passes exits 0 (got $status)"
[ "$(cat "$CALLS")" = "$pass_calls" ] || fail "a pass pulls, creates, checks, promotes and removes the candidate in order"
has "thinking: PASS" out || fail "a pass prints the thinking verdict"
has "cache: reused" out || fail "a pass prints the cache verdict"
has "eval: skipped" out || fail "without --eval the verdict says the eval was skipped"
has "Next: bin/ollama-models pin qwen3.8:27b-mlx && git add ollama/model-digests.json && git commit -m 'chore: pin qwen3.8:27b-mlx at abcdef123456'" out || fail "a pass prints the pin command"
grep -q '"registry_digest": "abcdef123456"' "$run_dir"/home/bench-results/upgrade-27b-*.json || fail "the report keeps the registry digest"

run_upgrade STUB_NO_THINKING=1
[ "$status" -eq 1 ] || fail "a failed thinking check exits 1 (got $status)"
has "thinking: FAIL" out || fail "a failed thinking check prints FAIL"
has "Not pinning; qwen3.8:27b-mlx stays at its current pin." out || fail "a failed thinking check says it is not pinning"
[ "$(cat "$CALLS")" = "$fail_calls" ] || fail "a failed check removes the candidate, then the base, and promotes nothing"

upgrade_args=(27b --keep)
run_upgrade STUB_NO_THINKING=1
[ "$status" -eq 1 ] || fail "--keep with a failed check exits 1 (got $status)"
grep -qxF 'ollama rm qwen3.8-27b-cc-next' "$CALLS" && fail "--keep leaves the candidate for inspection"
grep -qxF 'ollama rm qwen3.8:27b-mlx' "$CALLS" || fail "--keep still removes the base"
upgrade_args=(27b)

upgrade_args=(27b --eval)
run_upgrade
[ "$status" -eq 0 ] || fail "--eval passes a clean review (got $status)"
grep -qxF 'pr-review-eval --model qwen3.8-27b-cc-next --json' "$CALLS" || fail "--eval runs the review eval on the candidate"
has "eval: 4 of 4 bugs caught, 0 false blockers, 0 unparsable" out || fail "--eval prints the eval verdict"

run_upgrade STUB_UNPARSABLE=2
[ "$status" -eq 1 ] || fail "review replies that do not parse fail the upgrade (got $status)"
has "eval: 4 of 4 bugs caught, 0 false blockers, 2 unparsable" out || fail "unparsable review replies are counted"
upgrade_args=(27b)

run_upgrade STUB_CACHE_REUSED=false
[ "$status" -eq 1 ] || fail "a prompt cache that is not reused fails the upgrade (got $status)"
has "cache: not reused" out || fail "a prompt cache that is not reused says so"

run_upgrade STUB_PULL_FAIL=1
[ "$status" -eq 1 ] || fail "a failed pull exits 1 (got $status)"
has "model-upgrade stopped" err || fail "a failed pull says the upgrade stopped"
grep -q '^ollama rm' "$CALLS" && fail "a failed pull removes nothing"

run_upgrade STUB_PROBE_FAIL=1
[ "$status" -eq 1 ] || fail "a probe that crashes exits 1 (got $status)"
grep -qxF 'ollama rm qwen3.8-27b-cc-next' "$CALLS" || fail "a probe that crashes removes the candidate"
grep -qxF 'ollama rm qwen3.8:27b-mlx' "$CALLS" || fail "a probe that crashes restores the base"

if [ "$failures" -eq 0 ]; then
  echo "all passed"
else
  echo "$failures failed"
  exit 1
fi
