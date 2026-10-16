# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with
code in this repository.

## What this repo is

Configuration overlays for Claude Code itself, plus two small Go apps. There are
four parts:

- **Personal setup** (`personal/`, `project/`): loaded with `--settings` by the
  `claude` shell function and `@`-imported into `~/.claude/CLAUDE.md` to cut
  token usage on the normal Anthropic-backed `claude`.
- **Preference enforcement** (`shared/hooks/`, `shared/preferences/`): hooks and
  a short rules file that both the personal setup and the work harness load, so
  the same checks run whichever model is driving.
- **Work harness** (`bin/claude-ollama`, `ollama/`, `model-picker-tui/`): starts
  `claude` against a local Ollama server (`localhost:11434`) running Qwen 3.8
  27b or Qwen 3.6 35b. The overlay only applies to that launch.
  `model-picker-tui/` is a Go/Bubble Tea menu for choosing the size.
- **Tools TUI** (`tools-tui/`): a Go/Bubble Tea app that edits the
  bare-tool-name permission rules in a Claude Code settings file.

Every file is additive. Nothing here replaces a base config. The layer order and
install/revert steps are in `README.md`. Read it before changing how any file
gets applied.

## Commands

- Hook tests: `shared/hooks/*.test.sh` (each prints `all passed`, or `FAIL:`
  lines and exits 1)
- Everything at once: `.claude/verify` (the Stop hook runs it too)
- Installer tests: `personal/install.test.sh` (prints `all passed`)
- Feed the hook one command by hand:
  `printf '{"tool_input":{"command":"git log"}}' | shared/hooks/bash-output-guard.py`
- Validate JSON after editing: `jq . ollama/settings.*.json >/dev/null`
- Launch the work harness: `claude-ollama [27b|35b] [claude args...]` (27b is
  the default size; `--help` lists sizes)
- Launch the tools TUI: `claude-tools [user|project|local|FILE]`. Both are also
  `claude-custom ollama|tools [...]`.
- `bin/claude-custom`, `bin/claude-ollama` and `bin/claude-tools` must stay
  bash-3.2 compatible (macOS `/bin/bash`). `bin/claude-custom` must never write
  `~/.zshenv` or `~/.local/bin/claude`, and derives Ollama model names from
  `ollama/settings.<size>.json` and `ollama/Modelfile.<size>`. Adding a size
  means adding both files; the installer picks it up.
- Model picker (Go, `model-picker-tui/`):
  `cd model-picker-tui && go test ./...`; `claude-ollama` builds and runs it
  when no size is given on a terminal.
- Tools TUI (Go, `tools-tui/`): `cd tools-tui && go test ./...` (one test:
  `go test ./ui -run TestSwitching`), run with `go run .`. See
  `tools-tui/README.md`.

There is no build step outside the two Go apps. `claude-tools` builds
`tools-tui/` and `claude-ollama` builds `model-picker-tui/model-picker`
(gitignored) on launch. `pnpm install` enables git hooks (husky): pre-commit
checks staged files for conflict markers, files over 1 MB and secrets, then
lint-staged runs Prettier on staged `.md`/`.json` (plus ESLint on JS/TS).
commitlint enforces conventional commits (`feat:`, `fix:`, `chore:`). The
ESLint/TypeScript/React config is unused boilerplate from `git-precommit-setup`;
there is no `src/`.

## How the pieces connect

- `shared/hooks/bash-output-guard.py` is a `PreToolUse` hook on Bash. It denies
  commands that would flood the context (unbounded `git log`, `cat` on a
  lockfile, recursive `ls`). Each rule is one `(regex, reason)` entry in
  `UNBOUNDED_COMMANDS`. Every regex starts with `COMMAND_START`, so it only
  matches at the start of a command segment and ignores text inside arguments. A
  new rule needs both `expect deny` and `expect allow` cases in the test script.
- `shared/hooks/bash-output-trim.py` is a `PostToolUse` hook on Bash. It
  shortens long stdout/stderr through `updatedToolOutput`, keeping head, tail
  and error/fail lines plus a marker naming the hidden line range. The reply
  must keep the Bash output shape (`stdout`, `stderr`, `interrupted`, `isImage`)
  or Claude Code ignores it.
- `shared/hooks/edit-check.py` (PostToolUse on Edit/Write/MultiEdit) runs the
  edited file's project-local formatter/linter and rejects newly added comments.
  `shared/hooks/stop-verify.py` (Stop) runs Fallow in JS/TS projects and the
  project's `.claude/verify`; it blocks once per turn (`stop_hook_active`). Both
  exit 2 so the model sees stderr.
- `shared/preferences/PREFERENCES.md` holds the prose rules no tool can check.
  `bin/claude-custom install` `@`-imports it into `~/.claude/CLAUDE.md`, so both
  backends load it. Keep it short: Ollama has 64k context.
- All settings files (`personal/settings.tokens.json`, `ollama/settings.*.json`)
  point to the hooks at `~/.claude/hooks/<name>`, not at paths in this repo.
  They rely on the symlinks that `bin/claude-custom install` creates (names in
  `hook_names`).
- The Read `permissions.deny` globs and the `hooks` block are shared by all
  settings files. Change them together; `personal/install.test.sh` fails when
  the `hooks` blocks differ. `ollama/settings.*.json` also deny unused tools by
  bare name, so their schemas never reach the local model's context. `--tools`
  in `bin/claude-ollama` is the primary allowlist and that deny list is the
  backstop. `personal/install.test.sh` fails when the Ollama deny lists differ.
- `bin/claude-ollama` resolves its own symlink to find `ollama/`. It unsets
  `ANTHROPIC_API_KEY`, passes `--settings ollama/settings.<size>.json`,
  `--system-prompt-file ollama/system-prompt.md` (replacing Claude Code's
  default system prompt), `--append-system-prompt-file ollama/CLAUDE.<size>.md`,
  and `--strict-mcp-config`, and restricts tools with `--tools`. Before
  launching, it pulls the base model and creates the `-cc` model when
  `ollama show` can't find the `-cc` model.
- `bin/claude-ollama` reads the configured sizes from `ollama/` (a
  `settings.<size>.json` plus a `Modelfile.<size>`), never a hardcoded list. A
  first arg that matches launches that size. Otherwise, on a terminal it runs
  `model-picker-tui` (which renders on stderr and prints the chosen size on
  stdout); without one it uses 27b. A first arg that is neither a size nor a
  flag is dropped so it doesn't reach `claude` as a prompt.
- `ollama/server.env` documents the Ollama server env the profiles expect. The
  Homebrew service sets the same values. Nothing in this repo applies it.
- `ollama/CLAUDE.<size>.md` files are appended system prompts for small local
  models, not memory files. Keep them terse: both sizes have a 64k context.
  Context sizes must match across `Modelfile.<size>` (`num_ctx`),
  `CLAUDE_CODE_MAX_CONTEXT_TOKENS`, and the `ollama create` names that `model`
  and the `ANTHROPIC_DEFAULT_*_MODEL` vars refer to. `ollama/system-prompt.md`
  replaces Claude Code's default system prompt for both sizes; keep it short and
  don't put size-specific rules in it.
- The personal overlay is loaded with `--settings` by the `claude` shell
  function (`personal/claude.sh` for bash/zsh/ksh, `personal/claude.fish` for
  fish), wired into rc files by `bin/claude-custom install`, never merged into
  `~/.claude/settings.json`. `--settings` holds one file: a second `--settings`
  replaces the first, so `bin/claude-ollama` launches don't get the personal
  overlay (the Ollama profiles carry their own deny globs and hooks). Top-level
  scalars in the overlay override the user file, so don't add keys to the
  overlay that `~/.claude/settings.json` already sets.
- `personal/CLAUDE.tokens.md` reaches every personal session through an `@`
  import that `bin/claude-custom install` adds to `~/.claude/CLAUDE.md` (the
  imported files are listed in `imported_files`). Keep it short: it loads on
  every turn.
- `model-picker-tui/` has two packages: `profiles` (`Load` reads the configured
  sizes from `ollama/`) and `ui` (the Bubble Tea model).
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
