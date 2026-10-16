# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with
code in this repository.

## What this repo is

Configuration overlays for Claude Code itself, plus one small Go app. There are
three parts:

- **Personal setup** (`personal/`, `project/`, `shared/`): merged into
  `~/.claude/settings.json` and `~/.claude/CLAUDE.md` to cut token usage on the
  normal Anthropic-backed `claude`.
- **Work harness** (`bin/claude-ollama`, `ollama/`): starts `claude` against a
  local Ollama server (`localhost:11434`) running Qwen 27b. The overlay only
  applies to that launch.
- **Tools TUI** (`tools-tui/`): a Go/Bubble Tea app that edits the
  bare-tool-name permission rules in a Claude Code settings file.

Every file is additive. Nothing here replaces a base config. The layer order and
install/revert steps are in `README.md`. Read it before changing how any file
gets applied.

## Commands

- Hook tests: `shared/hooks/bash-output-guard.test.sh` (prints `all passed`, or
  `FAIL:` lines and exits 1)
- Installer tests: `personal/install.test.sh` (prints `all passed`)
- Feed the hook one command by hand:
  `printf '{"tool_input":{"command":"git log"}}' | shared/hooks/bash-output-guard.py`
- Validate JSON after editing: `jq . ollama/settings.27b.json >/dev/null`
- Launch the work harness: `claude-ollama [27b] [claude args...]` (27b is the
  default size; `--help` lists sizes)
- Launch the tools TUI: `claude-tools [user|project|local|FILE]`. Both are also
  `claude-custom ollama|tools [...]`.
- `bin/claude-custom`, `bin/claude-ollama` and `bin/claude-tools` must stay
  bash-3.2 compatible (macOS `/bin/bash`). `bin/claude-custom` must never write
  `~/.zshenv` or `~/.local/bin/claude`, and derives Ollama model names from
  `ollama/settings.<size>.json` and `ollama/Modelfile.<size>`. Adding a size
  means adding both files; the installer picks it up.
- Tools TUI (Go, `tools-tui/`): `cd tools-tui && go test ./...` (one test:
  `go test ./ui -run TestSwitching`), run with `go run .`. See
  `tools-tui/README.md`.

There is no build step outside `tools-tui/`. `pnpm install` enables git hooks
(husky): lint-staged runs Prettier on staged `.md`/`.json`, and commitlint
enforces conventional commits (`feat:`, `fix:`, `chore:`). The
ESLint/TypeScript/React config is unused boilerplate from `git-precommit-setup`;
there is no `src/`.

## How the pieces connect

- `shared/hooks/bash-output-guard.py` is a `PreToolUse` hook on Bash. It denies
  commands that would flood the context (unbounded `git log`, `cat` on a
  lockfile, recursive `ls`). Each rule is one `(regex, reason)` entry in
  `UNBOUNDED_COMMANDS`. Every regex starts with `COMMAND_START`, so it only
  matches at the start of a command segment and ignores text inside arguments. A
  new rule needs both `expect deny` and `expect allow` cases in the test script.
- Both settings files (`personal/settings.tokens.json`,
  `ollama/settings.27b.json`) point to the hook at
  `~/.claude/hooks/bash-output-guard.py`, not at a path in this repo. They rely
  on the symlink that `bin/claude-custom install` creates, and the Ollama
  harness needs it too.
- The Read `permissions.deny` globs and the hook entry are copied into both
  settings files. Change both together.
- `bin/claude-ollama` resolves its own symlink to find `ollama/`. It unsets
  `ANTHROPIC_API_KEY`, passes `--settings ollama/settings.<size>.json`,
  `--append-system-prompt-file ollama/CLAUDE.<size>.md`, and
  `--strict-mcp-config`, and restricts tools with `--tools`.
- `ollama/CLAUDE.<size>.md` files are appended system prompts for small local
  models, not memory files. Keep them terse: the 27b has a 64k context. Context
  sizes must match across `Modelfile.<size>` (`num_ctx`),
  `CLAUDE_CODE_MAX_CONTEXT_TOKENS`, and the `ollama create` names that `model`
  and the `ANTHROPIC_DEFAULT_*_MODEL` vars refer to.
- The personal overlay is loaded with `--settings` by the `claude` shell
  function (`personal/claude.sh` for bash/zsh/ksh, `personal/claude.fish` for
  fish), wired into rc files by `bin/claude-custom install`, never merged into
  `~/.claude/settings.json`. `--settings` holds one file: a second `--settings`
  replaces the first, so `bin/claude-ollama` launches don't get the personal
  overlay (the Ollama profiles carry their own deny globs and hook). Top-level
  scalars in the overlay override the user file, so don't add keys to the
  overlay that `~/.claude/settings.json` already sets.
- `personal/CLAUDE.tokens.md` reaches every personal session through an `@`
  import that `bin/claude-custom install` adds to `~/.claude/CLAUDE.md`. Keep it
  short: it loads on every turn.
- `tools-tui/` has three packages:
  - `catalog`: fetches the tool table from the Claude Code docs and caches it in
    the user cache dir.
  - `settings`: maps rules to and from `ToolState`, using gjson/sjson so other
    keys survive. Saves are atomic and keep a `.bak`. Also lists the user,
    project and local files.
  - `ui`: the Bubble Tea model. It's "dirty" when `states` differs from `saved`.

  The TUI only touches rules that are a bare tool name. Scoped rules like
  `Bash(git log *)` are never changed. "Disable" means a bare deny rule. Write
  rules are in `tools-tui/README.md`.
