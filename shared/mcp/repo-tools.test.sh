#!/usr/bin/env bash
set -u
umask 022
server="$(cd "$(dirname "$0")" && pwd)/repo-tools.py"
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

contains() {
  case "$1" in
    *"$2"*) return 0 ;;
    *) return 1 ;;
  esac
}

lacks() {
  ! contains "$1" "$2"
}

cat > "$tmp/client.py" <<'PY'
import json
import subprocess
import sys

server, method = sys.argv[1:3]
arguments = json.loads(sys.argv[3]) if len(sys.argv) > 3 else {}
messages = [
    {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "test", "version": "0"}}},
    {"jsonrpc": "2.0", "method": "notifications/initialized"},
]
if method in ("list", "schema"):
    messages.append({"jsonrpc": "2.0", "id": 2, "method": "tools/list"})
else:
    messages.append({"jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": {"name": method, "arguments": arguments}})
stdin = "".join(json.dumps(message) + "\n" for message in messages)
completed = subprocess.run([sys.executable, server], input=stdin, capture_output=True, text=True, timeout=60)
replies = {reply.get("id"): reply for reply in map(json.loads, completed.stdout.splitlines())}
result = replies[2]["result"]
if method == "list":
    print(" ".join(tool["name"] for tool in result["tools"]))
elif method == "schema":
    print(json.dumps(next(tool["inputSchema"] for tool in result["tools"] if tool["name"] == arguments["tool"]), sort_keys=True))
else:
    print(("ERROR " if result["isError"] else "") + "\n".join(item["text"] for item in result["content"]).rstrip("\n"))
PY

cat > "$tmp/session.py" <<'PY'
import json
import subprocess
import sys

server = sys.argv[1]
process = subprocess.Popen([sys.executable, server], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)


def send(message):
    process.stdin.write(json.dumps(message) + "\n")
    process.stdin.flush()
    return json.loads(process.stdout.readline())


send({"jsonrpc": "2.0", "id": 0, "method": "initialize", "params": {"protocolVersion": "2025-06-18"}})
for number, step in enumerate(sys.argv[2:], start=1):
    kind, _, rest = step.partition(":")
    if kind == "sh":
        subprocess.run(rest, shell=True, check=True)
        continue
    name, _, arguments = rest.partition(":")
    result = send({"jsonrpc": "2.0", "id": number, "method": "tools/call", "params": {"name": name, "arguments": json.loads(arguments or "{}")}})["result"]
    print(("ERROR " if result["isError"] else "") + result["content"][0]["text"].rstrip("\n"))
process.stdin.close()
process.wait()
PY

mkdir -p "$tmp/bin"
repo="$tmp/repo"
git init -q -b main "$repo"
git -C "$repo" config user.email test@example.com
git -C "$repo" config user.name Tester
printf 'one\n' > "$repo/notes.txt"
printf 'alpha\n' > "$repo/other.txt"
git -C "$repo" add .
git -C "$repo" commit -q -m "first commit"
printf 'one\ntwo\n' > "$repo/notes.txt"
git -C "$repo" commit -q -am "second commit"
first="$(git -C "$repo" rev-parse --short HEAD~1)"
from_first="{\"base\":\"$first\"}"
stat_from_first="{\"base\":\"$first\",\"stat\":true}"
other_from_first="{\"base\":\"$first\",\"paths\":[\"other.txt\"]}"
at_first="{\"rev\":\"$first\"}"
option_rev="{\"rev\":\"--output=$tmp/written\"}"
option_base="{\"base\":\"--output=$tmp/written\"}"

call() {
  (cd "$repo" && python3 "$tmp/client.py" "$server" "$@")
}

call_without_gh() {
  (cd "$repo" && env PATH=/usr/bin:/bin "$(command -v python3)" "$tmp/client.py" "$server" "$@")
}

check "without gh only the git tools are listed" \
  [ "$(call_without_gh list)" = "git_status git_diff git_log git_show" ]

printf 'one\ntwo\nthree\n' > "$repo/notes.txt"
status="$(call git_status)"
check "git_status names the branch" contains "$status" "## main"
check "git_status lists a changed file" contains "$status" " M notes.txt"

diff="$(call git_diff)"
check "git_diff shows unstaged changes" contains "$diff" "+three"
check "git_diff of staged changes is empty before staging" [ "$(call git_diff '{"staged":true}')" = "(no output)" ]
git -C "$repo" add notes.txt
check "git_diff shows staged changes" contains "$(call git_diff '{"staged":true}')" "+three"
check "git_diff compares against a base revision" contains "$(call git_diff "$from_first")" "+two"
check "git_diff --stat summarises" contains "$(call git_diff "$stat_from_first")" "notes.txt | 2 ++"
check "git_diff limits to paths" [ "$(call git_diff "$other_from_first")" = "(no output)" ]

log="$(call git_log)"
check "git_log lists commits newest first, one line each" contains "$log" "Tester second commit"
check "git_log shows short hashes" contains "$log" "$first "
check "git_log limit caps the commits" [ "$(call git_log '{"limit":1}' | wc -l | tr -d ' ')" = 1 ]
check "git_log follows a path" lacks "$(call git_log '{"path":"other.txt"}')" "second commit"
check "git_log starts from a revision" lacks "$(call git_log "$at_first")" "second commit"

shown="$(call git_show "$at_first")"
check "git_show shows the commit message" contains "$shown" "first commit"
check "git_show shows the diff" contains "$shown" "+alpha"
check "git_show --stat summarises" contains "$(call git_show '{"rev":"HEAD","stat":true}')" "notes.txt | 1 +"

check "a revision that looks like an option is never read as one" \
  contains "$(call git_show "$option_rev")" "ERROR"
check "so git writes no file" [ ! -e "$tmp/written" ]
check "a diff base that looks like an option is refused by git" \
  contains "$(call git_diff "$option_base")" "ERROR"
check "and writes no file either" [ ! -e "$tmp/written" ]

printf '#!/bin/sh\ntouch %s/external-ran\n' "$tmp" > "$tmp/external.sh"
chmod +x "$tmp/external.sh"
git -C "$repo" config diff.external "$tmp/external.sh"
git -C "$repo" config diff.conv.textconv "$tmp/external.sh"
printf '*.txt diff=conv\n' > "$repo/.gitattributes"
call git_diff '{"staged":true}' >/dev/null
call git_show '{"rev":"HEAD"}' >/dev/null
check "git tools never run external diff or textconv programs" [ ! -e "$tmp/external-ran" ]
git -C "$repo" config --unset diff.external
rm "$repo/.gitattributes"

outside_paths='{"paths":["/etc/hosts","/etc/hosts"]}'
check "git_diff refuses absolute paths, which would make git compare any two files" \
  contains "$(call git_diff "$outside_paths")" "ERROR paths must stay inside the repository"
check "git_diff refuses paths that climb out of the repository" \
  contains "$(call git_diff '{"paths":["../x"]}')" "ERROR paths must stay inside the repository"
check "git_log refuses a path outside the repository" \
  contains "$(call git_log '{"path":"/etc"}')" "ERROR paths must stay inside the repository"

mkdir -p "$repo/sub"
planted="$(cd "$repo/sub" && python3 "$tmp/session.py" "$server" \
  "call:git_log:{\"limit\":1}" \
  "sh:git init -q $repo/sub && git -C $repo/sub -c user.email=x@y -c user.name=Planter commit -q --allow-empty -m planted" \
  "call:git_log:{\"limit\":1}")"
check "a .git planted after the server started is never used" lacks "$planted" "planted"
rm -rf "$repo/sub"
mkdir -p "$tmp/not-a-repo"
outside="$(cd "$tmp/not-a-repo" && python3 "$tmp/client.py" "$server" git_status)"
check "outside a git repository the git tools say so" [ "$outside" = "ERROR the session did not start inside a git repository" ]

check "an unknown argument is an error" contains "$(call git_log '{"since":"yesterday"}')" "ERROR unknown arguments: since"
check "a limit over 100 is an error" contains "$(call git_log '{"limit":500}')" "ERROR"
check "a revision that is not text is an error" contains "$(call git_show '{"rev":5}')" "ERROR"
check "git_show needs a revision" contains "$(call git_show)" "ERROR rev is required"
check "paths must be a list of text" contains "$(call git_diff '{"paths":"notes.txt"}')" "ERROR"
check "an unknown tool is an error" contains "$(call git_push)" "ERROR"
check "a GitHub tool without gh says how to get it" \
  contains "$(call_without_gh pr_list '{"repo":"owner/project"}')" "ERROR gh is not installed; install it and run gh auth login"

head -c 30000 /dev/zero | tr '\0' x > "$repo/big.txt"
git -C "$repo" add big.txt
big="$(call git_diff '{"staged":true,"paths":["big.txt"]}')"
check "long output is cut to stay inside the model's context" [ "${#big}" -lt 21000 ]
check "and says how to narrow it" contains "$big" "[truncated: showed 20000 of"

drafts="$tmp/drafts"
export CLAUDE_OLLAMA_DRAFTS_DIR="$drafts"
check "with a drafts folder the draft tools are listed too" \
  [ "$(call_without_gh list)" = "git_status git_diff git_log git_show draft_pr draft_review draft_open" ]
pr_draft='{"title":"Add notes","base":"main","sections":[{"heading":"Summary","body":"Adds **notes**."},{"heading":"Testing","body":"- [x] ran it"}]}'
drafted="$(call draft_pr "$pr_draft")"
check "draft_pr reply carries no console link the session cannot open" lacks "$drafted" "http://"
check "draft_pr says the page opens in the user's browser" contains "$drafted" "opens in the user's browser"
pr_file="$(find "$drafts" -name '*-pr-*.json' 2>/dev/null | head -n 1)"
check "draft_pr writes one draft file" [ -f "$pr_file" ]
check "the drafts folder is private" [ "$(stat -f %Lp "$drafts" 2>/dev/null || stat -c %a "$drafts")" = 700 ]
check "the draft file is private" [ "$(stat -f %Lp "$pr_file" 2>/dev/null || stat -c %a "$pr_file")" = 600 ]
draft_field() {
  python3 -c "import json, sys; value = json.load(open(sys.argv[1]))[sys.argv[2]]; print(value if isinstance(value, (str, int)) else json.dumps(value))" "$1" "$2"
}
check "a PR draft names its kind" [ "$(draft_field "$pr_file" kind)" = pr ]
check "a PR draft takes the head from the current branch" [ "$(draft_field "$pr_file" head)" = main ]
check "a PR draft records the pinned work tree" [ "$(draft_field "$pr_file" project)" = "$repo" ]
check "a PR draft keeps its sections in order" \
  [ "$(draft_field "$pr_file" sections)" = '[{"heading": "Summary", "body": "Adds **notes**."}, {"heading": "Testing", "body": "- [x] ran it"}]' ]
check "the reply names the draft id" contains "$drafted" "$(draft_field "$pr_file" id)"

review_draft='{"pr":12,"event":"REQUEST_CHANGES","summary":"Close.","comments":[{"label":"issue","decorations":["blocking"],"path":"notes.txt","line":2,"body":"Off by one."},{"label":"praise","body":"Nice tests."}]}'
call draft_review "$review_draft" >/dev/null
review_file="$(find "$drafts" -name '*-review-12.json' 2>/dev/null | head -n 1)"
check "draft_review writes a draft named after the PR" [ -f "$review_file" ]
check "a review draft keeps the event" [ "$(draft_field "$review_file" event)" = REQUEST_CHANGES ]
check "a review draft keeps inline and general comments" \
  [ "$(draft_field "$review_file" comments)" = '[{"label": "issue", "decorations": ["blocking"], "path": "notes.txt", "line": 2, "body": "Off by one."}, {"label": "praise", "decorations": [], "body": "Nice tests."}]' ]
pr_id="$(basename "$pr_file" .json)"
check "draft_open asks the opener to open a saved draft" contains "$(call draft_open "{\"id\":\"$pr_id\"}")" "asked for draft $pr_id"
check "draft_open leaves a request file the opener claims" [ -f "$drafts/$pr_id.open" ]
check "draft_open refuses an id that is not saved" contains "$(call draft_open '{"id":"20261029-000000-pr-none"}')" "ERROR id must be a saved draft"
check "draft_open refuses a path that climbs out of the drafts folder" contains "$(call draft_open '{"id":"../x"}')" "ERROR id must be a saved draft"

refused() {
  contains "$(call "$1" "$2")" "ERROR $3"
}
check "a label outside Conventional Comments is refused" \
  refused draft_review '{"pr":1,"event":"COMMENT","summary":"s","comments":[{"label":"bug","body":"b"}]}' "label must be one of"
check "an unknown decoration is refused" \
  refused draft_review '{"pr":1,"event":"COMMENT","summary":"s","comments":[{"label":"issue","decorations":["urgent"],"body":"b"}]}' "decorations must be from"
check "a comment path that climbs out is refused" \
  refused draft_review '{"pr":1,"event":"COMMENT","summary":"s","comments":[{"label":"issue","path":"../x","line":1,"body":"b"}]}' "paths must stay inside the repository"
check "a line without a path is refused" \
  refused draft_review '{"pr":1,"event":"COMMENT","summary":"s","comments":[{"label":"issue","line":3,"body":"b"}]}' "line needs a path"
check "an unknown event is refused" \
  refused draft_review '{"pr":1,"event":"MERGE","summary":"s","comments":[]}' "event must be one of"
check "a PR number must be positive" \
  refused draft_review '{"pr":0,"event":"COMMENT","summary":"s","comments":[]}' "pr must be a positive whole number"
check "a PR title must be one line" \
  refused draft_pr '{"title":"a\nb","base":"main","sections":[{"heading":"h","body":"b"}]}' "title must be one line"
check "a PR draft needs sections" \
  refused draft_pr '{"title":"t","base":"main","sections":[]}' "sections must be a list of 1 to 30"
check "a section needs a heading" \
  refused draft_pr '{"title":"t","base":"main","sections":[{"body":"b"}]}' "heading is required"
check "a base that looks like an option is refused" \
  refused draft_pr '{"title":"t","base":"--force","sections":[{"heading":"h","body":"b"}]}' "base must be a branch name"
check "a refused draft writes no file" [ "$(find "$drafts" -name '*.json' | wc -l | tr -d ' ')" = 2 ]
unset CLAUDE_OLLAMA_DRAFTS_DIR

export REPO_TEST_DIR="$tmp"
cat > "$tmp/bin/gh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$REPO_TEST_DIR/gh.log"
printf 'GH_REPO=%s GH_HOST=%s cwd=%s\n' "$GH_REPO" "$GH_HOST" "$PWD" >> "$REPO_TEST_DIR/gh.env"
cat "$REPO_TEST_DIR/gh-reply"
exit "$(cat "$REPO_TEST_DIR/gh-status")"
SH
chmod +x "$tmp/bin/gh"
printf '[{"number":12}]\n' > "$tmp/gh-reply"
printf '0' > "$tmp/gh-status"
git -C "$repo" remote add origin https://github.com/owner/project.git
export PATH="$tmp/bin:$PATH"
check "with gh on PATH the GitHub tools are listed too" \
  [ "$(call list)" = "git_status git_diff git_log git_show pr_list pr_view pr_diff pr_checks pr_review_comments issue_list issue_view run_list run_view" ]
github_schema() {
  call schema "{\"tool\":\"$1\"}" | python3 -c "import json, sys; schema = json.load(sys.stdin); print(sys.argv[1] in schema['properties'])" "$2"
}
for github_tool in pr_list pr_view pr_diff pr_checks pr_review_comments issue_list issue_view run_list run_view; do
  check "$github_tool can name another repo" [ "$(github_schema "$github_tool" repo)" = True ]
done
for github_tool in pr_view pr_checks issue_view run_view; do
  check "$github_tool can choose its JSON fields" [ "$(github_schema "$github_tool" fields)" = True ]
done
check "pr_diff can find a PR by branch" [ "$(github_schema pr_diff branch)" = True ]
check "so pr_diff needs no number" [ "$(call schema '{"tool":"pr_diff"}' | python3 -c 'import json, sys; print(json.load(sys.stdin).get("required"))')" = None ]
check "a GitHub tool returns gh's output" [ "$(call pr_view '{"number":12}')" = '[{"number":12}]' ]
check "and runs gh with the tool's argv" \
  [ "$(tail -n 1 "$tmp/gh.log")" = "pr view 12 --json number,title,body,state,author,headRefName,baseRefName,url,isDraft,reviewDecision,labels,files,comments,reviews" ]
check "gh runs for the origin's repository with GH_HOST set" \
  [ "$(tail -n 1 "$tmp/gh.env" | cut -d' ' -f1-2)" = "GH_REPO=owner/project GH_HOST=github.com" ]
check "and gh does not run inside the repository" \
  [ "$(grep -c "cwd=$repo\$" "$tmp/gh.env")" = 0 ]
call pr_view '{"number":12,"repo":"other/repo"}' >/dev/null
check "repo picks another repository" \
  [ "$(tail -n 1 "$tmp/gh.env" | cut -d' ' -f1)" = "GH_REPO=other/repo" ]
check "a bad repo is refused" \
  [ "$(call pr_list '{"repo":"not-a-repo"}')" = "ERROR gh: repo must be owner/name" ]
check "a bad number is refused" \
  [ "$(call pr_view '{"number":-1}')" = "ERROR gh: number must be a positive whole number" ]
check "a search qualifier outside the allowed list is refused" \
  contains "$(call pr_list '{"search":"org:x"}')" "ERROR gh: search can't use the org: qualifier"
check "fields must come from the tool's choices" \
  contains "$(call pr_view '{"number":12,"fields":"nope"}')" "ERROR gh: fields must be a comma-separated list from:"
printf '%s\n' '[{"bucket":"pending"}]' > "$tmp/gh-reply"
printf '8' > "$tmp/gh-status"
check "output from gh that exits non-zero, like pending checks, is still a result" \
  [ "$(call pr_checks '{"number":12}')" = '[{"bucket":"pending"}]' ]
printf '' > "$tmp/gh-reply"
printf '1' > "$tmp/gh-status"
check "gh that fails with no output is an error with its stderr" \
  [ "$(call pr_view '{"number":12}')" = "ERROR gh failed" ]

if [ "$failures" -eq 0 ]; then
  echo "all passed"
else
  echo "$failures failed"
  exit 1
fi
