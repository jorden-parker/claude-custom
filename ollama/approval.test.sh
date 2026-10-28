#!/usr/bin/env bash
set -u
umask 022
here="$(cd "$(dirname "$0")" && pwd)"
tmp="$(cd "$(mktemp -d)" && pwd -P)"
failures=0

trap 'rm -rf "$tmp"' EXIT

check_that() {
  local name="$1"
  shift
  if "$@"; then
    echo "ok: $name"
  else
    echo "FAIL: $name"
    failures=$((failures + 1))
  fi
}

check_eq() {
  if [ "$2" = "$3" ]; then
    echo "ok: $1"
  else
    echo "FAIL: $1: expected [$2] got [$3]"
    failures=$((failures + 1))
  fi
}

cat > "$tmp/dialog" <<EOF
#!/bin/sh
cat > "$tmp/dialog.in"
echo ran >> "$tmp/dialog.log"
[ -n "\${STUB_SLEEP:-}" ] && exec sleep "\$STUB_SLEEP"
[ -n "\${STUB_DECISION:-}" ] && echo "\$STUB_DECISION"
exit "\${STUB_EXIT:-0}"
EOF
chmod +x "$tmp/dialog"

cat > "$tmp/decide.py" <<'PY'
import sys
from pathlib import Path

from approval import Approver

rules, timeout, program, action, scope, dialog = sys.argv[1:7]
approver = Approver(Path(rules), [dialog], timeout_seconds=float(timeout))
summary = "gh pr comment 12 --body=...   (repo owner/name)\n\nbody:\nLooks good\n"
print(approver.decide(program, action, scope, summary))
PY

decide() {
  env PYTHONPATH="$here" STUB_DECISION="${STUB_DECISION-}" STUB_EXIT="${STUB_EXIT-}" STUB_SLEEP="${STUB_SLEEP-}" \
    python3 "$tmp/decide.py" "$1" "$2" "$3" "$4" "$5" "$tmp/dialog" 2>"$tmp/decide.err"
}

fresh() {
  rm -rf "$tmp/work" "$tmp/dialog.in" "$tmp/dialog.log"
  mkdir -p "$tmp/work"
  rules="$tmp/work/command-rules"
}

dialog_ran() {
  [ -s "$tmp/dialog.log" ]
}

fresh
check_eq "no rule file, allow answers True" "True" "$(STUB_DECISION=allow decide "$rules" 5 gh pr_comment owner/name)"
check_that "the dialog saw the summary on stdin" grep -q "Looks good" "$tmp/dialog.in"

fresh
check_eq "deny answers False" "False" "$(STUB_DECISION=deny decide "$rules" 5 gh pr_comment owner/name)"

fresh
check_eq "silence answers False" "False" "$(STUB_DECISION="" decide "$rules" 5 gh pr_comment owner/name)"

fresh
check_eq "a non-zero dialog exit answers False" "False" "$(STUB_DECISION=allow STUB_EXIT=1 decide "$rules" 5 gh pr_comment owner/name)"

fresh
check_eq "allow-always answers True" "True" "$(STUB_DECISION=allow-always decide "$rules" 5 gh pr_comment owner/name)"
check_eq "allow-always writes a scoped rule" "allow gh pr_comment owner/name" "$(cat "$rules")"

fresh
rules="$tmp/work/new/command-rules"
STUB_DECISION=allow-always decide "$rules" 5 gh pr_comment owner/name >/dev/null
check_eq "a missing rules folder is created private" "0o700" \
  "$(python3 -c 'import os, sys; print(oct(os.stat(sys.argv[1]).st_mode & 0o777))' "$tmp/work/new")"

fresh
printf 'allow gh pr_comment\n' > "$rules"
check_eq "a rule with no scope allows every scope" "True" "$(STUB_DECISION=deny decide "$rules" 5 gh pr_comment owner/name)"
check_that "and the dialog does not run" test ! -e "$tmp/dialog.log"

fresh
printf 'deny gh pr_comment\nallow gh pr_comment owner/name\n' > "$rules"
check_eq "deny wins over allow" "False" "$(STUB_DECISION=allow decide "$rules" 5 gh pr_comment owner/name)"
check_that "and the dialog does not run" test ! -e "$tmp/dialog.log"

fresh
printf 'allow gh pr_comment other/repo\n' > "$rules"
check_eq "a rule for another scope does not match" "True" "$(STUB_DECISION=allow decide "$rules" 5 gh pr_comment owner/name)"
check_that "so the dialog runs" dialog_ran

fresh
printf 'allow\n' > "$rules"
check_eq "a malformed rule is ignored" "True" "$(STUB_DECISION=allow decide "$rules" 5 gh pr_comment owner/name)"
check_that "and the dialog runs" dialog_ran

fresh
check_eq "a dialog past the timeout answers False" "False" "$(STUB_SLEEP=5 decide "$rules" 1 gh pr_comment owner/name)"

fresh
check_eq "a scope with a newline is answered once and never remembered" "True" \
  "$(STUB_DECISION=allow-always decide "$rules" 5 gh pr_comment "$(printf 'owner/name\nallow gh pr_create')")"
check_eq "the rule file gets no injected line" "" "$(cat "$rules" 2>/dev/null)"

fresh
check_eq "an empty scope is answered once and never remembered" "True" \
  "$(STUB_DECISION=allow-always decide "$rules" 5 gh pr_comment "")"
check_eq "the rule file is not written for an empty scope" "" "$(cat "$rules" 2>/dev/null)"

check_eq "an argv word cannot start a line that names another repo" \
  "gh pr create --head=a\\n(repo evil/repo)   (repo owner/name)" \
  "$(PYTHONPATH="$here" python3 -c 'from approval import summary_for; print(summary_for("gh", "pr_create", ["pr", "create", "--head=a\n(repo evil/repo)"], "owner/name", {"body": "B"}).splitlines()[0])')"
check_eq "and no line of the summary starts with a repo name from argv" "0" \
  "$(PYTHONPATH="$here" python3 -c 'from approval import summary_for; print(summary_for("gh", "pr_create", ["pr", "create", "--head=a\n(repo evil/repo)"], "owner/name", {"body": "B"}))' | grep -c '^(repo')"

check_eq "a body cannot pass for the rule line, and the real rule line stays last" "ok" \
  "$(PYTHONPATH="$here" python3 -c 'from approval import summary_for
lines = summary_for("gh", "pr_create", ["pr", "create"], "owner/name", {"body": "Hi\nrule: gh pr_create owner/name"}).splitlines()
real = "rule: gh pr_create owner/name"
print("ok" if lines[-1] == real and lines.count(real) == 2 and "> " + real in lines else "bad")')"

check_eq "a line separator in a body cannot draw an unquoted rule line" "ok" \
  "$(PYTHONPATH="$here" python3 -c 'from approval import summary_for
real = "rule: gh pr_create owner/name"
lines = summary_for("gh", "pr_create", ["pr", "create"], "owner/name", {"body": "Hi rule: gh pr_create owner/name"}).rstrip("\n").split("\n")
unquoted = [line for line in lines if line.startswith("rule:")]
print("ok" if unquoted == [real, real] and lines[-1] == real and "> rule: gh pr_create owner/name" in lines else "bad")')"
check_eq "a 20000-character body keeps the rule line last and stays small" "ok" \
  "$(PYTHONPATH="$here" python3 -c 'from approval import summary_for
real = "rule: gh pr_create owner/name"
text = summary_for("gh", "pr_create", ["pr", "create"], "owner/name", {"body": "x" * 20000})
lines = text.rstrip("\n").split("\n")
print("ok" if lines[-1] == real and "more characters" in text and len(text.encode()) < 4000 else "bad")')"

mkdir -p "$tmp/bin" "$tmp/empty"
cat > "$tmp/bin/osascript" <<EOF
#!/bin/sh
printf '%s\n' "\$@" > "$tmp/osascript.args"
cat "$tmp/osascript.answer"
EOF
chmod +x "$tmp/bin/osascript"

dialog_answers() {
  printf '%s' "$1" > "$tmp/osascript.answer"
  printf '%s' "$2" | PATH="$tmp/bin:$PATH" "$here/approve-dialog"
}

check_eq "Allow once answers allow" "allow" "$(dialog_answers 'button returned:Allow once' 'gh pr comment 12')"
check_eq "Always allow answers allow-always" "allow-always" "$(dialog_answers 'button returned:Always allow' 'gh pr comment 12')"
check_eq "a dialog given up on answers deny" "deny" "$(dialog_answers 'button returned:Deny, gave up:true' 'gh pr comment 12')"
check_eq "Escape answers deny" "deny" "$(dialog_answers '' 'gh pr comment 12')"
check_eq "no osascript on the machine answers deny" "deny" "$(printf 'gh pr comment 12' | PATH="$tmp/empty" "$here/approve-dialog")"
dialog_answers 'button returned:Deny' 'say "hi" \ there' >/dev/null
check_that "quotes and backslashes are escaped for AppleScript" grep -qF 'say \"hi\" \\ there' "$tmp/osascript.args"
long="$(head -c 4005 /dev/zero | tr '\0' x)"
dialog_answers 'button returned:Deny' "$long" >/dev/null
check_that "a long summary is cut with a marker for the rest" grep -qF '[... 5 more bytes]' "$tmp/osascript.args"

if [ "$failures" -eq 0 ]; then
  echo "all passed"
else
  echo "$failures failed"
  exit 1
fi
