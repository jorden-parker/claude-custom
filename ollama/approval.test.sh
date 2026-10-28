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

if [ "$failures" -eq 0 ]; then
  echo "all passed"
else
  echo "$failures failed"
  exit 1
fi
