#!/bin/bash
set -u
here="$(cd "$(dirname "$0")" && pwd)"
guard="$here/test-guard"
failures=0

check() {
  if "${@:2}"; then echo "ok: $1"; else echo "FAIL: $1"; failures=$((failures + 1)); fi
}

refuses() {
  ! "$guard" "$@" >/dev/null 2>&1
}

runs() {
  "$guard" "$@" >/dev/null 2>&1
}

probe="$HOME/.claude-ollama/test-guard-probe-$$"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"; rm -f "$probe"' EXIT

check "a guarded command still runs" runs true
check "a guarded command keeps its exit status" refuses false
check "a guarded command can write a temp folder" runs sh -c "touch '$scratch/written'"

if [ "$(uname -s)" = Darwin ] && command -v sandbox-exec >/dev/null 2>&1; then
  check "a guarded command cannot write the real session folder" refuses sh -c "touch '$probe'"
  check "a guarded command cannot write the real LaunchAgents folder" refuses sh -c "touch '$HOME/Library/LaunchAgents/test-guard-probe-$$'"
  check "a guarded command cannot reach the real model server port" refuses curl -s -m 2 -o /dev/null http://127.0.0.1:11435/health
  check "a guarded command cannot run launchctl" refuses launchctl list
  check "a nested guard runs the command once, unsandboxed again" runs env CLAUDE_CUSTOM_TEST_GUARD=1 "$guard" true
fi

if [ "$failures" -gt 0 ]; then
  echo "$failures failed"
  exit 1
fi
echo "all passed"
