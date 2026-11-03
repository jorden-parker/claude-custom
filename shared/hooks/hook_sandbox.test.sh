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
    print(json.dumps({"argv": argv, "tmpdir": (env or {}).get("TMPDIR"), "profile": profile, "mode": mode, "token": (env or {}).get("GH_TOKEN"), "envkeys": sorted((env or {}).keys())}))
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

out="$(GH_TOKEN=secret LC_ALL=C CLAUDE_CUSTOM_HOOK_SANDBOX=1 HOOK_SANDBOX_PLATFORM=darwin CLAUDE_OLLAMA_SANDBOX_EXEC="$scratch/sandbox-exec" probe)"
argv_line="$(field "$out" argv)"
case "$argv_line" in "$scratch/sandbox-exec -f "*) echo "ok: argv starts with sandbox-exec -f" ;; *) echo "FAIL: argv start: $argv_line"; failures=$((failures + 1)) ;; esac
for needle in "-D HOME_DIR=$HOME" "-D TARGET_DIR=/work/project" "-D TMP_DIR=" "-D CACHE_DIR=$HOME/.cache/claude-sandbox" "-D GIT_DIR_REAL=/work/project/.git" "shared/sandbox-env echo hi"; do
  case "$argv_line" in *"$needle"*) echo "ok: argv has $needle" ;; *) echo "FAIL: argv lacks $needle: $argv_line"; failures=$((failures + 1)) ;; esac
done
check "profile copy is 0600" "0o600" "$(field "$out" mode)"
tmpdir_value="$(field "$out" tmpdir)"
case "$argv_line" in *"-D TMP_DIR=$tmpdir_value "*) echo "ok: TMPDIR matches TMP_DIR" ;; *) echo "FAIL: TMPDIR $tmpdir_value not in argv"; failures=$((failures + 1)) ;; esac
check "child env drops GH_TOKEN" "None" "$(field "$out" token)"
env_keys="$(field "$out" envkeys)"
case " $env_keys " in *" PATH "*" TMPDIR "*) echo "ok: child env keeps PATH and TMPDIR" ;; *) echo "FAIL: env keys: $env_keys"; failures=$((failures + 1)) ;; esac
extra_keys="$(python3 -c 'import sys; allowed={"PATH","HOME","USER","LOGNAME","SHELL","TERM","LANG","TMPDIR","CLAUDE_CUSTOM_HOME"}; print(" ".join(k for k in sys.argv[1:] if k not in allowed and not k.startswith("LC_")))' $env_keys)"
check "child env has only allowlisted keys" "" "$extra_keys"
profile_path="$(field "$out" profile)"
if [ -e "$profile_path" ]; then echo "FAIL: profile copy left behind"; failures=$((failures + 1)); else echo "ok: profile copy removed"; fi

refusal_probe() {
  CLAUDE_CUSTOM_HOOK_SANDBOX=1 HOOK_SANDBOX_PLATFORM=darwin CLAUDE_OLLAMA_SANDBOX_EXEC="$scratch/sandbox-exec" PYTHONPATH="$hooks_dir" python3 -c '
import sys
import hook_sandbox
try:
    with hook_sandbox.confined(["echo", "hi"], sys.argv[1]) as (argv, env):
        print("confined")
except hook_sandbox.RefusedTarget:
    print("refused")
' "$1"
}

fake_home="$scratch/fakehome"
mkdir -p "$fake_home/work"
check "home target is refused" "refused" "$(HOME="$fake_home" refusal_probe "$fake_home")"
check "ancestor of home is refused" "refused" "$(HOME="$fake_home" refusal_probe "$scratch")"
check "root is refused" "refused" "$(HOME="$fake_home" refusal_probe "/")"
check "folder under home is confined" "confined" "$(HOME="$fake_home" refusal_probe "$fake_home/work")"
for sensitive in "$fake_home/.ssh" "$fake_home/.config/x" "$fake_home/Library/Keychains" /System/x /Library/x /usr/local/x /bin /sbin /etc /private/etc/x /Applications/x /opt/homebrew/x; do
  check "sensitive $sensitive is refused" "refused" "$(HOME="$fake_home" refusal_probe "$sensitive")"
done
mkdir -p "$fake_home/src/x"
check "home src folder is confined" "confined" "$(HOME="$fake_home" refusal_probe "$fake_home/src/x")"
check "temp folder is confined" "confined" "$(HOME="$fake_home" refusal_probe "$scratch/tempproj")"
check "tmp folder is confined" "confined" "$(HOME="$fake_home" refusal_probe "/tmp/x")"
check "work outside the target is refused" "refused" "$(CLAUDE_CUSTOM_HOOK_SANDBOX=1 HOOK_SANDBOX_PLATFORM=darwin CLAUDE_OLLAMA_SANDBOX_EXEC="$scratch/sandbox-exec" HOME="$fake_home" PYTHONPATH="$hooks_dir" python3 -c '
import hook_sandbox
try:
    with hook_sandbox.confined(["echo"], "'"$fake_home"'/src/x", within="'"$fake_home"'/work") as (argv, env): print("confined")
except hook_sandbox.RefusedTarget:
    print("refused")')"
check "work inside the target is confined" "confined" "$(CLAUDE_CUSTOM_HOOK_SANDBOX=1 HOOK_SANDBOX_PLATFORM=darwin CLAUDE_OLLAMA_SANDBOX_EXEC="$scratch/sandbox-exec" HOME="$fake_home" PYTHONPATH="$hooks_dir" python3 -c '
import hook_sandbox
with hook_sandbox.confined(["echo"], "'"$fake_home"'/src/x", within="'"$fake_home"'/src/x/sub") as (argv, env): print("confined")')"
check "refusal is inactive without the switch" "confined" "$(CLAUDE_CUSTOM_HOOK_SANDBOX=0 HOME="$fake_home" PYTHONPATH="$hooks_dir" python3 -c 'import hook_sandbox
with hook_sandbox.confined(["echo"], "/") as (argv, env): print("confined")')"

main_repo="$scratch/main-repo"
git init -q "$main_repo"
git -C "$main_repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
git -C "$main_repo" worktree add -q "$scratch/linked" -b linked
linked_argv="$(CLAUDE_CUSTOM_HOOK_SANDBOX=1 HOOK_SANDBOX_PLATFORM=darwin CLAUDE_OLLAMA_SANDBOX_EXEC="$scratch/sandbox-exec" PYTHONPATH="$hooks_dir" python3 -c '
import sys
import hook_sandbox
with hook_sandbox.confined(["echo"], sys.argv[1]) as (argv, env):
    print(" ".join(argv))
' "$scratch/linked")"
case "$linked_argv" in *"-D GIT_DIR_REAL=$main_repo/.git "*) echo "ok: worktree resolves the common git dir" ;; *) echo "FAIL: worktree GIT_DIR_REAL: $linked_argv"; failures=$((failures + 1)) ;; esac

if [ "$(uname)" = "Darwin" ] && [ -x /usr/bin/sandbox-exec ]; then
  found="$(CLAUDE_OLLAMA_SANDBOX_EXEC="" PATH="/nonexistent" /usr/bin/python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import hook_sandbox; print(hook_sandbox.sandbox_exec())' "$hooks_dir")"
  check "sandbox-exec found without PATH or override" "/usr/bin/sandbox-exec" "$found"

  project="$scratch/project"
  mkdir -p "$project/.git/hooks" "$project/.claude"
  cat > "$scratch/probe.sh" <<'PROBE'
echo ok > project-file && echo "file:ok"
(echo x > .git/hooks/x) 2>/dev/null && echo "hooks:written"
(echo x > .claude/x) 2>/dev/null && echo "claude:written"
(echo x > "$HOME/hook-sandbox-probe") 2>/dev/null && echo "home:written"
echo "token:${GH_TOKEN:-none}"
python3 -c 'import socket; socket.socket(socket.AF_INET, socket.SOCK_DGRAM).sendto(b"x", ("8.8.8.8", 53)); print("udp:sent")' 2>/dev/null
PROBE
  real_out="$(GH_TOKEN=secret CLAUDE_CUSTOM_HOOK_SANDBOX=1 PYTHONPATH="$hooks_dir" python3 -c '
import subprocess, sys
import hook_sandbox
with hook_sandbox.confined(["sh", sys.argv[2]], sys.argv[1]) as (argv, env):
    result = subprocess.run(argv, cwd=sys.argv[1], env=env, capture_output=True, text=True)
    print(result.stdout, result.stderr)
' "$project" "$scratch/probe.sh" 2>&1)"
  rm -f "$HOME/hook-sandbox-probe"
  cat > "$scratch/git-probe.sh" <<'PROBE'
(echo x > .git/info/x) 2>/dev/null && echo "gitinfo:written"
(echo x > .git/HEAD) 2>/dev/null && echo "githead:written"
(echo x > .envrc) 2>/dev/null && echo "envrc:written"
(mkdir .vscode && echo x > .vscode/tasks.json) 2>/dev/null && echo "vscode:written"
(mkdir .idea && echo x > .idea/x) 2>/dev/null && echo "idea:written"
(echo "gitdir: /tmp/elsewhere" > "$LINKED_GIT_FILE") 2>/dev/null && echo "gitfile:written"
(echo x >> "$COMMON_GIT_DIR/info/x") 2>/dev/null && echo "commondir:written"
echo ok > plain-file && echo "file:ok"
PROBE
  mkdir -p "$project/.git/info"
  git_out="$(CLAUDE_CUSTOM_HOOK_SANDBOX=1 LINKED_GIT_FILE="$scratch/linked/.git" COMMON_GIT_DIR="$main_repo/.git" PYTHONPATH="$hooks_dir" python3 -c '
import os, subprocess, sys
import hook_sandbox
target = sys.argv[1]
with hook_sandbox.confined(["sh", sys.argv[2]], target) as (argv, env):
    result = subprocess.run(argv, cwd=target, env={**env, "LINKED_GIT_FILE": os.environ["LINKED_GIT_FILE"], "COMMON_GIT_DIR": os.environ["COMMON_GIT_DIR"]}, capture_output=True, text=True)
    print(result.stdout, result.stderr)
' "$project" "$scratch/git-probe.sh" 2>&1)"
  linked_out="$(CLAUDE_CUSTOM_HOOK_SANDBOX=1 LINKED_GIT_FILE="$scratch/linked/.git" COMMON_GIT_DIR="$main_repo/.git" PYTHONPATH="$hooks_dir" python3 -c '
import os, subprocess, sys
import hook_sandbox
target = sys.argv[1]
with hook_sandbox.confined(["sh", sys.argv[2]], target) as (argv, env):
    result = subprocess.run(argv, cwd=target, env={**env, "LINKED_GIT_FILE": os.environ["LINKED_GIT_FILE"], "COMMON_GIT_DIR": os.environ["COMMON_GIT_DIR"]}, capture_output=True, text=True)
    print(result.stdout, result.stderr)
' "$scratch/linked" "$scratch/git-probe.sh" 2>&1)"
  case "$git_out" in *file:ok*) echo "ok: git probe project is writable" ;; *) echo "FAIL: git probe ran nothing: $git_out"; failures=$((failures + 1)) ;; esac
  for marker in gitinfo githead envrc vscode idea; do
    case "$git_out" in *"$marker:written"*) echo "FAIL: real run wrote $marker"; failures=$((failures + 1)) ;; *) echo "ok: real run cannot write $marker" ;; esac
  done
  case "$linked_out" in *file:ok*) echo "ok: linked worktree is writable" ;; *) echo "FAIL: linked probe ran nothing: $linked_out"; failures=$((failures + 1)) ;; esac
  for marker in gitfile commondir; do
    case "$linked_out" in *"$marker:written"*) echo "FAIL: linked worktree wrote $marker"; failures=$((failures + 1)) ;; *) echo "ok: linked worktree cannot write $marker" ;; esac
  done
  case "$real_out" in *file:ok*) echo "ok: real run writes in the project" ;; *) echo "FAIL: real run project write: $real_out"; failures=$((failures + 1)) ;; esac
  case "$real_out" in *hooks:written*) echo "FAIL: real run wrote .git/hooks"; failures=$((failures + 1)) ;; *) echo "ok: real run cannot write .git/hooks" ;; esac
  case "$real_out" in *claude:written*) echo "FAIL: real run wrote .claude"; failures=$((failures + 1)) ;; *) echo "ok: real run cannot write .claude" ;; esac
  case "$real_out" in *home:written*) echo "FAIL: real run wrote HOME"; failures=$((failures + 1)) ;; *) echo "ok: real run cannot write HOME" ;; esac
  case "$real_out" in *udp:sent*) echo "FAIL: real run sent UDP"; failures=$((failures + 1)) ;; *) echo "ok: real run cannot send UDP" ;; esac
  case "$real_out" in *token:none*) echo "ok: real run does not see GH_TOKEN" ;; *) echo "FAIL: real run token: $real_out"; failures=$((failures + 1)) ;; esac
else
  echo "ok: skipped (not macOS)"
fi

if [ "$failures" -eq 0 ]; then echo "all passed"; else exit 1; fi
