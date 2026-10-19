# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with
code in this repository.

## What this repo is

Configuration overlays for Claude Code itself, plus two small Go apps. There are
four parts:

- **Personal setup** (`personal/`, `project/`): loaded with `--settings` by the
  `claude` shell function, and `shared/preferences/PREFERENCES.md` is
  `@`-imported into `~/.claude/CLAUDE.md`, to cut token usage on the normal
  Anthropic-backed `claude`.
- **Preference enforcement** (`shared/hooks/`, `shared/preferences/`): hooks and
  a short rules file that both the personal setup and the work harness load, so
  the same checks run whichever model is driving.
- **Work harness** (`bin/claude-ollama`, `ollama/`, `go/cmd/model-picker/`):
  starts `claude` against a local Ollama server (`localhost:11434`) running Qwen
  3.8 27b or Qwen 3.6 35b. The overlay only applies to that launch.
  `go/cmd/model-picker/` is a Go/Bubble Tea menu for choosing the size.
- **Tools TUI** (`go/cmd/claude-tools/`): a Go/Bubble Tea app that edits the
  bare-tool-name permission rules in a Claude Code settings file.

Every file is additive. Nothing here replaces a base config. The layer order and
install/revert steps are in `README.md`. Read it before changing how any file
gets applied.

## Commands

- Hook tests: `shared/hooks/*.test.sh` (each prints `all passed`, or `FAIL:`
  lines and exits 1)
- Everything at once: `make test` (`.claude/verify` runs it; the Stop hook runs
  that)
- Installer tests: `personal/install.test.sh` (prints `all passed`)
- Launcher tests: `bin/claude-ollama.test.sh` (prints `all passed`; covers
  `bin/claude-ollama` and the `claude-custom ollama|tools` subcommands)
- Config check: `bin/check-config` (prints `all passed`; static checks that the
  `ollama/` and `personal/` config files agree with each other)
- Cache probe: `bin/ollama-cache-probe [27b|35b|MODEL] [--prefix-tokens N]`
  measures prompt-cache reuse on a live Ollama; its tests are
  `bin/ollama-cache-probe.test.sh` (stub server, no real Ollama)
- Code search MCP server: `shared/mcp/code-search.py`; its tests are
  `shared/mcp/code-search.test.sh` (stub embedding server, temp git repo)
- Feed the hook one command by hand:
  `printf '{"tool_input":{"command":"git log"}}' | shared/hooks/bash-output-guard.py`
- Validate JSON after editing: `make check-json`
- Launch the work harness: `claude-ollama [27b|35b] [claude args...]` (27b is
  the default size; `--help` lists sizes)
- Check the work harness: `claude-ollama doctor [size]` (exit 1 on a missing
  model, hook, context mismatch or server env var; needs `jq`) and
  `claude-ollama --print-config [size]` (resolved values, no launch)
- Launch the tools TUI: `claude-tools [user|project|local|FILE]`. Both are also
  `claude-custom ollama|tools [...]`.
- `bin/claude-custom`, `bin/claude-ollama` and `bin/claude-tools` must stay
  bash-3.2 compatible (macOS `/bin/bash`). `bin/claude-custom` must never write
  `~/.zshenv` or `~/.local/bin/claude`, and derives Ollama model names from
  `ollama/settings.<size>.json` and `ollama/Modelfile.<size>`. Adding a size
  means adding both files; the installer picks it up.
- Go module `go/` (both apps; `go/cmd/model-picker/`, `go/cmd/claude-tools/`):
  `cd go && go test ./...`. One test:
  `cd go && go test ./internal/tools/ui -run TestSwitching`. Run the picker or
  the tools TUI with `cd go && go run ./cmd/model-picker` or
  `cd go && go run ./cmd/claude-tools`. `claude-ollama` builds and runs the
  picker when no size is given on a terminal. See
  `go/cmd/claude-tools/README.md`.

There is no build step outside the Go module. `claude-custom install` builds
`go/cmd/claude-tools/claude-tools` and `go/cmd/model-picker/model-picker` (both
gitignored). Each launcher rebuilds its binary only when a Go source, `go.mod`
or `go.sum` is newer than it. `pnpm install` enables git hooks (husky):
pre-commit checks staged files for conflict markers, files over 1 MB and
secrets, then lint-staged runs Prettier on staged `.md`/`.json`/`.yml`.
commitlint enforces conventional commits (`feat:`, `fix:`, `chore:`).

## How the pieces connect

- `shared/hooks/bash-output-guard.py` is a `PreToolUse` hook on Bash. It denies
  commands that would flood the context (unbounded `git log`, `cat` on a
  lockfile, recursive `ls`). Each rule in `UNBOUNDED_COMMANDS` is built by
  `needs_bounding_flag`, `must_not_open` or `must_not_use_flag`, which prepend
  `COMMAND_START` so a rule only matches at the start of a command segment and
  ignores text inside arguments. A new rule needs both `expect deny` and
  `expect allow` cases in the test script.
- `shared/hooks/bash-output-trim.py` is a `PostToolUse` hook on Bash. It
  shortens long stdout/stderr through `updatedToolOutput`, keeping head, tail
  and error/fail lines plus a marker naming the hidden line range. The reply
  must keep the Bash output shape (`stdout`, `stderr`, `interrupted`, `isImage`)
  or Claude Code ignores it.
- `shared/hooks/read-range-guard.py` is a `PreToolUse` hook on Read. It denies
  reading a file over 300 lines unless `limit` is 300 or less. Read can't be
  disabled for the local models: Edit refuses files that weren't Read first.
- `shared/hooks/edit-check.py` (PostToolUse on Edit/Write/MultiEdit) runs the
  edited file's project-local formatter/linter and rejects newly added comments.
  It caches passes by content hash under `~/.cache/claude-custom/edit-check`
  (`EDIT_CHECK_CACHE_DIR` overrides). `shared/hooks/stop-verify.py` (Stop) runs
  Fallow in JS/TS projects and the project's `.claude/verify`, falling back to
  `make test`, `go test ./...` or `pnpm test` when none exists (an empty
  `.claude/no-verify` opts out); it blocks once per turn (`stop_hook_active`).
  Both exit 2 so the model sees stderr.
- The `fallow-*.sh` hooks gate Fallow use in JS/TS projects and share
  `shared/hooks/fallow-lib.sh` (sourced from the hook's own directory).
  `fallow-command-guard.sh` (PreToolUse on Bash) denies `fallow` calls without
  `--format json`, denies `fallow fix --yes` until a `--dry-run` ran in the
  session, and denies `git commit`/`git push` while `fallow audit` fails. It
  only looks at the first word of each command segment (plus `npx fallow`),
  never at arguments. `fallow-mark-preview.sh` (PostToolUse on Bash) records the
  dry run. `fallow-after-edit.sh` (PostToolUse on Edit/Write) adds the edited
  file's audit findings as context. Tests stub `fallow` on PATH through
  `fallow-test-lib.sh`; `.shellcheckrc` lets shellcheck follow the sourced
  library.
- `shared/preferences/PREFERENCES.md` holds the prose rules no tool can check,
  including token discipline. `bin/claude-custom install` `@`-imports it into
  `~/.claude/CLAUDE.md`, so both backends load it. Keep it short: Ollama has 64k
  context.
- `shared/hooks/tool-nudge.py` is wired only in the Ollama profiles
  (UserPromptSubmit resets its per-session state under
  `~/.claude/cache/tool-nudge/`). As PreToolUse on Bash and
  `mcp__code-search__semantic_search` it denies a Bash command that leads with a
  text search (`grep`, `rg`, `ag`, `ack`, `git grep`) until the MCP tool has
  been called in the turn, at most twice per turn so a dead server can't lock
  the model out. As PostToolUse on Bash, Read and Agent it adds
  `additionalContext` once per turn after the 6th read-or-search (delegate to
  `Agent`).
- All settings files (`personal/settings.tokens.json`, `ollama/settings.*.json`)
  run hooks as `"$CLAUDE_CUSTOM_HOME"/shared/hooks/<name>`. Hook commands go
  through a shell, so the variable expands. `personal/claude.sh` and
  `personal/claude.fish` pass it to `claude` with `env` (the rc block defines it
  unexported), and `bin/claude-ollama` exports it from its own `repo_dir`.
  Nothing is linked into `~/.claude/hooks`; `install` and `uninstall` remove
  links there that point into `shared/hooks/` (`remove_stale_hook_links`).
  `personal/install.test.sh` checks every hook command resolves to an executable
  in `shared/hooks/`.
- The Read `permissions.deny` globs and the `hooks` block are shared by all
  settings files. Change them together; `bin/check-config` fails when an Ollama
  profile lacks a hook the personal overlay has (the profiles may add hooks of
  their own, like `tool-nudge.py`). `ollama/settings.*.json` also deny unused
  tools by bare name, so their schemas never reach the local model's context.
  `--tools` in `bin/claude-ollama` is the primary allowlist and that deny list
  is the backstop. `bin/check-config` fails when the Ollama deny lists differ.
  The personal overlay also denies unused tools by bare name (`Artifact`,
  `Workflow`, `ScheduleWakeup`, `SendFeedback` and the deferred ones), since a
  bare deny removes the tool's schema from the request; `bin/check-config` fails
  when an Ollama profile lacks one of those bare denies.
- `bin/claude-ollama` resolves its own symlink to find `ollama/`. It unsets
  `ANTHROPIC_API_KEY`, passes `--settings ollama/settings.<size>.json`,
  `--system-prompt-file ollama/system-prompt.md` (replacing Claude Code's
  default system prompt), `--append-system-prompt-file ollama/CLAUDE.<size>.md`,
  `--strict-mcp-config` plus an inline `--mcp-config` for the code-search
  server, `--model` with the profile's `model` (it also unsets
  `ANTHROPIC_MODEL`, which would otherwise win over the settings file), and
  restricts tools with `--tools` (built-in tools only; MCP tools still load).
  Before launching, it pulls the base model and creates the `-cc` model when
  `ollama show` can't find the `-cc` model. When the side model is missing it
  launches with a temporary copy of the profile whose side-model entries point
  at the main model (`--require-side-model` exits 1 instead). `doctor` and
  `--print-config` are dispatched before any pull or launch; `doctor` reads hook
  names from the profile's settings file, not from `~/.claude/hooks`.
- The **side model** (`ollama/side.Modelfile`, `qwen3:4b` created as
  `qwen3-4b-cc`) fills the Haiku slot: every Ollama profile sets
  `ANTHROPIC_DEFAULT_HAIKU_MODEL` to it. The file is not `Modelfile.side`
  because `Modelfile.*` must pair with a `settings.<size>.json`. The model
  picker's "Set up side model" row pulls and creates it. The Ollama profiles set
  `CLAUDE_CODE_SUBAGENT_MODEL` to the side model's ID, not `haiku`, and map the
  full Haiku IDs to it in `modelOverrides`, because `ANTHROPIC_DEFAULT_*_MODEL`
  only remaps aliases. Never map a Claude ID to the main model there: Claude
  Code then names it after that ID, so the banner says Sonnet.
  `personal/settings.tokens.json` uses `CLAUDE_CODE_SUBAGENT_MODEL=haiku`. All
  of them set `CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1` (Claude Code v2.1.257 or
  later), so `Agent` is allowed in `--tools` and not in the deny list.
- `bin/claude-ollama` reads the configured sizes from `ollama/` (a
  `settings.<size>.json` plus a `Modelfile.<size>`), never a hardcoded list. A
  first arg that matches launches that size. Otherwise, on a terminal it runs
  `go/cmd/model-picker` (which renders on stderr and prints the chosen size on
  stdout); without one it uses 27b. A first arg that is neither a size nor a
  flag is dropped so it doesn't reach `claude` as a prompt.
- `shared/mcp/code-search.py` is the `semantic_search` MCP server (JSON-RPC over
  stdio, stdlib only). It embeds chunks through Ollama `/api/embed`, keeps its
  index in `.git/code-search/index.json` and re-embeds only changed files.
  `claude-ollama` starts `code-search.py --index` in the background on launch
  (`CLAUDE_OLLAMA_NO_INDEX=1` skips it). `bin/claude-ollama` pulls its model
  (`CODE_SEARCH_MODEL`, default `qwen3-embedding:0.6b`); the model picker's "Set
  up embedding model" row pulls it too. The default name appears once in each of
  `bin/claude-ollama`, `code-search.py` and
  `go/internal/picker/profiles/embedding.go`, and `bin/check-config` checks they
  agree. The Ollama profiles allow the tool in `permissions.allow`.
- `ollama/server.env` documents the Ollama server env the profiles expect. The
  Homebrew service sets the same values. Nothing in this repo applies it.
  `bin/claude-ollama` sends a background warm-up `keep_alive` request to
  `OLLAMA_HOST` (default `localhost:11434`) before `exec claude`.
- `ollama/CLAUDE.<size>.md` files are appended system prompts for small local
  models, not memory files. Keep them terse: both sizes have a 64k context.
  Context sizes must match across `Modelfile.<size>` (`num_ctx`),
  `CLAUDE_CODE_MAX_CONTEXT_TOKENS`, `CLAUDE_CODE_AUTO_COMPACT_WINDOW`, and the
  `ollama create` names that `model` and the `ANTHROPIC_DEFAULT_*_MODEL` vars
  refer to. The compact window is pinned because a managed `availableModels`
  that lacks the model makes Claude Code substitute a `[1m]` ID, which assumes a
  1M window; `claude-ollama doctor` warns when that happens.
  `ollama/system-prompt.md` replaces Claude Code's default system prompt for
  both sizes; keep it short and don't put size-specific rules in it.
- The personal overlay is loaded with `--settings` by the `claude` shell
  function (`personal/claude.sh` for bash/zsh/ksh, `personal/claude.fish` for
  fish), wired into rc files by `bin/claude-custom install`, never merged into
  `~/.claude/settings.json`. `--settings` holds one file: a second `--settings`
  replaces the first, so `bin/claude-ollama` launches don't get the personal
  overlay (the Ollama profiles carry their own deny globs and hooks). Top-level
  scalars in the overlay override the user file, so don't add keys to the
  overlay that `~/.claude/settings.json` already sets.
- `go/internal/picker/` has two packages: `profiles` (`Load` reads the
  configured sizes from `ollama/`, `EmbeddingModel` the search model) and `ui`
  (the Bubble Tea model).
- `go/internal/tools/` has three packages:
  - `catalog`: fetches the tool table from the Claude Code docs and caches it in
    the user cache dir.
  - `settings`: maps rules to and from `ToolState`, using gjson/sjson so other
    keys survive. Saves are atomic and keep a `.bak`. Also lists the user,
    project and local files.
  - `ui`: the Bubble Tea model. It's "dirty" when `states` differs from `saved`.

  The TUI only touches rules that are a bare tool name. Scoped rules like
  `Bash(git log *)` are never changed. "Disable" means a bare deny rule. Write
  rules are in `go/cmd/claude-tools/README.md`.
