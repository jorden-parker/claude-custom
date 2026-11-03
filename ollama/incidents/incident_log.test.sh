#!/usr/bin/env bash
set -u
umask 022
here="$(cd "$(dirname "$0")" && pwd)"
incident_log="$here/incident_log.py"
tmp="$(made="$(mktemp -d)" && cd "$made" && pwd -P)" || exit 1
failures=0

trap 'rm -rf "$tmp"' EXIT

check() {
  local name="$1"
  shift
  if "$@"; then
    echo "ok: $name"
  else
    echo "FAIL: $name"
    failures=$((failures + 1))
  fi
}

equals() {
  if [ "$1" != "$2" ]; then
    echo "  want: $1"
    echo "  got:  $2"
    return 1
  fi
}

mode_of() {
  stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"
}

in_module() {
  local code="$1"
  shift
  PYTHONPATH="$here" python3 -c "import json, sys; from incident_log import *; $code" "$@"
}

raises_value_error() {
  in_module "$@" 2>&1 | grep -q "^ValueError: unknown incident cause"
}

append() {
  python3 "$incident_log" append --file "$tmp/state/incidents/session.jsonl" "$@"
}

check "the cause list is the data file's keys" \
  equals "$(python3 -c 'import json, sys; print(" ".join(json.load(open(sys.argv[1]))))' "$here/causes.json")" "$(in_module 'print(" ".join(CAUSES))')"
check "every cause has a console log level" \
  equals "true" "$(python3 -c 'import json, sys; print(str(all(level in ("error", "warn", "info", "debug") for level in json.load(open(sys.argv[1])).values())).lower())' "$here/causes.json")"
for cause in aborted evicted truncated reprefilled compacted relaunched degraded recovered unknown; do
  check "the cause list holds $cause" equals True "$(in_module "print('$cause' in CAUSES)")"
done

check "a record carries the five fields in order" \
  equals '{"ts": "t", "cause": "aborted", "detail": "d", "tokens": 5, "rule": "r"}' \
  "$(in_module 'print(json.dumps(incident("t", "aborted", "d", 5, "r")))')"
check "a reprefilled record carries preceded_by" \
  equals '{"ts": "t", "cause": "reprefilled", "detail": "d", "tokens": 5, "rule": null, "preceded_by": {"kind": "embed", "ts": "u"}}' \
  "$(in_module 'print(json.dumps(incident("t", "reprefilled", "d", 5, preceded_by={"kind": "embed", "ts": "u"})))')"
check "a reprefilled record without an event keeps a null preceded_by" \
  equals None "$(in_module 'print(incident("t", "reprefilled", "d")["preceded_by"])')"
check "other causes carry no preceded_by" \
  equals False "$(in_module 'print("preceded_by" in incident("t", "evicted", "d", preceded_by={"kind": "embed", "ts": "u"}))')"
check "the detail is clipped to 200 characters" \
  equals 200 "$(in_module 'print(len(incident("t", "aborted", "x" * 400)["detail"]))')"
check "an unknown cause is refused" raises_value_error 'incident("t", "melted", "d")'
check "appending an unknown cause is refused" \
  raises_value_error 'IncidentLog(sys.argv[1]).record({"ts": "t", "cause": "melted", "detail": "d", "tokens": None, "rule": None})' "$tmp/refused.jsonl"
check "a row without a kind is refused as a kind row" \
  sh -c "PYTHONPATH='$here' python3 -c 'from incident_log import IncidentLog; IncidentLog(\"$tmp/kindless.jsonl\").record_kind_row({\"ts\": \"t\"})' 2>&1 | grep -q '^ValueError: '"
check "a refused append writes nothing" test ! -e "$tmp/refused.jsonl"

in_module 'log = IncidentLog(sys.argv[1]); log.prepare(); log.record(incident("t1", "evicted", "first")); log.record(incident("t2", "truncated", "second", 70100, "truncated/input-prompt")); log.record_kind_row({"ts": "t3", "kind": "health", "rules": {}, "unmatched": 0, "lines": 1})' "$tmp/round/incidents.jsonl"
check "records read back in order" \
  equals "evicted truncated" "$(in_module 'print(" ".join(row["cause"] for row in incident_rows(open(sys.argv[1]))))' "$tmp/round/incidents.jsonl")"
check "reading skips rows with a kind, lines that are not JSON and JSON that is not an object" \
  equals 1 "$(in_module 'print(len(list(incident_rows(["not json", "42", "{\"kind\": \"health\"}", "{\"cause\": \"aborted\"}"]))))')"
check "a record round-trips" \
  equals '{"ts": "t2", "cause": "truncated", "detail": "second", "tokens": 70100, "rule": "truncated/input-prompt"}' "$(sed -n 2p "$tmp/round/incidents.jsonl")"
check "the latest file holds the newest incident, never a health row" \
  equals "$(sed -n 2p "$tmp/round/incidents.jsonl")" "$(cat "$tmp/round/incidents.jsonl.latest")"
check "the incidents folder is private" equals 700 "$(mode_of "$tmp/round")"
check "the incidents file is private" equals 600 "$(mode_of "$tmp/round/incidents.jsonl")"
check "the latest file is private" equals 600 "$(mode_of "$tmp/round/incidents.jsonl.latest")"

mkdir -p "$tmp/state/incidents"
append --cause recovered --detail "embeddings-off: quiet" --rule ladder/up
check "the CLI appends a record" \
  equals '"recovered" "embeddings-off: quiet" null "ladder/up"' \
  "$(python3 -c 'import json, sys; row = json.loads(open(sys.argv[1]).readline()); print(" ".join(json.dumps(row[key]) for key in ("cause", "detail", "tokens", "rule")))' "$tmp/state/incidents/session.jsonl")"
check "the CLI stamps a UTC time" \
  python3 -c 'import json, re, sys; sys.exit(0 if re.fullmatch(r"\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ", json.loads(open(sys.argv[1]).readline())["ts"]) else 1)' "$tmp/state/incidents/session.jsonl"
append --cause relaunched --detail note.md --tokens 37806
check "the CLI takes tokens" \
  equals 37806 "$(python3 -c 'import json, sys; print(json.loads(open(sys.argv[1]).readlines()[1])["tokens"])' "$tmp/state/incidents/session.jsonl")"
check "the CLI also writes the latest file" \
  equals "$(sed -n 2p "$tmp/state/incidents/session.jsonl")" "$(cat "$tmp/state/incidents/session.jsonl.latest")"
check "the CLI keeps the file private" equals 600 "$(mode_of "$tmp/state/incidents/session.jsonl")"
append --cause melted --detail d 2> "$tmp/err"
check "the CLI refuses an unknown cause with exit 2" equals 2 "$?"
check "the refusal names the cause" grep -q "melted" "$tmp/err"
check "the refused cause is not written" equals 2 "$(wc -l < "$tmp/state/incidents/session.jsonl" | tr -d ' ')"
append --cause relaunched --detail d --tokens many 2>/dev/null
check "the CLI refuses tokens that are not a number" equals 2 "$?"

if [ "$failures" -eq 0 ]; then
  echo "all passed"
else
  echo "$failures failed"
  exit 1
fi
