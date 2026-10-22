#!/usr/bin/env bash
set -u
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
reviewer="$repo_dir/bin/pr-review-local"
tmp="$(mktemp -d)"
failures=0
stub_pid=""
port=""
export PR_REVIEW_TEST_TMP="$tmp"
export PR_REVIEW_LOG_DIR="$tmp/default-logs"
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.test
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.test

trap 'stop_stub; rm -rf "$tmp"' EXIT

cat > "$tmp/stub.py" <<'PY'
import json
import sys
import time
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

LOG_PATH, PORT_PATH = sys.argv[1], sys.argv[2]
DELAY_SECONDS = float(sys.argv[3]) if len(sys.argv) > 3 else 0.0
BAD_REPLY = json.dumps([
    {"label": "issue", "blocking": True, "path": "src/bad.ts", "line": 3,
     "summary": "Null deref on empty list", "why": "items[0] when items is []",
     "confidence": "high"},
    {"label": "nitpick", "blocking": False, "path": "src/bad.ts", "line": 2,
     "summary": "Name the variable", "why": "", "confidence": "high"},
])
PRAISE_REPLY = json.dumps([
    {"label": "praise", "blocking": False, "line": None,
     "summary": "Clear usage section", "why": "", "confidence": "medium"},
])
DOCS_BLOCKER_REPLY = json.dumps([
    {"label": "issue", "blocking": True, "path": "README.md", "line": 2,
     "summary": "Sentence is split across two lines", "why": "line break",
     "confidence": "high"},
])
SUMMARY_REPLY = "Adds a widget; one blocking bug."
ERROR_BODY = json.dumps({"type": "error", "error": {"type": "api_error", "message": "model requires 22.0 GiB but only 11.3 GiB are available"}}).encode("utf-8")


def is_summary(body):
    return body.get("system", "").startswith("You summarise")


def is_server_error(body):
    if body["model"] == "oom-model":
        return True
    return body["model"] == "summary-fails-model" and is_summary(body)


def without_confidence(reply):
    findings = json.loads(reply)
    for finding in findings:
        finding.pop("confidence", None)
    return json.dumps(findings)


def plain_reply_for(body):
    if is_summary(body):
        return SUMMARY_REPLY
    user = body["messages"][0]["content"]
    if "File: src/bad.ts" in user:
        return without_confidence(BAD_REPLY) if body["model"] == "no-confidence-model" else BAD_REPLY
    if "File: README.md" in user:
        return DOCS_BLOCKER_REPLY if body["model"] == "docs-blocker-model" else PRAISE_REPLY
    if "File: src/weird.ts" in user:
        return "I think it is fine."
    return "[]"


def reply_for(body):
    reply = plain_reply_for(body)
    if body["model"] == "fenced-model" and reply.startswith("["):
        return "Findings for items[0] and the rest:\n```json\n" + reply + "\n```"
    return reply


def sse(kind, **fields):
    return f"event: {kind}\ndata: {json.dumps(dict(type=kind, **fields))}\n\n".encode("utf-8")


def events_for(text):
    usage = {"input_tokens": 10, "output_tokens": 1}
    yield sse("message_start", message={"id": "msg_stub", "role": "assistant", "usage": usage})
    yield sse("content_block_start", index=0, content_block={"type": "text", "text": ""})
    for start in range(0, len(text), 12):
        yield sse("content_block_delta", index=0, delta={"type": "text_delta", "text": text[start:start + 12]})
    yield sse("content_block_stop", index=0)
    yield sse("message_delta", delta={"stop_reason": "end_turn"}, usage={"output_tokens": 3})
    yield sse("message_stop")


class Handler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        return

    def do_POST(self):
        time.sleep(DELAY_SECONDS)
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        record = {"anthropic-version": self.headers.get("anthropic-version"), "body": body}
        with open(LOG_PATH, "a") as log:
            log.write(json.dumps(record) + "\n")
        if is_server_error(body):
            self.send_response(500)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(ERROR_BODY)
            return
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.end_headers()
        for chunk in events_for(reply_for(body)):
            self.wfile.write(chunk)
            self.wfile.flush()


server = HTTPServer(("127.0.0.1", 0), Handler)
Path(PORT_PATH).write_text(str(server.server_port))
server.serve_forever()
PY

cat > "$tmp/inspect.py" <<'PY'
import json
import sys
from pathlib import Path

EXPECTED_VERSION = "2023-06-01"


def requests(path):
    return [json.loads(line) for line in Path(path).read_text().splitlines() if line]


def user_text(request):
    return request["body"]["messages"][0]["content"]


def system_text(request):
    return request["body"].get("system", "")


def matching(path, pattern):
    return [request for request in requests(path) if pattern in user_text(request)]


def every_request_ok(path, model):
    for request in requests(path):
        body = request["body"]
        if body.get("model") != model or body.get("stream") is not True:
            return False
        if request.get("anthropic-version") != EXPECTED_VERSION or "system" not in body:
            return False
        if body.get("thinking") != {"type": "disabled"}:
            return False
    return True


def main(argv):
    command, path, *args = argv
    if command == "count-user":
        print(len(matching(path, args[0])))
        return 0
    if command == "request-user-has":
        return 0 if args[1] in user_text(matching(path, args[0])[-1]) else 1
    if command == "request-user-lacks":
        return 0 if args[1] not in user_text(matching(path, args[0])[-1]) else 1
    if command == "request-system-has":
        return 0 if args[1] in system_text(matching(path, args[0])[-1]) else 1
    if command == "request-system-lacks":
        return 0 if args[1] not in system_text(matching(path, args[0])[-1]) else 1
    if command == "every-request-ok":
        return 0 if every_request_ok(path, args[0]) else 1
    if command == "last-system-starts":
        last = requests(path)[-1]["body"].get("system", "")
        return 0 if last.startswith(args[0]) else 1
    return 2


sys.exit(main(sys.argv[1:]))
PY

cat > "$tmp/stubbin_gh.sh" <<'SH'
#!/usr/bin/env bash
echo "$*" >> "$PR_REVIEW_TEST_TMP/gh.log"
case "$1" in
  api) echo "src/ok.ts:1 Please add a test" ;;
  pr)
    case "$2" in
      view)
        printf '{"number":%s,"title":"Add widget","url":"https://example.test/pull/%s","author":{"login":"reviewer"},"isDraft":false,"baseRefName":"main","headRefName":"widget","headRefOid":"0123","additions":3,"deletions":0,"changedFiles":4,"body":"Adds the widget."}\n' "$3" "$3" ;;
      checks)
        printf '[{"name":"ci","bucket":"pass"},{"name":"lint","bucket":"pending"}]\n'
        exit 8 ;;
      review)
        cp "$6" "$PR_REVIEW_TEST_TMP/posted.md" ;;
      *) exit 1 ;;
    esac ;;
  *) exit 1 ;;
esac
SH

cat > "$tmp/stubbin_fallow.sh" <<'SH'
#!/usr/bin/env bash
echo "$*" >> "$PR_REVIEW_TEST_TMP/fallow.log"
printf 'pwd=%s\nbad=%s\n' "$PWD" "$(tail -n 1 src/bad.ts)" >> "$PR_REVIEW_TEST_TMP/fallow-env.log"
printf '%s\n' '{"verdict":"warn","summary":{"dead_code_issues":1,"complexity_findings":0,"duplication_clone_groups":0},"dead_code":{"unused_exports":[{"path":"src/ok.ts","line":1,"export_name":"ok","introduced":true},{"path":"src/old.ts","line":9,"export_name":"old","introduced":false}]}}'
SH

mkdir -p "$tmp/stubbin"
mv "$tmp/stubbin_gh.sh" "$tmp/stubbin/gh"
mv "$tmp/stubbin_fallow.sh" "$tmp/stubbin/fallow"
chmod +x "$tmp/stubbin/gh" "$tmp/stubbin/fallow"

git init -q --bare "$tmp/origin.git"
git init -q -b main "$tmp/work"
git -C "$tmp/work" remote add origin "$tmp/origin.git"
mkdir -p "$tmp/work/src"
printf 'export const ok = 1;\n' > "$tmp/work/src/ok.ts"
printf 'export function first(items: string[]) {\n  return items[0];\n}\n' > "$tmp/work/src/bad.ts"
printf 'export const weird = 1;\n' > "$tmp/work/src/weird.ts"
printf '# Widget\n\nUsage section.\n' > "$tmp/work/README.md"
printf '{"name":"t"}\n' > "$tmp/work/package.json"
seq 500 | sed 's/^/const v/; s/$/ = 1;/' > "$tmp/work/big.ts"
printf 'lockfile\n' > "$tmp/work/pnpm-lock.yaml"
git -C "$tmp/work" add -A
git -C "$tmp/work" commit -q -m base
git -C "$tmp/work" push -q origin main
git -C "$tmp/work" checkout -q -b widget
printf 'export const added = 2;\n' >> "$tmp/work/src/ok.ts"
printf 'export const extra = 3;\n' >> "$tmp/work/src/bad.ts"
printf 'export const more = 4;\n' >> "$tmp/work/src/weird.ts"
printf 'More usage.\n' >> "$tmp/work/README.md"
printf 'const appended = 1;\n' >> "$tmp/work/big.ts"
printf 'more\n' >> "$tmp/work/pnpm-lock.yaml"
printf 'PNG\0data\n' > "$tmp/work/img.png"
mkdir -p "$tmp/work/bin"
cat > "$tmp/work/bin/run" <<'SH'
#!/bin/bash
echo "$1"
SH
git -C "$tmp/work" add -A
git -C "$tmp/work" commit -q -m "widget"
git -C "$tmp/work" push -q origin HEAD:refs/pull/7/head
git -C "$tmp/work" checkout -q main
git -C "$tmp/work" checkout -q -b docs-only
printf 'More usage.\n' >> "$tmp/work/README.md"
git -C "$tmp/work" add -A
git -C "$tmp/work" commit -q -m "docs"
git -C "$tmp/work" push -q origin HEAD:refs/pull/8/head
git -C "$tmp/work" checkout -q main

stop_stub() {
  if [ -n "$stub_pid" ]; then
    kill "$stub_pid" 2>/dev/null
    wait "$stub_pid" 2>/dev/null
    stub_pid=""
  fi
}

start_stub() {
  rm -f "$tmp/port"
  python3 "$tmp/stub.py" "$tmp/requests.log" "$tmp/port" "${1:-0}" &
  stub_pid=$!
  for _ in $(seq 200); do
    [ -s "$tmp/port" ] && break
    sleep 0.05
  done
  port="$(cat "$tmp/port")"
}

fail() {
  echo "FAIL: $1"
  failures=$((failures + 1))
}

jq_quiet() {
  jq "$@" > /dev/null
}

check_that() {
  local name="$1"
  shift
  if ! "$@"; then
    fail "$name"
  fi
}

check_not() {
  local name="$1"
  shift
  if "$@"; then
    fail "$name"
  fi
}

check_eq() {
  local name="$1" expected="$2" actual="$3"
  if [ "$expected" != "$actual" ]; then
    fail "$name (expected $expected, got $actual)"
  fi
}

inspect() {
  python3 "$tmp/inspect.py" "$@"
}

report_has() {
  grep -qF -- "$1" "$tmp/report.md"
}

err_has() {
  grep -qF -- "$1" "$tmp/err"
}

fallow_ran_with_merge_base() {
  [ "$(grep -cE '^audit --base [0-9a-f]{40} --format json --quiet$' "$tmp/fallow.log")" = 1 ]
}

review_ref_gone() {
  ! git -C "$tmp/work" show-ref -q refs/pr-review/7
}

review_in_work() {
  (cd "$tmp/work" && PATH="$tmp/stubbin:$PATH" "$reviewer" --base-url "http://127.0.0.1:$port" --model stub-model "$@")
}

start_stub
: > "$tmp/requests.log"
review_in_work 7 --log-dir "$tmp/logs" > "$tmp/report.md" 2> "$tmp/err"
check_eq "exit status" 0 "$?"
check_that "verdict is REQUEST CHANGES" grep -q '^\*\*Verdict:\*\* REQUEST CHANGES\. Adds a widget; one blocking bug\.$' "$tmp/report.md"
check_that "checks line counts buckets" report_has 'CI 1 pass, 0 fail, 1 pending; Fallow warn'
check_that "blocking finding rendered" report_has "- **issue (blocking):** Null deref on empty list — \`src/bad.ts:3\`"
check_that "nitpick under Nits" awk '/^### Nits/ {inside = 1; next} /^### / {inside = 0} inside && /^- \*\*nitpick \(if-minor\):\*\*/ {found = 1} END {exit !found}' "$tmp/report.md"
check_that "praise rendered without a line" report_has '- **praise:** Clear usage section'
check_that "fallow introduced finding listed" report_has 'unused_export src/ok.ts:1 ok'
check_not "fallow finding that is not introduced is omitted" report_has 'src/old.ts'
check_that "fallow ran with the merge base" fallow_ran_with_merge_base
check_that "fallow ran at the PR head, which appended the bad.ts line" grep -qxF 'bad=export const extra = 3;' "$tmp/fallow-env.log"
check_not "fallow did not run in the checkout" grep -qF "pwd=$tmp/work" "$tmp/fallow-env.log"
check_eq "temporary worktree is removed" 1 "$(git -C "$tmp/work" worktree list | wc -l | tr -d ' ')"
check_that "unparsable file is skipped after one retry" report_has 'src/weird.ts: skipped (unparsable answer)'
check_eq "unparsable file gets exactly two requests" 2 "$(inspect count-user "$tmp/requests.log" 'File: src/weird.ts')"
check_that "the retry says the answer was not a JSON array" inspect request-user-has "$tmp/requests.log" 'File: src/weird.ts' 'was not a JSON array'
check_that "big file is omitted from the prompt" inspect request-user-has "$tmp/requests.log" 'File: big.ts' 'Whole file omitted: 501 lines'
check_that "big file's first line is not in the prompt" inspect request-user-lacks "$tmp/requests.log" 'File: big.ts' 'const v1 = 1;'
check_that "short file is included whole" inspect request-user-has "$tmp/requests.log" 'File: src/ok.ts' 'Whole file at the PR head ('
check_that "short file includes its appended line" inspect request-user-has "$tmp/requests.log" 'File: src/ok.ts' 'export const added = 2;'
check_eq "lockfile and binary are not sent to the model" 0 "$(( $(inspect count-user "$tmp/requests.log" 'File: pnpm-lock.yaml') + $(inspect count-user "$tmp/requests.log" 'File: img.png') ))"
check_that "lockfile skip is reported" report_has '- pnpm-lock.yaml: skipped (generated or vendored path)'
check_that "binary skip is reported" report_has '- img.png: skipped (binary)'
check_that "already-raised comments reach the prompt" test "$(inspect count-user "$tmp/requests.log" 'Please add a test')" -ge 1
ok_line=$(git -C "$tmp/work" show widget:src/ok.ts | grep -n 'export const added = 2;' | cut -d: -f1)
check_that "diff lines carry new-file numbers" inspect request-user-has "$tmp/requests.log" 'File: src/ok.ts' '| +export const added = 2;'
check_that "whole file lines carry numbers" inspect request-user-has "$tmp/requests.log" 'File: src/ok.ts' '| export const added = 2;'
check_that "prompt says to use the numbers" inspect request-system-has "$tmp/requests.log" 'File: src/ok.ts' 'starts with its line number in the new file'
check_that "ts prompt has the TypeScript notes" inspect request-system-has "$tmp/requests.log" 'File: src/ok.ts' 'TypeScript/JavaScript pitfalls'
check_that "ts prompt has no Python notes" inspect request-system-lacks "$tmp/requests.log" 'File: src/ok.ts' 'Python pitfalls'
check_that "docs prompt has no language notes" inspect request-system-lacks "$tmp/requests.log" 'File: README.md' 'pitfalls'
check_that "shebang script gets the shell notes" inspect request-system-has "$tmp/requests.log" 'File: bin/run' 'Shell pitfalls'
check_that "prompt defines blocking" inspect request-system-has "$tmp/requests.log" 'File: src/ok.ts' 'a normal, expected input'
check_that "added line carries its exact new-file number" inspect request-user-has "$tmp/requests.log" 'File: src/ok.ts' "$(printf '%5d | +export const added = 2;' "$ok_line")"
check_that "requests name the model and version" inspect every-request-ok "$tmp/requests.log" stub-model
check_that "summary request is last" inspect last-system-starts "$tmp/requests.log" 'You summarise'
review_in_work 7 --model no-confidence-model > "$tmp/noconf.md" 2> "$tmp/noconf.err"
check_that "finding without confidence stays blocking" grep -qF -- '- **issue (blocking):** Null deref on empty list' "$tmp/noconf.md"
check_that "verdict without confidence is REQUEST CHANGES" grep -qF '**Verdict:** REQUEST CHANGES.' "$tmp/noconf.md"
review_in_work 7 --model no-confidence-model --json > "$tmp/noconf.json" 2>/dev/null
check_eq "missing confidence becomes medium" medium "$(jq -r '.findings[] | select(.summary == "Null deref on empty list") | .confidence' "$tmp/noconf.json")"
review_in_work 7 --model docs-blocker-model > "$tmp/docs.md" 2> "$tmp/docs.err"
check_not "docs findings never block" grep -qF -- '- **issue (blocking):** Sentence is split' "$tmp/docs.md"
check_that "docs issue is listed as non-blocking" grep -qF -- '- **issue (non-blocking):** Sentence is split' "$tmp/docs.md"
check_that "docs prompt has no whole file" inspect request-user-lacks "$tmp/requests.log" 'File: README.md' 'Whole file at the PR head'
check_that "docs prompt is told it is docs" inspect request-system-has "$tmp/requests.log" 'File: README.md' 'This file is documentation'
check_that "code prompt is not told it is docs" inspect request-system-lacks "$tmp/requests.log" 'File: src/ok.ts' 'This file is documentation'
check_not "no post without --post" grep -q '^pr review' "$tmp/gh.log"
check_not "no posted body without --post" test -e "$tmp/posted.md"
check_that "stderr names the lookup" err_has 'pr-review-local: looking up PR 7'
check_that "stderr names the fetch" err_has 'pr-review-local: fetching PR #7 and main'
check_that "stderr counts files" grep -qE '^pr-review-local: [0-9]+ files to review, 2 skipped$' "$tmp/err"
check_that "stderr names the comment read" err_has 'pr-review-local: reading review comments already on the PR'
check_that "stderr announces each file before its request" grep -qE '^\[[0-9]+/[0-9]+\] src/bad\.ts: reviewing, [0-9]+ chars$' "$tmp/err"
check_that "stderr echoes the model text" err_has 'Null deref on empty list'
check_that "stderr result line starts on its own line" grep -qE '^\[[0-9]+/[0-9]+\] src/bad\.ts: 2 findings in ' "$tmp/err"
check_that "announce comes before the result" awk '/src\/bad\.ts: reviewing/ {seen = 1} /src\/bad\.ts: 2 findings/ {ok = seen} END {exit !ok}' "$tmp/err"
check_that "stderr names the retry" grep -qE '^\[[0-9]+/[0-9]+\] src/weird\.ts: retrying, the answer was not a JSON array$' "$tmp/err"
check_that "stderr names the Fallow run" err_has 'pr-review-local: running Fallow in . at the PR head'
check_that "stderr gives the Fallow status" err_has 'pr-review-local: Fallow warn'
check_that "stderr names the summary" err_has 'pr-review-local: writing the summary'
check_that "stderr echoes the summary text" err_has 'Adds a widget; one blocking bug.'
check_that "stderr names the CI read" err_has 'pr-review-local: reading CI checks'
check_that "stderr ends with the verdict" grep -qE '^pr-review-local: REQUEST CHANGES after [0-9.]+s$' "$tmp/err"
check_not "no heartbeat on a fast server" err_has 'waiting for the first token'
check_not "model text stays off stdout" grep -qF '"confidence"' "$tmp/report.md"
check_that "finding rendered as a line" grep -qE '^\[[0-9]+/[0-9]+\] src/bad\.ts:   issue \(blocking\)  src/bad\.ts:3  Null deref on empty list$' "$tmp/err"
check_not "raw JSON is not echoed" grep -qF '"confidence"' "$tmp/err"
check_that "unparsable reply is shown on retry" grep -qE '^\[[0-9]+/[0-9]+\] src/weird\.ts:   reply was: I think it is fine\.$' "$tmp/err"
check_not "plain mode has no escape codes" grep -q "$(printf '\033')" "$tmp/err"
cat > "$tmp/frames.py" <<'PY'
import re
import sys

ANSI = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")
CLEAR = "\r\x1b[K"
WIDTH = int(sys.argv[2])
text = open(sys.argv[1], encoding="utf-8", newline="").read()
frames = [segment for segment in text.split(CLEAR)[1:] if "\n" not in segment]
too_wide = [frame for frame in frames if len(ANSI.sub("", frame)) > WIDTH]
print(len(frames), "frames", len(too_wide), "too wide")
sys.exit(0 if frames and not too_wide else 1)
PY
(export COLUMNS=40; review_in_work 7 --color always > "$tmp/color.md" 2> "$tmp/color.err")
check_that "status frames fit one terminal row" python3 "$tmp/frames.py" "$tmp/color.err" 39
check_that "color mode styles the blocking label red" grep -qF "$(printf '\033[31missue (blocking)')" "$tmp/color.err"
check_that "color mode rewrites the status line in place" grep -qF "$(printf '\r\033[K')" "$tmp/color.err"
check_not "stdout stays plain markdown when not a TTY" grep -q "$(printf '\033')" "$tmp/color.md"
logs=("$tmp/logs"/*-pr-7.jsonl)
log="${logs[0]}"
check_that "log file named after the PR" test -f "$log"
mode_of() {
  python3 -c 'import os,sys; print(oct(os.stat(sys.argv[1]).st_mode & 0o777)[2:])' "$1"
}
check_eq "log directory is private" 700 "$(mode_of "$tmp/logs")"
check_eq "log file is private" 600 "$(mode_of "$log")"
check_eq "log starts with start" start "$(head -1 "$log" | jq -r .kind)"
check_eq "log ends with end ok" "end ok" "$(tail -1 "$log" | jq -r '"\(.kind) \(.status)"')"
check_that "log has the live finding" jq_quiet -e 'select(.kind == "finding" and .finding.summary == "Null deref on empty list")' "$log"
check_that "log has the report" jq_quiet -e 'select(.kind == "report") | .markdown | contains("## PR #7")' "$log"
check_not "log has no log path stage" jq_quiet -e 'select(.kind == "stage" and (.message | startswith("log ")))' "$log"
mkdir "$tmp/live-logs"
printf 'http://127.0.0.1:9/\n' > "$tmp/live-logs/.web-url"
review_in_work 7 --log-dir "$tmp/live-logs" > /dev/null 2> "$tmp/live.err"
check_that "stderr links the live reviews page" grep -qE '^pr-review-local: live at http://127\.0\.0\.1:9/reviews/[0-9]{8}-[0-9]{6}-pr-7$' "$tmp/live.err"
live_id=$(sed -n 's#^pr-review-local: live at .*/reviews/##p' "$tmp/live.err")
check_that "live link names an existing log" test -f "$tmp/live-logs/$live_id.jsonl"
check_not "live link is not a log stage" jq_quiet -e 'select(.kind == "stage" and (.message | startswith("live at ")))' "$tmp/live-logs/$live_id.jsonl"
rm -f "$tmp/live-logs/.web-url"
check_that "stderr names the log" grep -qE '^pr-review-local: log .*/logs/[0-9]{8}-[0-9]{6}-pr-7\.jsonl$' "$tmp/err"

review_in_work 7 --post > "$tmp/report.md" 2> "$tmp/err"
check_eq "post run exit status" 0 "$?"
check_that "post sends a comment review" grep -qE '^pr review 7 --comment --body-file ' "$tmp/gh.log"
check_that "posted body equals the printed report" cmp -s "$tmp/posted.md" "$tmp/report.md"
check_that "review ref is deleted afterwards" review_ref_gone
check_that "stderr names the post" err_has 'pr-review-local: posting the review to 7'

review_in_work 7 --json > "$tmp/json.out" 2> "$tmp/err"
check_eq "json verdict" "REQUEST CHANGES" "$(jq -r .verdict "$tmp/json.out")"
check_eq "json lists three findings" 3 "$(jq '.findings | length' "$tmp/json.out")"

(cd "$tmp/work" && PATH="$tmp/stubbin:$PATH" "$reviewer" --base-url http://127.0.0.1:1 --model stub-model 7 --log-dir "$tmp/down-logs" > "$tmp/down.out" 2> "$tmp/down.err")
check_eq "unreachable server exits 1" 1 "$?"
check_that "unreachable server is named in the error" grep -q '^pr-review-local: request to http://127.0.0.1:1/v1/messages failed' "$tmp/down.err"
check_not "no heartbeat after a failed request" grep -qF 'waiting for the first token' "$tmp/down.err"
down_logs=("$tmp/down-logs"/*-pr-7.jsonl)
check_eq "failed run log ends with end error" "end error" "$(tail -1 "${down_logs[0]}" | jq -r '"\(.kind) \(.status)"')"
check_that "failed run log names the failed request" jq_quiet -e 'select(.kind == "error") | .message | contains("request to http://127.0.0.1:1/v1/messages failed")' "${down_logs[0]}"
review_in_work 7 --no-log --log-dir "$tmp/nolog" > /dev/null 2> /dev/null
check_not "--no-log writes no log directory" test -e "$tmp/nolog"
(export PR_REVIEW_LOG_DIR="$tmp/env-logs"; review_in_work 7 > /dev/null 2> /dev/null)
env_logs=("$tmp/env-logs"/*-pr-7.jsonl)
check_that "PR_REVIEW_LOG_DIR is honoured" test -f "${env_logs[0]}"
touch "$tmp/not-a-dir"
review_in_work 7 --log-dir "$tmp/not-a-dir/logs" > "$tmp/unwritable.out" 2> "$tmp/unwritable.err"
check_eq "unwritable log dir still exits 0" 0 "$?"
check_that "unwritable log dir is reported" grep -qF 'pr-review-local: event log disabled:' "$tmp/unwritable.err"

review_in_work 7 --model oom-model > "$tmp/oom.out" 2> "$tmp/oom.err"
check_eq "server error exits 1" 1 "$?"
check_that "server error message is shown" grep -qF 'answered HTTP 500: model requires 22.0 GiB but only 11.3 GiB are available' "$tmp/oom.err"

review_in_work 7 --model summary-fails-model > "$tmp/sumfail.out" 2> "$tmp/sumfail.err"
check_eq "summary failure still exits 0" 0 "$?"
check_that "summary failure is on stderr" grep -qE '^pr-review-local: summary failed: .*model requires 22\.0 GiB' "$tmp/sumfail.err"
check_that "summary failure is in the report" grep -qF 'Summary unavailable:' "$tmp/sumfail.out"

review_in_work 7 --model fenced-model --json > "$tmp/fenced.json" 2> "$tmp/fenced.err"
check_eq "fenced replies parse to the same findings" 3 "$(jq '.findings | length' "$tmp/fenced.json")"
check_not "fenced replies are not skipped" grep -qF 'src/bad.ts: unparsable answer' "$tmp/fenced.err"

(cd "$tmp" && "$reviewer" --model stub-model 7 > "$tmp/norepo.out" 2> "$tmp/norepo.err")
check_eq "outside a repository exits 1" 1 "$?"
check_that "outside a repository says so" grep -qx 'pr-review-local: not inside a git repository' "$tmp/norepo.err"

fallow_lines_before="$(grep -c '' "$tmp/fallow.log")"
review_in_work 8 > "$tmp/report8.md" 2> "$tmp/err8"
check_eq "README-only PR exits 0" 0 "$?"
check_that "fallow is not run without TypeScript" grep -qF 'Fallow not run: no TypeScript changed' "$tmp/report8.md"
check_eq "fallow is not invoked for a README-only PR" "$fallow_lines_before" "$(grep -c '' "$tmp/fallow.log")"
check_that "fallow not-run status on stderr" grep -qF 'pr-review-local: Fallow not run: no TypeScript changed' "$tmp/err8"
check_not "no Fallow run line without TypeScript" grep -qF 'running Fallow' "$tmp/err8"

gh_calls_before=$(grep -c '' "$tmp/gh.log")
review_in_work --range main..widget > "$tmp/range.md" 2> "$tmp/range.err"
check_eq "range run exit status" 0 "$?"
check_that "range report names the range" grep -qxF '## main..widget: widget' "$tmp/range.md"
check_that "range report finds the blocking bug" grep -qF -- '- **issue (blocking):** Null deref on empty list' "$tmp/range.md"
check_that "range report says CI was not checked" grep -qF 'CI not checked (local range)' "$tmp/range.md"
check_eq "range run never calls gh" "$gh_calls_before" "$(grep -c '' "$tmp/gh.log")"
check_that "range prompts name the range" inspect request-user-has "$tmp/requests.log" 'File: src/bad.ts' 'main..widget: widget'
review_in_work --range main..widget --json > "$tmp/range.json" 2>/dev/null
check_eq "range json lists three findings" 3 "$(jq '.findings | length' "$tmp/range.json")"
check_eq "range json has no PR number" null "$(jq '.number' "$tmp/range.json")"
review_in_work 7 --range main..widget > /dev/null 2> "$tmp/both.err"
check_eq "PR and range together is a usage error" 2 "$?"
review_in_work --range main..widget --post > /dev/null 2> "$tmp/rangepost.err"
check_eq "range with --post is a usage error" 2 "$?"
review_in_work --range main > /dev/null 2> "$tmp/badrange.err"
check_eq "range without .. exits 1" 1 "$?"
check_that "bad range is explained" grep -qF 'pr-review-local: --range must be BASE..HEAD' "$tmp/badrange.err"
review_in_work > /dev/null 2> "$tmp/none.err"
check_eq "no PR and no range is a usage error" 2 "$?"

stop_stub
start_stub 0.6
review_in_work 8 --heartbeat-seconds 0.2 > "$tmp/slow.out" 2> "$tmp/slow.err"
check_eq "slow server exit status" 0 "$?"
check_that "heartbeat while waiting for the first token" grep -qE '^pr-review-local: waiting for the first token, [0-9]+\.[0-9]s$' "$tmp/slow.err"
check_that "slow run report is unchanged" grep -qF 'Fallow not run: no TypeScript changed' "$tmp/slow.out"
stop_stub

if [ "$failures" -eq 0 ]; then
  echo "all passed"
else
  echo "$failures failed"
  exit 1
fi
