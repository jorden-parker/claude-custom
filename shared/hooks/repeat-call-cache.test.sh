#!/usr/bin/env bash
set -u
hooks_dir="$(cd "$(dirname "$0")" && pwd)"
cache="$hooks_dir/repeat-call-cache.py"
budget="$hooks_dir/friction_budget.py"
failures=0
sandbox="$(mktemp -d)"
trap 'rm -rf "$sandbox"' EXIT
export CLAUDE_CONFIG_DIR="$sandbox/config"
export CLAUDE_TOOL_TELEMETRY="$sandbox/telemetry.jsonl"
repo="$sandbox/repo"
mkdir -p "$repo"
git -C "$repo" init -q
git -C "$repo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m first
printf 'alpha\nbeta\n' > "$repo/notes.txt"
touch -t 202401010000 "$repo/notes.txt"

new_turn() {
  printf '{"session_id":"s1","hook_event_name":"UserPromptSubmit"}' | python3 "$budget"
}

event() {
  local hook_event="$1" tool="$2" input="$3" response="${4:-null}"
  jq -cn --arg event "$hook_event" --arg tool "$tool" --argjson input "$input" --argjson response "$response" --arg cwd "$repo" \
    '{session_id: "s1", hook_event_name: $event, cwd: $cwd, tool_name: $tool, tool_input: $input, tool_response: $response}' \
    | python3 "$cache"
}

after() { event PostToolUse "$@" >/dev/null; }
before() { event PreToolUse "$1" "$2"; }
decision() { if before "$@" | grep -q '"permissionDecision": *"deny"'; then echo deny; else echo allow; fi; }

expect_eq() {
  local label="$1" want="$2" got="$3"
  if [ "$got" != "$want" ]; then
    echo "FAIL: $label (want '$want', got '$got')"
    failures=$((failures + 1))
  fi
}

mentions() { grep -qF -- "$2" <<<"$1" && echo yes || echo no; }

read_input="{\"file_path\":\"$repo/notes.txt\"}"
read_response="{\"type\":\"text\",\"file\":{\"filePath\":\"$repo/notes.txt\",\"content\":\"alpha\\nbeta\\n\",\"numLines\":2}}"

new_turn
expect_eq "a first Read passes" allow "$(decision Read "$read_input")"
after Read "$read_input" "$read_response"
expect_eq "the same Read of an unchanged file is denied" deny "$(decision Read "$read_input")"
expect_eq "the denial points at the earlier call" yes \
  "$(mentions "$(before Read "$read_input")" 'same result as call #1 this turn, unchanged since; use it')"
expect_eq "the hit writes a friction line with the bytes saved" yes \
  "$(mentions "$(cat "$CLAUDE_TOOL_TELEMETRY")" '"hook": "repeat-call-cache"')"
expect_eq "the saved bytes are the recorded output size" yes "$(mentions "$(cat "$CLAUDE_TOOL_TELEMETRY")" '"saved_bytes": 11')"
later_range_input="{\"file_path\":\"$repo/notes.txt\",\"offset\":2}"
expect_eq "a different range passes" allow "$(decision Read "$later_range_input")"
touch "$repo/notes.txt"
expect_eq "a touched file with the same content is still denied" deny "$(decision Read "$read_input")"
snapshot_dir="$CLAUDE_CONFIG_DIR/cache/friction/s1.snapshots"
expect_eq "the served content is kept as a snapshot" 1 "$(find "$snapshot_dir" -type f | wc -l | tr -d ' ')"
expect_eq "the snapshot is private" 600 "$(stat -f %Lp "$(find "$snapshot_dir" -type f)")"
printf 'alpha\nBETA\n' > "$repo/notes.txt"
touch -t 202401020000 "$repo/notes.txt"
narrowed="$(before Read "$read_input")"
expect_eq "a changed file is narrowed, not denied" no "$(mentions "$narrowed" '"deny"')"
expect_eq "the narrowed call allows the rewritten input without a prompt" yes "$(mentions "$narrowed" '"permissionDecision": "allow"')"
expect_eq "the narrowed call never asks" no "$(mentions "$narrowed" '"ask"')"
expect_eq "the narrowed call names the changed line" yes "$(mentions "$narrowed" 'lines 2-2 changed since call #1; showing only them')"
expect_eq "the narrowed input covers the change plus margin inside the file" \
  "$(jq -c '{file_path: "'"$repo/notes.txt"'", offset: 1, limit: 2}' <<<'{}')" \
  "$(jq -c '.hookSpecificOutput.updatedInput' <<<"$narrowed")"

after Read "$read_input" "$read_response"
expect_eq "re-recorded after the change, it is denied again" deny "$(decision Read "$read_input")"
expect_eq "the pointer names the later call number" yes "$(mentions "$(before Read "$read_input")" 'call #2')"

big="$repo/big.txt"
seq -f 'line %g' 1 40 > "$big"
touch -t 202401010000 "$big"
big_input="{\"file_path\":\"$big\"}"
big_response="$(jq -cn --arg path "$big" --rawfile content "$big" '{type: "text", file: {filePath: $path, content: $content, numLines: 40}}')"
after Read "$big_input" "$big_response"
sed -i '' 's/^line 20$/line twenty/' "$big"
touch -t 202401020000 "$big"
narrowed="$(before Read "$big_input")"
expect_eq "a mid-file change gets 3 lines of margin each side" \
  "$(jq -cn --arg path "$big" '{file_path: $path, offset: 17, limit: 7}')" \
  "$(jq -c '.hookSpecificOutput.updatedInput' <<<"$narrowed")"
expect_eq "the context names the changed span" yes "$(mentions "$narrowed" 'lines 20-20 changed since call #3; showing only them')"
expect_eq "the second snapshot joins the first" 2 "$(find "$snapshot_dir" -type f | wc -l | tr -d ' ')"

range_input="{\"file_path\":\"$big\",\"offset\":10,\"limit\":5}"
range_response="$(jq -cn --arg path "$big" --arg content "$(sed -n 10,14p "$big")" '{type: "text", file: {filePath: $path, content: ($content + "\n"), numLines: 5}}')"
after Read "$range_input" "$range_response"
sed -i '' 's/^line 12$/line twelve/' "$big"
touch -t 202401030000 "$big"
narrowed="$(before Read "$range_input")"
expect_eq "a ranged Read maps the change to absolute lines" \
  "$(jq -cn --arg path "$big" '{file_path: $path, offset: 9, limit: 7}')" \
  "$(jq -c '.hookSpecificOutput.updatedInput' <<<"$narrowed")"
expect_eq "the ranged context names the absolute line" yes "$(mentions "$narrowed" 'lines 12-12 changed since call #4')"

wide="$repo/wide.txt"
seq -f 'row %g' 1 400 > "$wide"
touch -t 202401010000 "$wide"
wide_input="{\"file_path\":\"$wide\"}"
after Read "$wide_input" "$(jq -cn --arg path "$wide" --rawfile content "$wide" '{type: "text", file: {filePath: $path, content: $content, numLines: 400}}')"
seq -f 'changed %g' 1 400 > "$wide"
touch -t 202401020000 "$wide"
narrowed="$(before Read "$wide_input")"
expect_eq "a span over 300 lines is cut to the first 300" \
  "$(jq -cn --arg path "$wide" '{file_path: $path, offset: 1, limit: 300}')" \
  "$(jq -c '.hookSpecificOutput.updatedInput' <<<"$narrowed")"
expect_eq "the cut is named" yes "$(mentions "$narrowed" 'lines 1-400 changed since call #5; showing only 1-300 (read on from 301 for the rest)')"

target="$repo/target.txt"
swapped="$repo/swapped.txt"
printf 'one\ntwo\n' > "$target"
printf 'secret\nlines\n' > "$swapped"
touch -t 202401010000 "$target"
target_input="{\"file_path\":\"$target\"}"
after Read "$target_input" "$(jq -cn --arg path "$target" --rawfile content "$target" '{type: "text", file: {filePath: $path, content: $content, numLines: 2}}')"
mv "$target" "$sandbox/moved.txt"
ln -s "$swapped" "$target"
expect_eq "a path swapped for a symlink between the calls passes through untouched" allow "$(decision Read "$target_input")"
expect_eq "the swapped path gets no rewrite" "" "$(before Read "$target_input")"

huge="$repo/huge.txt"
yes 'this line is here to make the file larger than the snapshot cap' | head -n 1200 > "$huge"
touch -t 202401010000 "$huge"
huge_input="{\"file_path\":\"$huge\"}"
after Read "$huge_input" "$(jq -cn --arg path "$huge" --rawfile content "$huge" '{type: "text", file: {filePath: $path, content: $content, numLines: 1200}}')"
expect_eq "a file over 64 KiB keeps no snapshot" 5 "$(find "$snapshot_dir" -type f | wc -l | tr -d ' ')"
printf 'extra\n' >> "$huge"
touch -t 202401020000 "$huge"
expect_eq "without a snapshot a changed file passes through whole" allow "$(decision Read "$huge_input")"
expect_eq "the pass-through rewrites nothing" "" "$(before Read "$huge_input")"

error_input="{\"file_path\":\"$repo/missing.txt\"}"
after Read "$error_input" '"Error: file not found"'
expect_eq "an error result is never cached" allow "$(decision Read "$error_input")"
after Read "$error_input" '{"is_error":true,"content":"ok"}'
expect_eq "a tool error flag is never cached" allow "$(decision Read "$error_input")"

new_turn
expect_eq "a new prompt clears the cache" allow "$(decision Read "$read_input")"
after Read "$read_input" "$read_response"
expect_eq "a record after the new prompt drops the stale snapshots" 1 "$(find "$snapshot_dir" -type f | wc -l | tr -d ' ')"

after mcp__repo__git_status '{}' '[{"type":"text","text":"## main\n M notes.txt"}]'
expect_eq "a repeated git_status is never served from the cache" allow "$(decision mcp__repo__git_status '{}')"

after mcp__code-search__semantic_search '{"query":"where is auth"}' '{"content":[{"type":"text","text":"src/auth.ts:1"}]}'
expect_eq "a repeated search is denied" deny "$(decision mcp__code-search__semantic_search '{"query":"where is auth"}')"
expect_eq "another query passes" allow "$(decision mcp__code-search__semantic_search '{"query":"where is billing"}')"

after Bash '{"command":"ls"}' '{"stdout":"a","stderr":""}'
expect_eq "a tool outside the list is never cached" allow "$(decision Bash '{"command":"ls"}')"

expect_eq "PostToolUse prints nothing" "" "$(event PostToolUse Read "$read_input" "$read_response")"
if printf 'not json' | python3 "$cache"; then :; else
  echo "FAIL: bad input must exit 0"
  failures=$((failures + 1))
fi

if [ "$failures" -eq 0 ]; then
  echo "all passed"
else
  echo "$failures failed"
  exit 1
fi
