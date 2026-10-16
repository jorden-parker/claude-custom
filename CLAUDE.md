# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with
code in this repository.

## What this repo is

Configuration overlays for Claude Code itself, not an application. There are two
consumers:

- **Personal setup** (`personal/`, `project/`, `shared/`): merged into
  `~/.claude/settings.json` and `~/.claude/CLAUDE.md` to cut token usage on the
  normal Anthropic-backed `claude`.
- **Work harness** (`bin/claude-ollama`, `ollama/`): starts `claude` against a
  local Ollama server (`localhost:11434`) running Qwen 27b or 9b. The overlay
  only applies to that launch.

Every file is additive. Nothing here replaces a base config. The layer order and
install/revert steps are in `README.md`. Read it before changing how any file
gets applied.

## Commands

- Hook tests: `shared/hooks/bash-output-guard.test.sh` (prints `all passed`, or
  `FAIL:` lines and exits 1)
- Feed the hook one command by hand:
  `printf '{"tool_input":{"command":"git log"}}' | shared/hooks/bash-output-guard.py`
- Validate JSON after editing: `jq . ollama/settings.27b.json >/dev/null`
- Launch the work harness: `claude-ollama 27b|9b [claude args...]`

There is no build step and no linter.

## How the pieces connect

- `shared/hooks/bash-output-guard.py` is a `PreToolUse` hook on Bash. It denies
  commands that would flood the context (unbounded `git log`, `cat` on a
  lockfile, recursive `ls`). Each rule is one `(regex, reason)` entry in
  `UNBOUNDED_COMMANDS`. Every regex starts with `COMMAND_START`, so it only
  matches at the start of a command segment and ignores text inside arguments. A
  new rule needs both `expect deny` and `expect allow` cases in the test script.
- All three settings files (`personal/settings.tokens.json`,
  `ollama/settings.27b.json`, `ollama/settings.9b.json`) point to the hook at
  `~/.claude/hooks/bash-output-guard.py`, not at a path in this repo. They rely
  on the symlink from the README install step, and the Ollama harness needs it
  too.
- The Read `permissions.deny` globs and the hook entry are copied into all three
  settings files. Change all three together.
- `bin/claude-ollama` resolves its own symlink to find `ollama/`. It unsets
  `ANTHROPIC_API_KEY`, passes `--settings ollama/settings.<size>.json`,
  `--append-system-prompt-file ollama/CLAUDE.<size>.md`, and
  `--strict-mcp-config`, and restricts tools with `--tools`. The 9b launch also
  adds `--disable-slash-commands`.
- `ollama/CLAUDE.<size>.md` files are appended system prompts for small local
  models, not memory files. Keep them terse: the 9b has a 32k context and the
  27b has 64k. Context sizes must match across `Modelfile.<size>` (`num_ctx`),
  `CLAUDE_CODE_MAX_CONTEXT_TOKENS`, and the `ollama create` names that `model`
  and the `ANTHROPIC_DEFAULT_*_MODEL` vars refer to.
- The 9b profile excludes the user's global `~/.claude/CLAUDE.md`
  (`claudeMdExcludes`) and turns off thinking two ways:
  `alwaysThinkingEnabled: false` and `CLAUDE_CODE_EXTRA_BODY`.
- The personal overlay is loaded with `--settings` by the fish function
  `personal/claude.fish`, never merged into `~/.claude/settings.json`.
  `--settings` holds one file: a second `--settings` replaces the first, so
  `bin/claude-ollama` launches don't get the personal overlay (the Ollama
  profiles carry their own deny globs and hook). Top-level scalars in the
  overlay override the user file, so don't add keys to the overlay that
  `~/.claude/settings.json` already sets.
