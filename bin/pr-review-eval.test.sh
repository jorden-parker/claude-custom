#!/usr/bin/env bash
set -u
repo="$(cd "$(dirname "$0")/.." && pwd -P)"
eval_script="$repo/bin/pr-review-eval"
sandbox="$(mktemp -d)"
trap 'rm -rf "$sandbox"' EXIT
failures=0
mkdir -p "$sandbox/tmp"
export TMPDIR="$sandbox/tmp"
export STUB_DIR="$sandbox"
scenarios="$sandbox/scenarios"

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
if [ -e a.py ]; then
  finding='{"label": "issue", "blocking": true, "path": "a.py", "line": 2, "summary": "y is set", "why": "", "confidence": "high"}'
else
  finding='{"label": "issue", "blocking": true, "path": "b.md", "line": 1, "summary": "heading is wrong", "why": "", "confidence": "high"}'
fi
skipped='[]'
if [ -e "$STUB_DIR/skip-unparsable" ]; then
  skipped='[{"path": "x", "note": "skipped (unparsable answer)"}]'
fi
printf '{"number": null, "verdict": "REQUEST CHANGES", "summary": "stub", "findings": [%s], "fallow": {"status": "not run", "lines": []}, "skipped": %s}\n' "$finding" "$skipped"
STUB
chmod +x "$sandbox/reviewer"

printf '#!/usr/bin/env bash\nexit 3\n' > "$sandbox/failing"
printf '#!/usr/bin/env bash\nexit 0\n' > "$sandbox/silent"
chmod +x "$sandbox/failing" "$sandbox/silent"

mkdir -p "$scenarios/buggy/base" "$scenarios/buggy/head" "$scenarios/clean/base" "$scenarios/clean/head"
printf 'x = 1\n' > "$scenarios/buggy/base/a.py.fixture"
printf 'x = 2\ny = 3\n' > "$scenarios/buggy/head/a.py.fixture"
cat > "$scenarios/buggy/expected.json" <<'JSON'
{
  "title": "buggy: add y",
  "body": "adds y",
  "bugs": [{"id": "y", "path": "a.py", "anchors": ["y = 3"], "what": "y is set to 3"}],
  "clean": [],
  "verdicts": ["REQUEST CHANGES"]
}
JSON
printf 'old\n' > "$scenarios/clean/base/b.md.fixture"
printf 'new\n' > "$scenarios/clean/head/b.md.fixture"
cat > "$scenarios/clean/expected.json" <<'JSON'
{
  "title": "clean: rewrite b",
  "body": "rewrites b",
  "bugs": [],
  "clean": ["b.md"],
  "verdicts": ["APPROVE", "APPROVE WITH COMMENTS"]
}
JSON

rm -f "$sandbox/reviewer.args"
"$eval_script" --model stub --reviewer "$sandbox/reviewer" --scenarios "$scenarios" --scenario buggy -- --full-file-lines 200 >/dev/null 2>"$sandbox/buggy.err"
check "reviewer got --model stub" grep -qF -- '--model stub' "$sandbox/reviewer.args"
check "reviewer got --range main..change" grep -qF -- '--range main..change' "$sandbox/reviewer.args"
check "reviewer got --json" grep -qF -- '--json' "$sandbox/reviewer.args"
check "extra args after -- reach the reviewer" grep -qF -- '--full-file-lines 200' "$sandbox/reviewer.args"
check "reviewer repo has the head commit" test "$(sed -n 1p "$sandbox/reviewer.log")" = "buggy: add y"
check "reviewer repo has the base commit" test "$(sed -n 2p "$sandbox/reviewer.log")" = base
check "reviewer sees the changed path" test "$(cat "$sandbox/reviewer.diff")" = "a.py "
check "stub progress reaches stderr" grep -qF 'stub progress' "$sandbox/buggy.err"
check "scenario name reaches stderr" grep -qF 'pr-review-eval: scenario buggy' "$sandbox/buggy.err"

"$eval_script" --model stub --reviewer "$sandbox/reviewer" --scenarios "$scenarios" >"$sandbox/out.txt" 2>"$sandbox/err.txt"
status=$?
check "eval exits 0 across scenarios" test "$status" -eq 0
check "each scenario has a header" grep -qx '== buggy ==' "$sandbox/out.txt"
check "clean scenario has a header" grep -qx '== clean ==' "$sandbox/out.txt"
check "buggy scenario scores its bug" grep -qF 'score: caught 1/1 (blocking 1/1), false blockers 0' "$sandbox/out.txt"
check "buggy verdict is right" grep -qF 'verdict REQUEST CHANGES (expected REQUEST CHANGES): right' "$sandbox/out.txt"
check "verdict is checked" grep -qF 'verdict REQUEST CHANGES (expected APPROVE or APPROVE WITH COMMENTS): wrong' "$sandbox/out.txt"
check "total line sums scenarios" grep -qE '^total: caught 1/1 \(blocking 1/1\), false blockers 1, clean-file findings 1, verdicts 1/2, unparsable 0, [0-9.]+s$' "$sandbox/out.txt"
check "--scenario picks one" test "$("$eval_script" --model stub --reviewer "$sandbox/reviewer" --scenarios "$scenarios" --scenario clean | grep -c '^== ')" = 1

json="$("$eval_script" --model stub --reviewer "$sandbox/reviewer" --scenarios "$scenarios" --json 2>/dev/null)"
check "json verdicts_ok is 1" test "$(jq .total.verdicts_ok <<<"$json")" = 1
check "json clean verdict is wrong" test "$(jq .scenarios.clean.verdict_ok <<<"$json")" = false
check "json buggy caught is 1" test "$(jq .scenarios.buggy.caught <<<"$json")" = 1
check "json total false blockers is 1" test "$(jq .total.false_blockers <<<"$json")" = 1

touch "$sandbox/skip-unparsable"
skipped_json="$("$eval_script" --model stub --reviewer "$sandbox/reviewer" --scenarios "$scenarios" --scenario buggy --json 2>/dev/null)"
rm -f "$sandbox/skip-unparsable"
check "json counts unparsable skips" test "$(jq .total.unparsable <<<"$skipped_json")" = 1

"$eval_script" --model stub --reviewer "$sandbox/reviewer" --scenarios "$scenarios" --scenario nope >/dev/null 2>"$sandbox/unknown.err"
unknown_status=$?
check "unknown scenario exits 2" test "$unknown_status" -eq 2
check "unknown scenario is named" grep -qF 'pr-review-eval: no scenario nope' "$sandbox/unknown.err"

"$eval_script" --model stub --reviewer "$sandbox/silent" --scenarios "$scenarios" --scenario buggy >/dev/null 2>"$sandbox/silent.err"
silent_status=$?
check "reviewer with no JSON exits 1" test "$silent_status" -eq 1
check "reviewer with no JSON gets a clear message" grep -qF 'did not print JSON' "$sandbox/silent.err"

"$eval_script" --model stub --reviewer "$sandbox/failing" --scenarios "$scenarios" >/dev/null 2>&1
failing_status=$?
check "reviewer exit status becomes the eval exit status" test "$failing_status" -eq 3
check "no temp repo is left behind" test -z "$(find "$sandbox/tmp" -name 'pr-review-eval-*')"

if [ "$failures" -eq 0 ]; then
  echo "all passed"
else
  echo "$failures failed"
  exit 1
fi
