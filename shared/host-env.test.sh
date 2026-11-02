#!/usr/bin/env bash
set -u
here="$(cd "$(dirname "$0")" && pwd)"
host_env="$here/host-env"
sandbox_env="$here/sandbox-env"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
failures=0

check_eq() {
  if [ "$2" = "$3" ]; then
    echo "ok: $1"
  else
    echo "FAIL: $1: want [$2] got [$3]"
    failures=$((failures + 1))
  fi
}

export HOME="$tmp/home"
mkdir -p "$HOME"
unset CLAUDE_SANDBOX_CACHE_DIR
root="$HOME/.cache/claude-sandbox"

check_eq "after sandbox-env, host-env drops every cache variable" 0 "$("$sandbox_env" "$host_env" env | grep -c "=$root/")"
check_eq "and keeps CLAUDE_SANDBOX_CACHE_DIR, so a hook can still tell" "$root" "$("$sandbox_env" "$host_env" printenv CLAUDE_SANDBOX_CACHE_DIR)"
check_eq "a cache variable the sandbox set is unset, not emptied" unset \
  "$(CLAUDE_SANDBOX_CACHE_DIR="$tmp/x" GOMODCACHE="$tmp/x/go/mod" "$host_env" printenv GOMODCACHE || echo unset)"
check_eq "without sandbox-env your own cache variables stay" "$tmp/mine" "$(GOMODCACHE="$tmp/mine" "$host_env" printenv GOMODCACHE)"
check_eq "arguments reach the command unchanged" "a|b c|" "$("$host_env" printf '%s|' a 'b c')"
check_eq "the command's exit code comes back" 7 "$("$host_env" sh -c 'exit 7'; echo $?)"
check_eq "no command is a usage error" 2 "$("$host_env" 2>/dev/null; echo $?)"

if [ "$failures" -eq 0 ]; then echo "all passed"; else echo "$failures failed"; exit 1; fi
