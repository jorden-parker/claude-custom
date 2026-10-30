#!/usr/bin/env bash
set -u
script="$(cd "$(dirname "$0")" && pwd)/sandbox-env"
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

for pair in GOMODCACHE=go/mod GOCACHE=go/build npm_config_cache=npm npm_config_store_dir=pnpm/store npm_config_cache_dir=pnpm/cache npm_config_state_dir=pnpm/state PIP_CACHE_DIR=pip UV_CACHE_DIR=uv YARN_CACHE_FOLDER=yarn BUN_INSTALL_CACHE_DIR=bun; do
  check_eq "${pair%%=*} points into the sandbox cache folder" "$root/${pair#*=}" "$("$script" printenv "${pair%%=*}")"
done
check_eq "and no other cache variable is exported" 10 "$("$script" env | grep -c "=$root/")"
check_eq "the folder is created, since the sandbox cannot create it" directory "$([ -d "$root" ] && echo directory)"
check_eq "the command sees the folder in CLAUDE_SANDBOX_CACHE_DIR" "$root" "$("$script" printenv CLAUDE_SANDBOX_CACHE_DIR)"
check_eq "CLAUDE_SANDBOX_CACHE_DIR moves every cache" "$tmp/other/go/build" \
  "$(CLAUDE_SANDBOX_CACHE_DIR="$tmp/other" "$script" printenv GOCACHE)"
check_eq "arguments reach the command unchanged" "a|b c|" "$("$script" printf '%s|' a 'b c')"
check_eq "the command's exit code comes back" 7 "$("$script" sh -c 'exit 7'; echo $?)"
check_eq "no command is a usage error" 2 "$("$script" 2>/dev/null; echo $?)"

if [ "$failures" -eq 0 ]; then echo "all passed"; else echo "$failures failed"; exit 1; fi
