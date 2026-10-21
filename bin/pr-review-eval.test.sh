#!/usr/bin/env bash
set -u
repo="$(cd "$(dirname "$0")/.." && pwd -P)"
eval_script="$repo/bin/pr-review-eval"
fixture="$repo/eval/pr-review"
sandbox="$(mktemp -d)"
trap 'rm -rf "$sandbox"' EXIT
failures=0
mkdir -p "$sandbox/tmp"
export TMPDIR="$sandbox/tmp"
export STUB_DIR="$sandbox"

check() {
  local label="$1"
  shift
  if ! "$@"; then
    echo "FAIL: $label"
    failures=$((failures + 1))
  fi
}

cat > "$sandbox/reviewer" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_DIR/reviewer.args"
git log --format=%s > "$STUB_DIR/reviewer.log"
git diff --name-only main..HEAD | sort | tr '\n' ' ' > "$STUB_DIR/reviewer.diff"
echo "stub progress" >&2
cat "$STUB_DIR/review.json"
STUB
chmod +x "$sandbox/reviewer"

printf '#!/usr/bin/env bash\nexit 3\n' > "$sandbox/failing"
chmod +x "$sandbox/failing"

top_line="$(grep -nF 'largest_first[: top - 1]' "$fixture/head/bin/telemetry-report.fixture" | cut -d: -f1)"
cache_line="$(grep -nF 'rm -rf' "$fixture/head/bin/cache-clean.fixture" | cut -d: -f1)"

cat > "$sandbox/review.json" <<JSON
{
  "number": null,
  "verdict": "block",
  "summary": "stub",
  "findings": [
    {"label": "issue", "blocking": true, "path": "bin/telemetry-report", "line": $top_line, "summary": "slices one call short", "why": "", "confidence": "high"},
    {"label": "suggestion", "blocking": false, "path": "bin/cache-clean", "line": $cache_line, "summary": "quote the cache path", "why": "", "confidence": "high"},
    {"label": "issue", "blocking": true, "path": "docs/telemetry.md", "line": 1, "summary": "heading is wrong", "why": "", "confidence": "high"},
    {"label": "praise", "blocking": false, "path": "lib/sizes.py", "line": 2, "summary": "sum is clearer", "why": "", "confidence": "high"}
  ],
  "fallow": {"status": "not run", "lines": []},
  "skipped": [{"path": "x", "note": "skipped (unparsable answer)"}]
}
JSON

out="$("$eval_script" --model stub --reviewer "$sandbox/reviewer" --fixture "$fixture" 2>"$sandbox/err")"
status=$?
last_line="$(tail -n 1 <<<"$out")"
title="$(jq -r .title "$fixture/expected.json")"

check "eval exits 0" test "$status" -eq 0
check "score line counts bugs, blockers, noise and unparsable" \
  grep -Eq '^score: caught 2/3 \(blocking 1/3\), false blockers 1, clean-file findings 1, unparsable 1, [0-9.]+s$' <<<"$last_line"
check "missed bug is listed" grep -Eq '^missed +top-read-as-log-path$' <<<"$out"
check "blocking catch is listed" grep -Eq '^caught blocking +top-slice-off-by-one$' <<<"$out"
check "non-blocking catch is listed" grep -Eq '^caught +cache-dir-empty-or-unquoted$' <<<"$out"
check "stub progress reaches stderr" grep -qF 'stub progress' "$sandbox/err"
check "reviewer got --model stub" grep -qF -- '--model stub' "$sandbox/reviewer.args"
check "reviewer got --range main..change" grep -qF -- '--range main..change' "$sandbox/reviewer.args"
check "reviewer got --json" grep -qF -- '--json' "$sandbox/reviewer.args"
check "reviewer repo has the head commit" test "$(sed -n 1p "$sandbox/reviewer.log")" = "$title"
check "reviewer repo has the base commit" test "$(sed -n 2p "$sandbox/reviewer.log")" = base
check "reviewer sees the four changed paths" test "$(cat "$sandbox/reviewer.diff")" = "bin/cache-clean bin/telemetry-report docs/telemetry.md lib/sizes.py "

json="$("$eval_script" --model stub --reviewer "$sandbox/reviewer" --fixture "$fixture" --json 2>/dev/null)"
check "json caught is 2" test "$(jq .caught <<<"$json")" = 2
check "json false blockers is 1" test "$(jq .false_blockers <<<"$json")" = 1
check "json missed is the log-path bug" test "$(jq -c .missed <<<"$json")" = '["top-read-as-log-path"]'

rm -f "$sandbox/reviewer.args"
"$eval_script" --model stub --reviewer "$sandbox/reviewer" --fixture "$fixture" -- --full-file-lines 200 >/dev/null 2>&1
check "extra args after -- reach the reviewer" grep -qF -- '--full-file-lines 200' "$sandbox/reviewer.args"

"$eval_script" --model stub --reviewer "$sandbox/failing" --fixture "$fixture" >/dev/null 2>&1
failing_status=$?
check "reviewer exit status becomes the eval exit status" test "$failing_status" -eq 3
check "no temp repo is left behind" test -z "$(find "$sandbox/tmp" -name 'pr-review-eval-*')"

if [ "$failures" -eq 0 ]; then
  echo "all passed"
else
  echo "$failures failed"
  exit 1
fi
