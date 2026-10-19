#!/usr/bin/env bash
set -u
repo="$(cd "$(dirname "$0")/.." && pwd -P)"
installer="$repo/bin/claude-custom"
fish_bin="$(command -v fish 2>/dev/null || true)"
failures=0
sandboxes=""
remove_sandboxes() {
  local dir
  for dir in $sandboxes; do
    rm -rf "$dir"
  done
}
trap remove_sandboxes EXIT

fail() {
  echo "FAIL: $1"
  failures=$((failures + 1))
}

check_eq() {
  if [ "$2" != "$3" ]; then
    fail "$1: expected [$2] got [$3]"
  fi
}

check_that() {
  local name="$1"
  shift
  "$@" || fail "$name"
}

check_not() {
  local name="$1"
  shift
  if "$@"; then
    fail "$name"
  fi
}

new_sandbox() {
  sandbox="$(cd "$(mktemp -d)" && pwd -P)"
  sandboxes="$sandboxes $sandbox"
  export HOME="$sandbox/home"
  mkdir -p "$HOME" "$sandbox/stubbin"
  unset ZDOTDIR XDG_CONFIG_HOME CLAUDE_CONFIG_DIR STUB_OLLAMA_SHOW_EXIT STUB_OLLAMA_PULL_EXIT
  export SHELL=/bin/zsh
  printf '#!/bin/sh\necho "ARGS: $*"\n' > "$sandbox/stubbin/claude"
  cat > "$sandbox/stubbin/ollama" <<EOF
#!/bin/sh
echo "\$*" >> "$sandbox/ollama.log"
if [ "\$1" = show ]; then exit "\${STUB_OLLAMA_SHOW_EXIT:-0}"; fi
if [ "\$1" = pull ]; then exit "\${STUB_OLLAMA_PULL_EXIT:-0}"; fi
exit 0
EOF
  chmod +x "$sandbox/stubbin/claude" "$sandbox/stubbin/ollama"
  export PATH="$sandbox/stubbin:/usr/bin:/bin"
}

run_capture() {
  "$@" >"$sandbox/out" 2>"$sandbox/err"
}

copy_repo() {
  mkdir -p "$1"
  cp -R "$repo/bin" "$repo/personal" "$repo/shared" "$repo/ollama" "$repo/model-picker-tui" "$1/"
}

make_all_rc_files() {
  printf 'export ZSH=1\n' > "$HOME/.zshrc"
  printf 'export BASH=1\n' > "$HOME/.bashrc"
  printf 'export BASHP=1\n' > "$HOME/.bash_profile"
  printf 'export KSH=1\n' > "$HOME/.kshrc"
  mkdir -p "$HOME/.config/fish"
}

block_count() {
  grep -c '^# >>> claude-custom >>>$' "$1" 2>/dev/null
}

hash_home() {
  (cd "$HOME" && find . -type f | sort | xargs shasum)
}

want_args="ARGS: --settings $repo/personal/settings.tokens.json a b c"

new_sandbox
for shell_name in bash zsh ksh dash; do
  if ! command -v "$shell_name" >/dev/null 2>&1; then
    echo "skip: $shell_name not installed"
    continue
  fi
  check_eq "$shell_name function" "$want_args" \
    "$(CLAUDE_CUSTOM_HOME="$repo" "$shell_name" -c ". \"$repo/personal/claude.sh\"; claude a 'b c'" 2>&1)"
  check_eq "$shell_name function with alias" "$want_args" \
    "$(CLAUDE_CUSTOM_HOME="$repo" "$shell_name" -c "alias claude='echo ALIAS'; . \"$repo/personal/claude.sh\"; claude a 'b c'" 2>&1)"
done
if [ -n "$fish_bin" ]; then
  check_eq "fish function" "$want_args" \
    "$("$fish_bin" --no-config -c "set -g CLAUDE_CUSTOM_HOME $repo; source $repo/personal/claude.fish; claude a 'b c'" 2>&1)"
else
  echo "skip: fish not installed"
fi

new_sandbox
run_capture "$installer" install
check_eq "fresh home: zshrc block count" 1 "$(block_count "$HOME/.zshrc")"
check_not "fresh home: no bashrc" test -e "$HOME/.bashrc"
check_not "fresh home: no kshrc" test -e "$HOME/.kshrc"
check_not "fresh home: no fish drop-in" test -e "$HOME/.config/fish/conf.d/claude-custom.fish"
check_not "fresh home: no grep noise on stderr" grep -q 'No such file' "$sandbox/err"

new_sandbox
make_all_rc_files
run_capture "$installer" install
check_eq "existing zshrc block count" 1 "$(block_count "$HOME/.zshrc")"
check_eq "existing bashrc block count" 1 "$(block_count "$HOME/.bashrc")"
check_eq "existing bash_profile block count" 1 "$(block_count "$HOME/.bash_profile")"
check_eq "existing kshrc block count" 1 "$(block_count "$HOME/.kshrc")"
check_that "existing fish conf.d drop-in" test -f "$HOME/.config/fish/conf.d/claude-custom.fish"

new_sandbox
make_all_rc_files
run_capture "$installer" install
first_hashes="$(hash_home)"
run_capture "$installer" install
check_eq "install is idempotent" "$first_hashes" "$(hash_home)"

new_sandbox
printf 'export FOO=1' > "$HOME/.zshrc"
run_capture "$installer" install
check_eq "no trailing newline keeps first line" "export FOO=1" "$(sed -n 1p "$HOME/.zshrc")"

new_sandbox
mkdir -p "$sandbox/dotfiles"
printf 'export FOO=1\n' > "$sandbox/dotfiles/zshrc"
ln -s "$sandbox/dotfiles/zshrc" "$HOME/.zshrc"
run_capture "$installer" install
check_that "symlinked zshrc stays a symlink" test -L "$HOME/.zshrc"
check_eq "symlinked zshrc target has block" 1 "$(block_count "$sandbox/dotfiles/zshrc")"

new_sandbox
printf '' > "$HOME/.bashrc"
mkdir -p "$HOME/.config/fish"
run_capture "$installer" install
check_eq "zsh end to end" "ARGS: --settings $repo/personal/settings.tokens.json x" \
  "$(zsh -f -c ". \"$HOME/.zshrc\"; claude x" 2>&1)"
check_eq "bash end to end" "ARGS: --settings $repo/personal/settings.tokens.json x" \
  "$(bash -c ". \"$HOME/.bashrc\"; claude x" 2>&1)"
if [ -n "$fish_bin" ]; then
  check_eq "fish end to end" "ARGS: --settings $repo/personal/settings.tokens.json x" \
    "$("$fish_bin" --no-config -c "source \"$HOME/.config/fish/conf.d/claude-custom.fish\"; claude x" 2>&1)"
fi

new_sandbox
run_capture "$installer" install
path_once="$(zsh -f -c "PATH=/usr/bin:/bin; . \"$HOME/.zshrc\"; echo \$PATH")"
case "$path_once" in
  "$HOME/.local/bin:"*) ;;
  *) fail "zshrc puts ~/.local/bin first on PATH: $path_once" ;;
esac
path_twice="$(zsh -f -c "PATH=/usr/bin:/bin; . \"$HOME/.zshrc\"; . \"$HOME/.zshrc\"; echo \$PATH")"
check_eq "sourcing zshrc twice does not duplicate PATH entry" 1 \
  "$(printf '%s\n' "$path_twice" | tr ':' '\n' | grep -cxF "$HOME/.local/bin")"

new_sandbox
printf '# >>> claude-custom >>>\n' > "$HOME/.zshrc"
run_capture "$installer" install
check_eq "unmatched marker exit status" 1 "$?"
check_eq "unmatched marker leaves file unchanged" "# >>> claude-custom >>>" "$(cat "$HOME/.zshrc")"
check_that "unmatched marker message" grep -q 'skip: unmatched claude-custom marker' "$sandbox/err"

new_sandbox
copy_repo "$sandbox/it's"
run_capture "$sandbox/it's/bin/claude-custom" install
check_eq "quote in repo path exit status" 2 "$?"
check_not "quote in repo path writes no zshrc" test -e "$HOME/.zshrc"
check_that "quote in repo path message" grep -q "claude-custom path must not contain a single quote" "$sandbox/err"

new_sandbox
run_capture "$installer" install
check_that "claude-ollama link" test "$(readlink "$HOME/.local/bin/claude-ollama")" = "$repo/bin/claude-ollama"
check_eq "claude-custom link" "$repo/bin/claude-custom" "$(readlink "$HOME/.local/bin/claude-custom")"
check_eq "claude-tools link" "$repo/bin/claude-tools" "$(readlink "$HOME/.local/bin/claude-tools")"
check_eq "hook link" "$repo/shared/hooks/bash-output-guard.py" "$(readlink "$HOME/.claude/hooks/bash-output-guard.py")"
check_eq "bash-output-trim hook link" "$repo/shared/hooks/bash-output-trim.py" "$(readlink "$HOME/.claude/hooks/bash-output-trim.py")"
check_eq "read-range-guard hook link" "$repo/shared/hooks/read-range-guard.py" "$(readlink "$HOME/.claude/hooks/read-range-guard.py")"
check_eq "edit-check hook link" "$repo/shared/hooks/edit-check.py" "$(readlink "$HOME/.claude/hooks/edit-check.py")"
check_eq "stop-verify hook link" "$repo/shared/hooks/stop-verify.py" "$(readlink "$HOME/.claude/hooks/stop-verify.py")"

new_sandbox
mkdir -p "$HOME/.local/bin"
printf 'mine\n' > "$HOME/.local/bin/claude-ollama"
run_capture "$installer" install
check_eq "regular file at link path is kept" "mine" "$(cat "$HOME/.local/bin/claude-ollama")"
check_that "regular file at link path is reported" grep -q '^skip: ' "$sandbox/err"
check_eq "regular file at link path exits 1" 1 "$(run_capture "$installer" install; echo $?)"

new_sandbox
mkdir -p "$HOME/.local/bin"
ln -s "$repo/old/path" "$HOME/.local/bin/claude-ollama"
run_capture "$installer" install
check_eq "symlink inside repo is replaced" "$repo/bin/claude-ollama" "$(readlink "$HOME/.local/bin/claude-ollama")"

new_sandbox
run_capture "$installer" install
check_not "claude is never created in local bin" test -e "$HOME/.local/bin/claude"
check_not "claude is never created as a link" test -L "$HOME/.local/bin/claude"

new_sandbox
run_capture "$installer" install
run_capture "$HOME/.local/bin/claude-custom" install
check_eq "install through the linked command" 0 "$?"

new_sandbox
run_capture "$installer" install
run_capture "$installer" install
check_eq "import line appears once after two installs" 1 \
  "$(grep -cxF "@$repo/personal/CLAUDE.tokens.md" "$HOME/.claude/CLAUDE.md")"
check_eq "preferences import appears once after two installs" 1 \
  "$(grep -cxF "@$repo/shared/preferences/PREFERENCES.md" "$HOME/.claude/CLAUDE.md")"

for settings in "$repo"/ollama/settings.*.json; do
  check_eq "hooks in ${settings##*/} match the personal overlay" \
    "$(jq -S .hooks "$repo/personal/settings.tokens.json")" "$(jq -S .hooks "$settings")"
done

for settings in "$repo"/ollama/settings.*.json; do
  check_eq "deny list in ${settings##*/} matches settings.27b.json" \
    "$(jq -S .permissions.deny "$repo/ollama/settings.27b.json")" "$(jq -S .permissions.deny "$settings")"
  check_that "${settings##*/} denies Workflow" \
    test "$(jq -r '.permissions.deny | index("Workflow") != null' "$settings")" = true
  check_that "${settings##*/} allows Agent" \
    test "$(jq -r '.permissions.deny | index("Agent") == null' "$settings")" = true
  check_eq "${settings##*/} sends Haiku to the side model" \
    "$(jq -r .env.ANTHROPIC_DEFAULT_HAIKU_MODEL "$repo/ollama/settings.27b.json")" \
    "$(jq -r .env.ANTHROPIC_DEFAULT_HAIKU_MODEL "$settings")"
done

check_eq "side model context matches the main models" \
  "$(grep num_ctx "$repo/ollama/Modelfile.27b")" "$(grep num_ctx "$repo/ollama/side.Modelfile")"

for settings in "$repo/personal/settings.tokens.json" "$repo"/ollama/settings.*.json; do
  check_eq "${settings##*/} sets subagents to Haiku" haiku "$(jq -r .env.CLAUDE_CODE_SUBAGENT_MODEL "$settings")"
  check_eq "${settings##*/} forces the subagent model" 1 "$(jq -r .env.CLAUDE_CODE_SUBAGENT_MODEL_FORCE "$settings")"
  check_eq "${settings##*/} keeps the personal Read globs" \
    "$(jq -S '[.permissions.deny[] | select(startswith("Read("))]' "$repo/personal/settings.tokens.json")" \
    "$(jq -S '[.permissions.deny[] | select(startswith("Read("))]' "$settings")"
done

new_sandbox
copy_repo "$HOME/src/.claude-custom"
mkdir -p "$HOME/.claude"
printf '@~/src/.claude-custom/personal/CLAUDE.tokens.md\n' > "$HOME/.claude/CLAUDE.md"
run_capture "$HOME/src/.claude-custom/bin/claude-custom" install
check_eq "tilde import line is not duplicated" 0 \
  "$(grep -cxF "@$HOME/src/.claude-custom/personal/CLAUDE.tokens.md" "$HOME/.claude/CLAUDE.md")"
check_eq "tilde import line is the only import" 1 \
  "$(grep -c 'CLAUDE.tokens.md' "$HOME/.claude/CLAUDE.md")"

new_sandbox
run_capture env CLAUDE_CONFIG_DIR="$sandbox/cfg" "$installer" install
check_eq "CLAUDE_CONFIG_DIR receives import line" 1 \
  "$(grep -cxF "@$repo/personal/CLAUDE.tokens.md" "$sandbox/cfg/CLAUDE.md")"
check_not "default CLAUDE.md not created under CLAUDE_CONFIG_DIR" test -e "$HOME/.claude/CLAUDE.md"

new_sandbox
mkdir -p "$HOME/.config/fish/functions"
ln -s "$repo/personal/claude.fish" "$HOME/.config/fish/functions/claude.fish"
run_capture "$installer" install
check_not "plan 001 fish function link removed" test -L "$HOME/.config/fish/functions/claude.fish"

new_sandbox
mkdir -p "$HOME/.config/fish/functions"
ln -s "$sandbox/elsewhere.fish" "$HOME/.config/fish/functions/claude.fish"
run_capture "$installer" install
check_that "fish function link pointing elsewhere is kept" test -L "$HOME/.config/fish/functions/claude.fish"

new_sandbox
run_capture "$installer" install
check_that "ollama show is run for 27b base" grep -qxF "show qwen3.8:27b-mlx" "$sandbox/ollama.log"
check_that "ollama create 27b model" grep -qxF "create qwen3.8-27b-cc -f $repo/ollama/Modelfile.27b" "$sandbox/ollama.log"
check_not "no 9b model is created" grep -qF "qwen3.8-9b-cc" "$sandbox/ollama.log"
check_that "ollama show is run for 35b base" grep -qxF "show qwen3.6:35b-mlx" "$sandbox/ollama.log"
check_that "ollama create 35b model" grep -qxF "create qwen3.6-35b-cc -f $repo/ollama/Modelfile.35b" "$sandbox/ollama.log"

new_sandbox
STUB_OLLAMA_SHOW_EXIT=1 run_capture "$installer" install
check_eq "missing base model exit status" 0 "$?"
check_not "missing base model skips create" grep -q '^create ' "$sandbox/ollama.log"
check_that "missing base model message" grep -qF "ollama pull qwen3.8:27b-mlx" "$sandbox/err"

new_sandbox
rm "$sandbox/stubbin/ollama"
run_capture "$installer" install
check_eq "no ollama on PATH exit status" 0 "$?"
check_not "no ollama on PATH prints nothing about ollama" grep -q 'ollama' "$sandbox/err"

new_sandbox
run_capture "$installer" install
path_message="$(printf '%s/.local/bin was not on PATH' '~')"
check_that "PATH message when local bin is missing from PATH" grep -qF "$path_message" "$sandbox/out"
run_capture env PATH="$HOME/.local/bin:$PATH" "$installer" install
check_not "no PATH message when local bin is on PATH" grep -qF "$path_message" "$sandbox/out"

new_sandbox
printf 'export FOO=1\n' > "$HOME/.zshrc"
printf 'export BAR=2\n' > "$HOME/.bashrc"
mkdir -p "$HOME/.config/fish"
cp "$HOME/.zshrc" "$sandbox/zshrc.orig"
cp "$HOME/.bashrc" "$sandbox/bashrc.orig"
run_capture "$installer" install
run_capture "$installer" uninstall
check_that "round trip zshrc is identical" cmp -s "$HOME/.zshrc" "$sandbox/zshrc.orig"
check_that "round trip bashrc is identical" cmp -s "$HOME/.bashrc" "$sandbox/bashrc.orig"
check_not "round trip removes fish drop-in" test -e "$HOME/.config/fish/conf.d/claude-custom.fish"
check_not "round trip removes ollama link" test -L "$HOME/.local/bin/claude-ollama"
check_not "round trip removes claude-custom link" test -L "$HOME/.local/bin/claude-custom"
check_not "round trip removes claude-tools link" test -L "$HOME/.local/bin/claude-tools"
check_not "round trip removes hook link" test -L "$HOME/.claude/hooks/bash-output-guard.py"
check_not "round trip removes bash-output-trim link" test -L "$HOME/.claude/hooks/bash-output-trim.py"
check_not "round trip removes read-range-guard link" test -L "$HOME/.claude/hooks/read-range-guard.py"
check_not "round trip removes edit-check link" test -L "$HOME/.claude/hooks/edit-check.py"
check_not "round trip removes stop-verify link" test -L "$HOME/.claude/hooks/stop-verify.py"

new_sandbox
mkdir -p "$HOME/.local/bin" "$HOME/.claude/hooks"
ln -s "$sandbox/elsewhere" "$HOME/.local/bin/claude-ollama"
printf 'mine\n' > "$HOME/.local/bin/claude-custom"
printf 'old build\n' > "$HOME/.local/bin/claude-tools"
ln -s "$sandbox/elsewhere-hook" "$HOME/.claude/hooks/bash-output-guard.py"
run_capture "$installer" install
run_capture "$installer" uninstall
check_eq "foreign link survives uninstall" "$sandbox/elsewhere" "$(readlink "$HOME/.local/bin/claude-ollama")"
check_eq "regular file survives uninstall" "mine" "$(cat "$HOME/.local/bin/claude-custom")"
check_eq "old claude-tools binary survives install and uninstall" "old build" "$(cat "$HOME/.local/bin/claude-tools")"
check_eq "foreign hook link survives uninstall" "$sandbox/elsewhere-hook" \
  "$(readlink "$HOME/.claude/hooks/bash-output-guard.py")"

new_sandbox
copy_repo "$HOME/src/.claude-custom"
mkdir -p "$HOME/.claude"
printf 'keep me\n@~/src/.claude-custom/personal/CLAUDE.tokens.md\n@%s/personal/CLAUDE.tokens.md\n@~/src/.claude-custom/shared/preferences/PREFERENCES.md\nkeep too\n' "$HOME/src/.claude-custom" > "$HOME/.claude/CLAUDE.md"
run_capture "$HOME/src/.claude-custom/bin/claude-custom" uninstall
check_eq "uninstall removes import lines and keeps others" "keep me
keep too" "$(cat "$HOME/.claude/CLAUDE.md")"

new_sandbox
before="$(find "$HOME" | sort)"
run_capture "$installer" uninstall
check_eq "uninstall on untouched home exit status" 0 "$?"
check_eq "uninstall on untouched home creates nothing" "$before" "$(find "$HOME" | sort)"

new_sandbox
run_capture "$installer" install
rm -f "$sandbox/ollama.log"
run_capture "$installer" uninstall
check_not "uninstall never calls ollama" test -s "$sandbox/ollama.log"
check_that "uninstall closing message" grep -qF "open a new terminal; current shells keep the claude function until they exit" "$sandbox/out"

new_sandbox
copy_repo "$sandbox/origin"
git -C "$sandbox/origin" init -q
git -C "$sandbox/origin" add -A
git -C "$sandbox/origin" -c user.name=t -c user.email=t@t commit -qm initial
git clone -q "$sandbox/origin" "$sandbox/clone"
printf 'true\n' >> "$sandbox/origin/personal/claude.sh"
git -C "$sandbox/origin" -c user.name=t -c user.email=t@t commit -qam 'add true'
run_capture "$sandbox/clone/bin/claude-custom" update
check_eq "update exit status" 0 "$?"
check_eq "update pulled the new commit" "true" "$(tail -n 1 "$sandbox/clone/personal/claude.sh")"
check_that "update rewrote zshrc block for the clone" grep -qxF "CLAUDE_CUSTOM_HOME='$sandbox/clone'" "$HOME/.zshrc"

new_sandbox
copy_repo "$sandbox/origin"
git -C "$sandbox/origin" init -q
git -C "$sandbox/origin" add -A
git -C "$sandbox/origin" -c user.name=t -c user.email=t@t commit -qm initial
git clone -q "$sandbox/origin" "$sandbox/clone"
printf 'local change\n' >> "$sandbox/clone/personal/claude.sh"
printf 'true\n' >> "$sandbox/origin/personal/claude.sh"
git -C "$sandbox/origin" -c user.name=t -c user.email=t@t commit -qam 'add true'
run_capture "$sandbox/clone/bin/claude-custom" update
check_eq "conflicting update exit status" 1 "$?"
check_that "conflicting update message" grep -q 'update: git pull failed' "$sandbox/err"
check_not "conflicting update writes no zshrc" test -e "$HOME/.zshrc"

new_sandbox
copy_repo "$sandbox/solo"
git -C "$sandbox/solo" init -q
git -C "$sandbox/solo" add -A
git -C "$sandbox/solo" -c user.name=t -c user.email=t@t commit -qm initial
run_capture "$sandbox/solo/bin/claude-custom" update
check_eq "no upstream exit status" 1 "$?"
check_that "no upstream message" grep -q 'update: git pull failed' "$sandbox/err"

new_sandbox
ollama_settings="--settings $repo/ollama/settings.27b.json"
run_capture "$repo/bin/claude-ollama" -p hi
denies_tool() {
  jq -e --arg tool "$2" '.permissions.deny | index($tool) != null' "$1" >/dev/null
}
for settings in "$repo"/ollama/settings.*.json; do
  for tool in Grep Glob; do
    check_that "${settings##*/} denies $tool" denies_tool "$settings" "$tool"
  done
done
check_that "claude-ollama defaults to 27b" grep -qF -- "$ollama_settings" "$sandbox/out"
check_that "claude-ollama passes claude args through" grep -qF -- "--tools Bash,Read,Edit,Write,Agent -p hi" "$sandbox/out"
run_capture "$repo/bin/claude-ollama" 27b -p hi
check_that "claude-ollama keeps the explicit size form" grep -qF -- "--tools Bash,Read,Edit,Write,Agent -p hi" "$sandbox/out"
run_capture "$repo/bin/claude-ollama" 35b -p hi
check_that "claude-ollama 35b uses the 35b settings" grep -qF -- "--settings $repo/ollama/settings.35b.json" "$sandbox/out"
check_that "claude-ollama 35b uses the 35b prompt" grep -qF -- "--append-system-prompt-file $repo/ollama/CLAUDE.35b.md" "$sandbox/out"
check_that "claude-ollama replaces the default system prompt" grep -qF -- "--system-prompt-file $repo/ollama/system-prompt.md --append-system-prompt-file $repo/ollama/CLAUDE.35b.md" "$sandbox/out"
check_that "claude-ollama 35b passes claude args through" grep -qF -- "--tools Bash,Read,Edit,Write,Agent -p hi" "$sandbox/out"
check_not "claude-ollama 35b skips pull when the model exists" grep -sqE '^(pull|create) ' "$sandbox/ollama.log"
check_not "claude-ollama does not warn when the side model exists" grep -q 'side model' "$sandbox/err"
check_that "claude-ollama starts the code-search MCP server" grep -qF -- "--strict-mcp-config --mcp-config {\"mcpServers\":{\"code-search\":{\"command\":\"python3\",\"args\":[\"$repo/shared/mcp/code-search.py\"]}}}" "$sandbox/out"
STUB_OLLAMA_SHOW_EXIT=1 run_capture "$repo/bin/claude-ollama" 35b -p hi
check_that "claude-ollama 35b pulls a missing base model" grep -qxF "pull qwen3.6:35b-mlx" "$sandbox/ollama.log"
check_that "claude-ollama 35b creates the missing model" grep -qxF "create qwen3.6-35b-cc -f $repo/ollama/Modelfile.35b" "$sandbox/ollama.log"
check_that "claude-ollama 35b launches after pulling" grep -qF -- "--settings $repo/ollama/settings.35b.json" "$sandbox/out"
check_that "claude-ollama warns about a missing side model" grep -qF "side model qwen3-4b-cc missing" "$sandbox/err"
check_not "claude-ollama does not pull the side model itself" grep -qxF "pull qwen3:4b" "$sandbox/ollama.log"
check_that "claude-ollama pulls a missing embedding model" grep -qxF "pull qwen3-embedding:0.6b" "$sandbox/ollama.log"
rm -f "$sandbox/ollama.log"
STUB_OLLAMA_SHOW_EXIT=1 STUB_OLLAMA_PULL_EXIT=1 run_capture "$repo/bin/claude-ollama" 35b -p hi
check_eq "claude-ollama 35b failed pull exit status" 1 "$?"
check_not "claude-ollama 35b failed pull does not create" grep -sq '^create ' "$sandbox/ollama.log"
check_not "claude-ollama 35b failed pull does not launch claude" grep -q '^ARGS:' "$sandbox/out"
rm -f "$sandbox/ollama.log"
run_capture "$repo/bin/claude-ollama" 27b -p hi
check_not "claude-ollama 27b skips pull when the model exists" grep -sqE '^(pull|create) ' "$sandbox/ollama.log"
STUB_OLLAMA_SHOW_EXIT=1 run_capture "$repo/bin/claude-ollama" 27b -p hi
check_that "claude-ollama 27b pulls a missing base model" grep -qxF "pull qwen3.8:27b-mlx" "$sandbox/ollama.log"
check_that "claude-ollama 27b creates the missing model" grep -qxF "create qwen3.8-27b-cc -f $repo/ollama/Modelfile.27b" "$sandbox/ollama.log"
check_that "claude-ollama 27b launches after pulling" grep -qF -- "--settings $repo/ollama/settings.27b.json" "$sandbox/out"
rm -f "$sandbox/ollama.log"
STUB_OLLAMA_SHOW_EXIT=1 STUB_OLLAMA_PULL_EXIT=1 run_capture "$repo/bin/claude-ollama" 27b -p hi
check_eq "claude-ollama 27b failed pull exit status" 1 "$?"
check_not "claude-ollama 27b failed pull does not create" grep -sq '^create ' "$sandbox/ollama.log"
check_not "claude-ollama 27b failed pull does not launch claude" grep -q '^ARGS:' "$sandbox/out"
run_capture "$repo/bin/claude-ollama" --help
check_eq "claude-ollama help exit status" 0 "$?"
check_that "claude-ollama help lists sizes" grep -qxF "sizes: 27b 35b" "$sandbox/out"
check_not "claude-ollama help does not launch claude" grep -q '^ARGS:' "$sandbox/out"
run_capture "$repo/bin/claude-ollama" 28b -p hi </dev/null
check_that "claude-ollama unknown size without a tty falls back to 27b" grep -qF -- "$ollama_settings" "$sandbox/out"
check_not "claude-ollama drops an unknown size" grep -qF "28b" "$sandbox/out"
check_that "claude-ollama unknown size keeps claude args" grep -qF -- "Agent -p hi" "$sandbox/out"

new_sandbox
copy_repo "$sandbox/repo"
cp "$sandbox/repo/ollama/settings.27b.json" "$sandbox/repo/ollama/settings.9b.json"
cp "$sandbox/repo/ollama/Modelfile.27b" "$sandbox/repo/ollama/Modelfile.9b"
cp "$sandbox/repo/ollama/settings.27b.json" "$sandbox/repo/ollama/settings.70b.json"
run_capture "$sandbox/repo/bin/claude-ollama" 9b -p hi
check_that "claude-ollama accepts a newly configured size" grep -qF -- "--settings $sandbox/repo/ollama/settings.9b.json" "$sandbox/out"
check_not "claude-ollama does not pass a configured size to claude" grep -qF -- "Write 9b" "$sandbox/out"
run_capture "$sandbox/repo/bin/claude-ollama" --help
check_that "claude-ollama help lists sizes from config" grep -qxF "sizes: 27b 35b 9b" "$sandbox/out"

cat > "$sandbox/stubbin/go" <<'STUB'
#!/bin/sh
printf '#!/bin/sh\necho 35b\n' > "$3"
chmod +x "$3"
STUB
chmod +x "$sandbox/stubbin/go"
script -q /dev/null "$sandbox/repo/bin/claude-ollama" -p hi >"$sandbox/out" 2>&1 </dev/null
check_that "claude-ollama with a tty and no size launches the picked size" grep -qF -- "--settings $sandbox/repo/ollama/settings.35b.json" "$sandbox/out"
script -q /dev/null "$sandbox/repo/bin/claude-ollama" 28b >"$sandbox/out" 2>&1 </dev/null
check_that "claude-ollama with a tty and an unknown size launches the picked size" grep -qF -- "--settings $sandbox/repo/ollama/settings.35b.json" "$sandbox/out"
cat > "$sandbox/stubbin/go" <<'STUB'
#!/bin/sh
printf '#!/bin/sh\nexit 1\n' > "$3"
chmod +x "$3"
STUB
script -q /dev/null "$sandbox/repo/bin/claude-ollama" >"$sandbox/out" 2>&1 </dev/null
check_not "claude-ollama cancelled picker does not launch claude" grep -q 'ARGS:' "$sandbox/out"
run_capture "$installer" ollama -p hi
check_that "claude-custom ollama runs claude-ollama" grep -qF -- "$ollama_settings" "$sandbox/out"

new_sandbox
run_capture "$repo/bin/claude-tools" local
check_eq "claude-tools without go exit status" 1 "$?"
check_that "claude-tools without go message" grep -qF "claude-tools: needs Go 1.26+" "$sandbox/err"
run_capture "$installer" tools
check_that "claude-custom tools runs claude-tools" grep -qF "claude-tools: needs Go 1.26+" "$sandbox/err"
run_capture "$installer" bogus
check_eq "unknown subcommand exit status" 2 "$?"
check_that "usage lists the new subcommands" grep -qF "install|update|uninstall|ollama|tools" "$sandbox/err"

if [ "$failures" -eq 0 ]; then
  echo "all passed"
else
  echo "$failures failed"
  exit 1
fi
