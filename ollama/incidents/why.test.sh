#!/usr/bin/env bash
set -u
here="$(cd "$(dirname "$0")" && pwd)"
why="$here/why.py"
tmp="$(made="$(mktemp -d)" && cd "$made" && pwd -P)" || exit 1
failures=0
case_dir=""

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

new_case() {
  case_dir="$(mktemp -d "$tmp/case.XXXXXX")"
  mkdir -p "$case_dir/proxy" "$case_dir/incidents"
}

proxy_rows() { cat > "$case_dir/proxy/requests.jsonl"; }

incident_rows() {
  cat > "$case_dir/incidents/session.jsonl"
  printf '%s\n' "$case_dir/incidents/session.jsonl" > "$case_dir/incidents/current"
}

run_why() {
  "$why" --proxy-log "$case_dir/proxy/requests.jsonl" --incidents-dir "$case_dir/incidents" "$@" > "$case_dir/out" 2> "$case_dir/err"
  status=$?
}

line_of() { grep "^$1:" "$case_dir/out" | head -1; }
out_has() { grep -q -- "$1" "$case_dir/out"; }
line_has() { line_of "$1" | grep -q -- "$2"; }
line_count() { wc -l < "$case_dir/out" | tr -d ' '; }

system_drift_row='{"ts":"2026-11-02T14:04:00.000Z","request_id":"r2","sections":5,"stable_sections":0,"diverged_at":"system","offset":41,"diff":"Monday 2026-11-02.\"}]","prompt_bytes":4100,"ledger":{"system":900,"tools":{"read_file":300},"messages":2800}}'
message_drift_row='{"ts":"2026-11-02T14:03:00.000Z","request_id":"r1","sections":5,"stable_sections":4,"diverged_at":"message:4","offset":0,"diff":"{\"content\":\"next\"","prompt_bytes":4000,"ledger":{"system":900,"tools":{"read_file":300},"messages":2700}}'
first_row='{"ts":"2026-11-02T14:02:00.000Z","request_id":"r0","sections":5,"stable_sections":0,"diverged_at":null,"offset":null,"diff":null,"prompt_bytes":3900,"ledger":{"system":900,"tools":{"read_file":300},"messages":2600}}'
stable_row='{"ts":"2026-11-02T14:05:00.000Z","request_id":"r3","sections":5,"stable_sections":5,"diverged_at":null,"offset":null,"diff":null,"prompt_bytes":4200,"ledger":{"system":900,"tools":{"read_file":300},"messages":2900}}'

new_case
run_why
check "empty inputs exit 0" [ "$status" = 0 ]
check "empty inputs find nothing wrong" line_has verdict "nothing wrong"
check "empty inputs have no fix" line_has fix "nothing to do"
check "empty inputs count no requests" line_has prefix "0 requests"
check "empty inputs name no drift" line_has drift none
check "the verdict fits one screen" [ "$(line_count)" -le 8 ]

new_case
printf '%s\n' "$first_row" "$message_drift_row" "$system_drift_row" "$stable_row" | proxy_rows
run_why
check "a drift at system is the verdict without incidents" line_has verdict "prompt drift at system"
check "the drift evidence shows the diverging offset" line_has evidence "offset 41"
check "the drift evidence quotes the diff" line_has evidence 'Monday 2026-11-02'
check "the drift fix names the volatile text" line_has fix 'move the volatile line after the stable prefix: "Monday 2026-11-02'
check "the prefix rate skips the first request" line_has prefix "67% of 3 requests stable through tools"
check "the top diverging sections carry counts" line_has drift "system 1 · message:4 1"

new_case
printf '%s\n' "$first_row" "$system_drift_row" | proxy_rows
incident_rows <<'EOF'
{"ts": "2026-11-02T14:04:03.000Z", "cause": "reprefilled", "detail": "prompt eval time = 52000.00 ms / 65450 tokens", "tokens": 65450, "rule": "reprefilled/prompt-eval", "preceded_by": null}
EOF
run_why
check "a reprefill 3s after a drifting request joins it" line_has evidence "the request 3s before it diverged at system"

new_case
printf '%s\n' "$first_row" "$system_drift_row" | proxy_rows
incident_rows <<'EOF'
{"ts": "2026-11-02T14:04:20.000Z", "cause": "reprefilled", "detail": "prompt eval time = 52000.00 ms / 65450 tokens", "tokens": 65450, "rule": "reprefilled/prompt-eval", "preceded_by": null}
EOF
run_why
check "a reprefill 20s after a request joins nothing" line_has evidence "no request within 5s before it"
check "an unexplained reprefill still names the drift" line_has verdict "prompt drift at system"

new_case
printf '%s\n' "$first_row" "$system_drift_row" | proxy_rows
incident_rows <<'EOF'
{"ts": "2026-11-02T14:04:01.000Z", "cause": "evicted", "detail": "msg=\"unload\"", "tokens": null, "rule": "evicted/unload"}
{"ts": "2026-11-02T14:04:02.000Z", "cause": "truncated", "detail": "truncating input prompt limit=65536 prompt=70100", "tokens": 70100, "rule": "truncated/input-prompt"}
{"ts": "2026-11-02T14:04:03.000Z", "cause": "compacted", "detail": "{\"subtype\": \"compact_boundary\"}", "tokens": 52000, "rule": "compacted/transcript"}
EOF
run_why
check "truncation beats eviction, drift and compaction" line_has verdict "^verdict: truncated"
check "the truncation evidence counts the rows" line_has evidence "1 truncated"
check "the truncation evidence shows the prompt size" line_has evidence "70100 tokens"
check "the truncation fix renders the profiles" line_has fix "bin/ollama-profiles"

new_case
incident_rows <<'EOF'
{"ts": "2026-11-02T14:04:01.000Z", "cause": "evicted", "detail": "msg=\"unload\"", "tokens": null, "rule": "evicted/unload"}
{"ts": "2026-11-02T14:04:03.000Z", "cause": "compacted", "detail": "{\"subtype\": \"compact_boundary\"}", "tokens": 52000, "rule": "compacted/transcript"}
EOF
run_why
check "eviction beats compaction" line_has verdict "^verdict: evicted"
check "the eviction fix raises the loaded model count" line_has fix "OLLAMA_MAX_LOADED_MODELS=2"
check "the eviction fix names the lease" line_has fix "CLAUDE_OLLAMA_LEASE"

new_case
incident_rows <<'EOF'
{"ts": "2026-11-02T14:04:03.000Z", "cause": "reprefilled", "detail": "prompt eval time = 52000.00 ms / 65450 tokens", "tokens": 65450, "rule": "reprefilled/prompt-eval", "preceded_by": {"kind": "embed", "ts": "2026-11-02T14:04:02Z"}}
{"ts": "2026-11-02T14:06:03.000Z", "cause": "reprefilled", "detail": "prompt eval time = 52000.00 ms / 65450 tokens", "tokens": 65450, "rule": "reprefilled/prompt-eval", "preceded_by": {"kind": "embed", "ts": "2026-11-02T14:06:02Z"}}
EOF
run_why
check "a reprefill after embed is an eviction" line_has verdict "^verdict: evicted"
check "the reprefill evidence names the preceding event" line_has evidence "2 reprefilled after embed"
check "the reprefill after embed fix raises the loaded model count" line_has fix "OLLAMA_MAX_LOADED_MODELS=2"

new_case
printf '%s\n' "$first_row" "$system_drift_row" | proxy_rows
incident_rows <<'EOF'
{"ts": "2026-11-02T14:04:03.000Z", "cause": "reprefilled", "detail": "prompt eval time = 52000.00 ms / 65450 tokens", "tokens": 65450, "rule": "reprefilled/prompt-eval", "preceded_by": {"kind": "expired", "ts": "2026-11-02T14:04:02Z"}}
EOF
run_why
check "a reprefill after expiry beats drift" line_has verdict "^verdict: reprefilled after expired"
check "the expiry fix raises the keep-alive" line_has fix "OLLAMA_KEEP_ALIVE"

new_case
incident_rows <<'EOF'
{"ts": "2026-11-02T14:04:03.000Z", "cause": "compacted", "detail": "{\"subtype\": \"compact_boundary\"}", "tokens": 52000, "rule": "compacted/transcript"}
{"ts": "2026-11-02T14:04:04.000Z", "cause": "degraded", "detail": "embeddings-off: 3 reprefilled after embed", "tokens": null, "rule": "ladder/embeddings-off"}
EOF
run_why
check "compaction beats a ladder rung" line_has verdict "^verdict: compacted"
check "the compaction evidence shows the pre-compaction size" line_has evidence "52000 tokens"
check "the compaction fix lowers the handoff point" line_has fix "CLAUDE_OLLAMA_HANDOFF_PCT"

new_case
incident_rows <<'EOF'
{"ts": "2026-11-02T14:04:04.000Z", "cause": "degraded", "detail": "embeddings-off: 3 reprefilled after embed", "tokens": null, "rule": "ladder/embeddings-off"}
{"ts": "2026-11-02T14:04:05.000Z", "cause": "aborted", "detail": "error=\"context canceled\"", "tokens": null, "rule": "aborted/context-canceled"}
EOF
run_why
check "a ladder rung beats an abort" line_has verdict "^verdict: degraded"
check "the degraded evidence names the rung" line_has evidence "embeddings-off"
check "the degraded fix inspects the ladder" line_has fix "ladder.py --inspect"

new_case
incident_rows <<'EOF'
{"ts": "2026-11-02T14:04:03.000Z", "cause": "reprefilled", "detail": "prompt eval time = 52000.00 ms / 65450 tokens", "tokens": 65450, "rule": "reprefilled/prompt-eval", "preceded_by": null}
EOF
run_why
check "an unexplained reprefill without drift is its own verdict" line_has verdict "^verdict: reprefilled"
check "the unexplained reprefill fix runs doctor" line_has fix "claude-ollama doctor"

new_case
: > "$case_dir/incidents/session.jsonl"
printf '%s\n' "$case_dir/incidents/session.jsonl" > "$case_dir/incidents/current"
printf '%s\n' '{"ts": "2026-11-02T14:04:03.000Z", "cause": "compacted", "detail": "{}", "tokens": 52000, "rule": "compacted/transcript"}' > "$case_dir/incidents/session.jsonl.latest"
run_why
check "the latest row counts when the file lacks it" line_has verdict "^verdict: compacted"

new_case
incident_rows <<'EOF'
{"ts": "2026-11-02T14:04:03.000Z", "cause": "compacted", "detail": "{}", "tokens": 52000, "rule": "compacted/transcript"}
{"ts": "2026-11-02T14:05:00Z", "kind": "health", "rules": {}, "unmatched": 0, "lines": 3}
{"ts": "2026-11-02T14:05:01Z", "kind": "ladder", "note": "compacted after none: no rung"}
EOF
printf '%s\n' '{"ts": "2026-11-02T14:04:03.000Z", "cause": "compacted", "detail": "{}", "tokens": 52000, "rule": "compacted/transcript"}' > "$case_dir/incidents/session.jsonl.latest"
run_why
check "a latest row already in the file counts once" line_has evidence "1 compacted"
check "health and ladder rows are skipped" [ "$status" = 0 ]

new_case
printf '%s\n' "$tmp/outside.jsonl" > "$case_dir/incidents/current"
printf '%s\n' '{"ts": "2026-11-02T14:04:03.000Z", "cause": "truncated", "detail": "x", "tokens": 1, "rule": "truncated/input-prompt"}' > "$tmp/outside.jsonl"
run_why
check "a current file outside the incidents folder is ignored" line_has verdict "nothing wrong"

new_case
printf '%s\n' "$first_row" "$system_drift_row" "$stable_row" | proxy_rows
incident_rows <<'EOF'
{"ts": "2026-11-02T14:04:03.000Z", "cause": "truncated", "detail": "truncating input prompt limit=65536 prompt=70100", "tokens": 70100, "rule": "truncated/input-prompt"}
EOF
run_why --since 10 --now 2026-11-02T14:30:00Z
check "--since drops older incidents" line_has verdict "nothing wrong"
check "--since drops older requests" line_has prefix "0 requests"
run_why --since 30 --now 2026-11-02T14:30:00Z
check "--since keeps incidents inside the window" line_has verdict "^verdict: truncated"
check "--since keeps requests inside the window" line_has prefix "2 requests"
check "the window is named" out_has "last 30 minutes"

new_case
printf '%s\n' "$first_row" "$message_drift_row" "$system_drift_row" "$stable_row" | proxy_rows
incident_rows <<'EOF'
{"ts": "2026-11-02T14:04:03.000Z", "cause": "evicted", "detail": "msg=\"unload\"", "tokens": null, "rule": "evicted/unload"}
EOF
run_why --json
check "--json exits 0" [ "$status" = 0 ]
check "--json prints one object" [ "$(jq -r .verdict "$case_dir/out")" = evicted ]
check "--json carries the fix" [ "$(jq -r '.fix | contains("OLLAMA_MAX_LOADED_MODELS=2")' "$case_dir/out")" = true ]
check "--json carries the hit rate" [ "$(jq -r .prefix.percent "$case_dir/out")" = 67 ]
check "--json counts the requests" [ "$(jq -r .prefix.requests "$case_dir/out")" = 3 ]
check "--json lists the diverging sections" [ "$(jq -r '.diverging[0].section' "$case_dir/out")" = system ]
check "--json counts the incidents" [ "$(jq -r .incidents.evicted "$case_dir/out")" = 1 ]
check "--json joins the request" [ "$(jq -r '.evidence | contains("3s before")' "$case_dir/out")" = true ]

new_case
printf 'not json\n' | proxy_rows
printf 'not json\n' | incident_rows
run_why
check "unreadable rows are skipped" [ "$status" = 0 ]
check "unreadable rows find nothing wrong" line_has verdict "nothing wrong"

if [ "$failures" -eq 0 ]; then
  echo "all passed"
else
  echo "$failures failed"
  exit 1
fi
