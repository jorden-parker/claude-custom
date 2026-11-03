#!/usr/bin/env bash
set -u
hooks_dir="$(cd "$(dirname "$0")" && pwd)"
failures=0
scratch="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$scratch"' EXIT
printf '#!/bin/sh\nexit 0\n' > "$scratch/sandbox-exec"
chmod +x "$scratch/sandbox-exec"

probe() {
  PYTHONPATH="$hooks_dir" python3 -c '
import json, os, sys
from pathlib import Path
import hook_sandbox
with hook_sandbox.confined(["echo", "hi"], "/work/project") as (argv, env):
    profile = argv[argv.index("-f") + 1] if "-f" in argv else None
    mode = oct(os.stat(profile).st_mode & 0o777) if profile else None
    print(json.dumps({"argv": argv, "tmpdir": (env or {}).get("TMPDIR"), "profile": profile, "mode": mode}))
'
}

check() {
  local name="$1" expected="$2" actual="$3"
  if [ "$actual" = "$expected" ]; then echo "ok: $name"; else echo "FAIL: $name: expected '$expected', got '$actual'"; failures=$((failures + 1)); fi
}

field() {
  python3 -c 'import json,sys; v=json.loads(sys.argv[1])[sys.argv[2]]; print(v if not isinstance(v, list) else " ".join(v))' "$1" "$2"
}

unset CLAUDE_CUSTOM_HOOK_SANDBOX
out="$(HOOK_SANDBOX_PLATFORM=darwin CLAUDE_OLLAMA_SANDBOX_EXEC="$scratch/sandbox-exec" probe)"
check "disabled leaves argv unchanged" "echo hi" "$(field "$out" argv)"
check "disabled sets no env" "None" "$(field "$out" tmpdir)"

out="$(CLAUDE_CUSTOM_HOOK_SANDBOX=0 HOOK_SANDBOX_PLATFORM=darwin CLAUDE_OLLAMA_SANDBOX_EXEC="$scratch/sandbox-exec" probe)"
check "zero leaves argv unchanged" "echo hi" "$(field "$out" argv)"

out="$(CLAUDE_CUSTOM_HOOK_SANDBOX=1 HOOK_SANDBOX_PLATFORM=linux CLAUDE_OLLAMA_SANDBOX_EXEC="$scratch/sandbox-exec" probe)"
check "enabled on linux leaves argv unchanged" "echo hi" "$(field "$out" argv)"

out="$(CLAUDE_CUSTOM_HOOK_SANDBOX=1 HOOK_SANDBOX_PLATFORM=darwin CLAUDE_OLLAMA_SANDBOX_EXEC="$scratch/missing" probe)"
check "enabled without sandbox-exec leaves argv unchanged" "echo hi" "$(field "$out" argv)"

out="$(CLAUDE_CUSTOM_HOOK_SANDBOX=1 HOOK_SANDBOX_PLATFORM=darwin CLAUDE_OLLAMA_SANDBOX_EXEC="$scratch/sandbox-exec" probe)"
argv_line="$(field "$out" argv)"
case "$argv_line" in "$scratch/sandbox-exec -f "*) echo "ok: argv starts with sandbox-exec -f" ;; *) echo "FAIL: argv start: $argv_line"; failures=$((failures + 1)) ;; esac
for needle in "-D HOME_DIR=$HOME" "-D TARGET_DIR=/work/project" "-D TMP_DIR=" "-D CACHE_DIR=$HOME/.cache/claude-sandbox" "shared/sandbox-env echo hi"; do
  case "$argv_line" in *"$needle"*) echo "ok: argv has $needle" ;; *) echo "FAIL: argv lacks $needle: $argv_line"; failures=$((failures + 1)) ;; esac
done
check "profile copy is 0600" "0o600" "$(field "$out" mode)"
tmpdir_value="$(field "$out" tmpdir)"
case "$argv_line" in *"-D TMP_DIR=$tmpdir_value "*) echo "ok: TMPDIR matches TMP_DIR" ;; *) echo "FAIL: TMPDIR $tmpdir_value not in argv"; failures=$((failures + 1)) ;; esac
profile_path="$(field "$out" profile)"
if [ -e "$profile_path" ]; then echo "FAIL: profile copy left behind"; failures=$((failures + 1)); else echo "ok: profile copy removed"; fi

if [ "$failures" -eq 0 ]; then echo "all passed"; else exit 1; fi
