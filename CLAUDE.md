# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with
code in this repository.

## What this repo is

Configuration overlays for Claude Code itself, plus two small Go apps. There are
four parts:

- **Personal setup** (`personal/`, `project/`): loaded with `--settings` by the
  `claude` shell function, and `shared/preferences/PREFERENCES.md` is
  `@`-imported into `~/.claude/CLAUDE.md`, to cut token usage on the normal
  Anthropic-backed `claude`; the overlay also turns Claude Code's own sandbox
  on, runs `claude` through `shared/sandbox-env` (`personal/launch`), which
  points package caches at `~/.cache/claude-sandbox`, and asks before any
  unsandboxed retry.
- **Preference enforcement** (`shared/hooks/`, `shared/preferences/`): hooks and
  a short rules file that both the personal setup and the work harness load, so
  the same checks run whichever model is driving.
- **Work harness** (`bin/claude-ollama`, `ollama/`, `go/cmd/model-picker/`):
  starts `claude` against a local Ollama server (`localhost:11434`) running Qwen
  3.8 27b or Qwen 3.6 35b. The overlay only applies to that launch.
  `claude-ollama qwen [size]` runs Qwen Code on the same model and MCP servers
  inside macOS Seatbelt (`ollama/qwen-sandbox.sb`, copied to the project's
  `.qwen/sandbox-macos-claude-ollama.sb` and excluded from git at each launch;
  `QWEN_SANDBOX=sandbox-exec`, never `SANDBOX`), with `~/.claude-ollama/qwen` as
  its `QWEN_HOME`; `qwen doctor [size]` checks that setup. Its settings come
  from `ollama/qwen-settings.template.json` and `ollama/QWEN.local.md` (see
  `docs/ollama.md`). `go/cmd/model-picker/` is a Go/Bubble Tea menu for choosing
  the size.
- **Tools TUI** (`go/cmd/claude-tools/`): a Go/Bubble Tea app that edits the
  bare-tool-name permission rules in a Claude Code settings file. `-json` prints
  the rules and `-set NAME=perm[,off]` saves them without the TUI (scope last).
  The console's `/tools` page drives both: `GET /api/tools` reads `-json`, and
  the Save button runs `tools-set` (`-set` per change) against the user file.
- **Agent TUI** (`go/cmd/ollama-agent/`): a Go/Bubble Tea app that edits the
  `OLLAMA_*` variables in a `local.ollama` LaunchAgent and reloads it, since
  launchd never reads `~/.zshenv`. `-json` prints the variables and conflicts
  without writing; `-set NAME=VALUE` (repeatable) writes just those and reloads.
  The console's Server page uses both.

Every file is additive. Nothing here replaces a base config. The layer order is
in `docs/layers.md` and install/revert steps in `docs/install.md`. Read them
before changing how any file gets applied.

## Commands

- Hook tests: `shared/hooks/*.test.sh` (each prints `all passed`, or `FAIL:`
  lines and exits 1)
- Everything at once: `make test` (`.claude/verify` with no arguments runs it).
  `make test` runs the targets in parallel (`$(MAKE) -j$(NPROC) test-all`);
  `make test-all` runs them one after another when interleaved output gets in
  the way. The Stop hook runs `.claude/verify FILE...` with the files the agent
  edited, which runs `check-json`, `check-config`, `check-profiles` plus each
  file's tests (`X.test.sh` beside `X`, mappings in the script; a `Makefile`
  edit runs `make test`). Its tests: `.claude/verify.test.sh`
- CI: `.github/workflows/verify.yml` runs `make test` on macOS and Ubuntu on
  every push to main and every PR.
- Installer tests: `personal/install.test.sh` (prints `all passed`)
- Run log tests: `bin/console-run.test.sh` (prints `all passed`;
  `make test-console`)
- Launcher tests: `bin/claude-ollama.test.sh` (prints `all passed`; covers
  `bin/claude-ollama` and the `claude-custom ollama|qwen|tools` subcommands)
- Model manager:
  `bin/ollama-models list|outdated [NAME...]|prune [--yes]|pin NAME[:TAG]` marks
  installed models (pinned, mismatch, profile, orphan, third-party, other),
  `outdated` compares each pin with the registry (current, behind, unknown,
  skipped, unpinned; exit 1 when one is behind or unpinned), removes third-party
  and orphan `-cc` models after asking (`prune --yes --only NAME...` removes
  just the named models that are still prunable, for the console's Models page),
  and writes a registry manifest sha256 to `ollama/model-digests.json`; tests:
  `bin/ollama-models.test.sh` (stub `ollama`, stub `curl`)
- Model upgrade: `bin/model-upgrade SIZE [--eval] [--keep] [--force]` pulls a
  behind base into `MODEL-next`, runs `speed-check --thinking-only --model`, the
  cache probe and (with `--eval`) `pr-review-eval`, saves
  `~/bench-results/upgrade-SIZE-*.json`, then promotes the candidate to the
  size's `-cc` model on a pass or removes it and the local base on a fail
  (`--keep` keeps the candidate). It prints the `pin` command and never writes
  the pin; GGUF sizes are refused. Tests: `bin/model-upgrade.test.sh` (stub
  `ollama`, stub tools)
- Config check: `bin/check-config` (prints `all passed`; static checks that the
  `ollama/` and `personal/` config files agree with each other)
- Profile generator: `bin/ollama-profiles` renders `ollama/settings.<size>.json`
  and `ollama/Modelfile.<size>` from `ollama/sizes.json` and the two
  `profile-template` files, and `personal/settings.tokens.json` from
  `personal/settings.tokens.template.json`; `bin/ollama-profiles --check`
  (`make check-profiles`) fails when they are stale (it compares JSON by
  content, so it needs no Prettier; writing the files needs `pnpm install`);
  tests: `bin/ollama-profiles.test.sh`
- GGUF inspector: `bin/gguf-inspect FILE [--file-size N] [--template-out PATH]`
  checks a GGUF header with strict bounds before Ollama parses it (never reads
  tensor data); tests: `bin/gguf-inspect.test.sh`
- Cache probe: `bin/ollama-cache-probe [27b|35b|MODEL] [--prefix-tokens N]`
  measures prompt-cache reuse on a live Ollama; its tests are
  `bin/ollama-cache-probe.test.sh` (stub server, no real Ollama)
- Speed check: `claude-ollama speed-check` (`bin/speed-check`) checks power,
  disk and Ollama, prepares the four MLX and GGUF sizes, then runs the thinking
  check, the paired benches and the cache probes, and prints a verdict and a
  paste block; `CLAUDE_OLLAMA_SPEED_CHECK` and `SPEED_CHECK_LAUNCHER`/`_BENCH`/
  `_PROBE` override the scripts in tests; tests: `bin/speed-check.test.sh`.
  `claude-ollama prepare [size]` pulls or imports one size and exits;
  `claude-ollama prepare-embedding` pulls the `semantic_search` embedding model
  and exits; `claude-ollama thinking-check` (`bin/speed-check --thinking-only`)
  runs only the thinking check on the MLX sizes and exits 1 when it fails
- Messages bench:
  `bin/messages-bench --model M [--base-url URL] [--thinking omit|claude-code|disabled]`
  times any `/v1/messages` server (cold/warm TTFT, prefill, decode, tool calls);
  runbook and results in `docs/backend-bench.md`; tests:
  `bin/messages-bench.test.sh` (stub server)
- Bench-off: `bin/backend-bench-off install|download|all` benches Ollama, oMLX
  and vllm-mlx, each with MTP off (stock MLX weights) and on (`oQ4e` MTP
  weights), model by model, and streams each run's JSONL into one side-by-side
  HTML page that reloads while it runs (`bin/backend-bench-report`, default
  `~/bench-results/bench-off.html`); `run SERVER MODEL` reruns one cell; MTP-on
  vllm-mlx runs copy the head with `bin/extract-mtp-weights`; tests:
  `bin/backend-bench-off.test.sh` (stub servers),
  `bin/backend-bench-report.test.sh`, `bin/extract-mtp-weights.test.sh`
- Code search MCP server: `shared/mcp/code-search.py`; its tests are
  `shared/mcp/code-search.test.sh` (stub embedding server, temp git repo)
- Repo tools MCP server: `shared/mcp/repo-tools.py`; its tests are
  `shared/mcp/repo-tools.test.sh` (stub gh, temp git repo). Both servers share
  the JSON-RPC loop in `shared/mcp/mcp_stdio.py`.
- Dev server MCP server: `shared/mcp/dev-server.py`; its tests are
  `shared/mcp/dev-server.test.sh` (stub npm, fake Next server, stub cmux).
- Feed the hook one command by hand:
  `printf '{"tool_input":{"command":"git log"}}' | shared/hooks/bash-output-guard.py`
- Validate JSON after editing: `make check-json`
- Launch the work harness: `claude-ollama [27b|35b] [claude args...]`, which
  runs `claude` on the profile in `ollama/settings.<size>.json` (27b is the
  default size; `--help` lists sizes)
- Check the work harness: `claude-ollama doctor [size]` (exit 1 on a missing
  model, hook, context mismatch or server env var; needs `jq`) and
  `claude-ollama --print-config [size]` (resolved values, no launch). Follow the
  server log: `claude-ollama logs [-n LINES]` (the running launchd job's log,
  else the LaunchAgent plist path, else the Homebrew log, else the app log);
  `claude-ollama logs --path` prints that path instead of following it. Each
  launch also copies its own stderr, up to the hand-off to `claude`, to
  `$CLAUDE_CONSOLE_STATE_DIR/launcher.log` (0600, moved to `launcher.log.1` past
  1 MiB); the console's Logs page has Ollama server and Launcher tabs
  (`/api/logs/path` and `/api/logs/events` take `?source=server|launcher`)
- Console: `claude-ollama ui [--port N]` serves `web/console` (Next.js with AI
  Elements) at `http://127.0.0.1:8765/`, built on first run with pnpm
  (reinstalled when `pnpm-lock.yaml` is newer than `node_modules/.modules.yaml`,
  rebuilt when a source is newer than `.next/BUILD_ID`). The reviews list is at
  `/reviews`; `claude-ollama reviews [--port N]` runs the same server and prints
  that link. A start on a port that already answers prints the running console's
  tokened link and starts nothing, writing a new token file if the old one was
  lost. Its tests run with `make test-web`.
- Console smoke check: `bin/console-smoke [--port N] [--keep]` starts
  `claude-ollama ui` on a temp state dir, checks every page, the token gate and
  the same-origin rule, then prints `all passed` (`make smoke-console`; `--keep`
  leaves it running with its link). It starts no run or model. Tests:
  `bin/console-smoke.test.sh` (`make test-smoke`).
- Run log:
  `bin/console-run --log FILE --id ID --command NAME --label TEXT -- ARGV...`
  runs one command and writes a JSONL run log (`start`, `line`, `progress`,
  `end` events) to `$CLAUDE_CONSOLE_STATE_DIR/runs/<id>.jsonl` (folder 0700,
  files 0600). Tests: `bin/console-run.test.sh` (`make test-console`). The
  console starts runs only from the command list in
  `web/console/src/lib/console-commands.ts`: fixed argv, params checked against
  the configured sizes, one run per command at a time. Its server gets
  `CLAUDE_CUSTOM_HOME` and `CLAUDE_CONSOLE_STATE_DIR` from `serve_console`.
  Every POST to the console must carry an `Origin` equal to its own
  `http://<host>` (`proxy.ts`), so a cross-site page can't start a run.
- Launch the tools TUI: `claude-tools [user|project|local|FILE]`. Launch the
  agent TUI: `ollama-agent [-file PLIST] [-ollama BIN]`. All three are also
  `claude-custom ollama|qwen|tools|agent [...]`.
- `bin/claude-custom`, `bin/claude-ollama`, `bin/claude-tools` and
  `bin/ollama-agent` must stay bash-3.2 compatible (macOS `/bin/bash`).
  `bin/claude-custom` must never write `~/.zshenv` or `~/.local/bin/claude`, and
  derives Ollama model names from `ollama/settings.<size>.json` and
  `ollama/Modelfile.<size>`, both rendered from `ollama/sizes.json`. Adding a
  size means one `sizes.json` entry, then `bin/ollama-profiles`; never hand-edit
  the rendered files. Every `base` (plus the default embedding model) must be an
  Ollama library model (no `/` in the name) with a manifest sha256 in
  `ollama/model-digests.json`, or a `./weights/<file>.gguf` from an
  `unsloth/*-GGUF` repo at a pinned commit whose file sha256 is the pin;
  `bin/check-config` checks both. `bin/claude-ollama` checks `/api/tags` against
  the pin after pulling a base and before each launch, exits 1 on a mismatch,
  and `doctor` reports it. A pin is the sha256 of the registry manifest
  (`https://registry.ollama.ai/v2/library/NAME/manifests/TAG`).
- Go module `go/` (all three apps; `go/cmd/model-picker/`,
  `go/cmd/claude-tools/`, `go/cmd/ollama-agent/`): `cd go && go test ./...`. One
  test: `cd go && go test ./internal/tools/ui -run TestSwitching`. Run the
  picker or the tools TUI with `cd go && go run ./cmd/model-picker` or
  `cd go && go run ./cmd/claude-tools`. `claude-ollama` builds and runs the
  picker when no size is given on a terminal. See
  `go/cmd/claude-tools/README.md` and `go/cmd/ollama-agent/README.md`.

`claude-custom install` (and `update`, which runs it) restarts a running Ollama
server through `ollama-agent -apply` when it lacks a value from
`ollama/server.env` (macOS only; a failed restart only warns). `update` execs
the pulled `claude-custom finish-update`, which runs the install again.

There is no build step outside the Go module. `claude-custom install` builds
`go/cmd/claude-tools/claude-tools`, `go/cmd/model-picker/model-picker` and
`go/cmd/ollama-agent/ollama-agent` (all gitignored), and removes the retired
`sandbox-runtime` and Shortcut CLI folders. Each launcher rebuilds its binary
only when a Go source, `go.mod` or `go.sum` is newer than it. `pnpm install`
enables git hooks (husky): pre-commit checks staged files for conflict markers,
files over 1 MB and secrets, then lint-staged runs Prettier on staged
`.md`/`.json`/`.yml`. commitlint enforces conventional commits (`feat:`, `fix:`,
`chore:`).

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
  project's prettier and eslint from `node_modules/.bin` and gofmt, go vet,
  ruff, shellcheck and `bash -n` from PATH, and rejects newly added comments. It
  caches passes by content hash under `~/.cache/claude-custom/edit-check`
  (`EDIT_CHECK_CACHE_DIR` overrides). `shared/hooks/stop-verify.py` also runs on
  PostToolUse Edit/Write/MultiEdit, where it appends the edited path to a
  per-session log under `~/.cache/claude-custom/edited-files`
  (`STOP_VERIFY_STATE_DIR` overrides). On Stop it does nothing unless that log
  has files inside the project. Otherwise it runs `fallow audit` on each edited
  JS/TS file in JS/TS projects and the project's `.claude/verify` with the
  edited files as arguments, falling back to `make test`, `go test ./...` or
  `pnpm test` when none exists (an empty `.claude/no-verify` opts out). A pass
  clears the log; a failure keeps it. Its message lists one line per new fallow
  finding in the edited files (at most 20; fallow tool errors don't block) and
  keeps a failing command's error lines plus a 15-line tail, each line clipped
  to 300 characters. It blocks once per turn (`stop_hook_active`). Both exit 2
  so the model sees stderr.
- The `fallow-*.sh` hooks gate Fallow use (the commit/push gate only in JS/TS
  projects) and share `shared/hooks/fallow-lib.sh` (sourced from the hook's own
  directory). `fallow-command-guard.sh` (PreToolUse on Bash) denies `fallow`
  calls without `--format json`, denies `fallow fix --yes` until a `--dry-run`
  ran in the session, and denies `git commit`/`git push` while `fallow audit`
  fails. It only looks at the first word of each command segment (plus
  `npx fallow`), never at arguments. `fallow-mark-preview.sh` (PostToolUse on
  Bash) records the dry run. `fallow-after-edit.sh` (PostToolUse on Edit/Write)
  adds the edited file's audit findings as context. Tests stub `fallow` on PATH
  through `fallow-test-lib.sh`; `.shellcheckrc` lets shellcheck follow the
  sourced library.
- `shared/hooks/tool-telemetry.py` is a `PostToolUse` hook on every tool. With
  `CLAUDE_TOOL_TELEMETRY=<file>` set it appends one JSON line per call (time,
  session, tool, bytes, lines, over the trim limit; never the tool input).
  `claude-ollama` sets that variable to
  `~/.claude-ollama/telemetry/tool-calls.jsonl` unless
  `CLAUDE_OLLAMA_TELEMETRY=0`, and a symlinked folder or file turns it off for
  that launch. The five deny hooks add one `"kind": "deny"` line per denial
  through `shared/hooks/hook_telemetry.py` (hook name and reason, never the
  command; a path that cannot be written never changes the decision), and
  `.claude/verify` maps that module to their tests.
  `bin/tool-telemetry-report LOG` summarises calls and denials and refuses a
  symlink; its test is `bin/tool-telemetry-report.test.sh`. Its
  `TRIM_LINE_LIMIT` must equal `MAX_LINES` in `bash-output-trim.py`
  (`bin/check-config` checks it).
- `shared/preferences/PREFERENCES.md` holds the prose rules no tool can check,
  including token discipline. `bin/claude-custom install` `@`-imports it into
  `~/.claude/CLAUDE.md`, so both backends load it. Keep it short: Ollama has
  64k-96k context.
- `shared/agents/pr-review.md` is a Claude Code subagent definition that
  `bin/claude-custom install` links into `~/.claude/agents/`. It reviews a
  GitHub PR from a temporary worktree (`gh pr view`/`diff`, callers via Grep,
  Fallow `audit --base <merge-base> --format json` on changed TypeScript through
  `fallow_report_filter` in `shared/hooks/fallow-lib.sh`) and prints
  Conventional-Comments findings with a verdict. Run it as the main thread with
  `claude --agent pr-review`; as a subagent it lands on the forced Haiku model.
  No `model:` key: FORCE ignores it and `--agent` must keep the session model.
  `bin/check-config` checks the frontmatter and the Fallow command.
- `shared/skills/handoff/SKILL.md` is the `/handoff` skill, which
  `bin/claude-custom install` links into `~/.claude/skills/` (so `claude-ollama`
  copies it into its session). `/handoff save` writes a note to
  `<git common dir>/handoff/` and `/handoff` resumes from the newest one.
  `bin/check-config` checks each `shared/skills/*` name matches its folder.
- `bin/pr-review-local --model M [--base-url URL] [--post] [--json] [--color auto|always|never] [--log-dir DIR] [--no-log] [--range BASE..HEAD | PR]`
  reviews a GitHub PR with a local model, or local commits with `--range` (no
  `gh`, no comments or CI, no `--post`): `gh`/`git` gather the PR (no checkout
  in the user's tree), Fallow runs on changed TypeScript in a temporary worktree
  of the PR head through `fallow_report_filter` from
  `shared/hooks/fallow-lib.sh`, one `/v1/messages` request per changed file
  returns a JSON findings array (one retry), the verdict is a fixed rule, and
  the report matches the `pr-review` agent's shape.
  `claude-ollama review [size] PR` resolves the size's model, warms it and execs
  the script (`CLAUDE_OLLAMA_REVIEWER` overrides the path; tests stub it). The
  event log (`--log-dir`, `0700` dir and `0600` files) also holds `prompt`
  (exact `system` and `user`, per file attempt and for `summary`) and
  `reply_text` (streamed reply text, flushed at the end), beside `file_start`,
  `writing`, `retry` and `file_done`. Tests: `bin/pr-review-local.test.sh` (stub
  `/v1/messages`, stub `gh`, stub `fallow`, two temp git repos).
- Review eval:
  `bin/pr-review-eval --model M [--base-url URL] [-- reviewer args]` reviews
  every scenario in `eval/pr-review/scenarios/` (six: `telemetry`,
  `shell-injection`, `async-ts`, `go-errors`, `weak-test`, `clean-refactor`;
  `--scenario NAME` picks some) with `pr-review-local --range`, checks each
  verdict, and prints a scorecard ending in a `total:` line; tests:
  `bin/pr-review-eval.test.sh` (stub reviewer)
- `shared/hooks/tool-nudge.py` is wired only in the Ollama profiles
  (UserPromptSubmit resets its per-session state under
  `${CLAUDE_CONFIG_DIR:-~/.claude}/cache/tool-nudge/`). As PreToolUse on Bash
  and `mcp__code-search__semantic_search` it denies every Bash command that runs
  a text search (`grep`, `rg`, `ag`, `ack`, `git grep`, or `find` with a name or
  path filter) at the head of any command in it, until the MCP tool has been
  called in the turn. A search after a pipe is a filter and passes. Calling the
  tool unlocks text search for the turn even when it errors, so a dead server
  can't lock the model out.
- All settings files (`personal/settings.tokens.json`, `ollama/settings.*.json`)
  run hooks as
  `"$CLAUDE_CUSTOM_HOME"/shared/host-env "$CLAUDE_CUSTOM_HOME"/shared/hooks/<name>`,
  and `bin/claude-ollama` starts its MCP servers through `shared/host-env` too:
  it unsets the cache variables `shared/sandbox-env` set, so nothing a hook or
  server runs (`go test`, `npx fallow`) executes from the sandbox-writable cache
  (`bin/check-config` checks both). Hook commands go through a shell, so the
  variable expands. `personal/claude.sh` and `personal/claude.fish` pass it to
  `claude` with `env` (the rc block defines it unexported), and
  `bin/claude-ollama` exports it from its own `repo_dir`. Nothing is linked into
  `~/.claude/hooks`; `install` and `uninstall` remove links there that point
  into `shared/hooks/` (`remove_stale_hook_links`). `personal/install.test.sh`
  checks every hook command resolves to an executable in `shared/hooks/`.
- The Read `permissions.deny` globs and the `hooks` block live in
  `shared/settings/read-deny.json` and `shared/settings/hooks.json`;
  `bin/ollama-profiles` splices them into every rendered settings file
  (`ollama/settings.<size>.json`, `personal/settings.tokens.json`). Edit the
  fragment, run `bin/ollama-profiles`, commit. The Ollama-only hooks
  (`tool-nudge.py`) are in `ollama/hooks.extra.json` and follow the shared hooks
  for each event. `bin/check-config` fails when an Ollama profile lacks a hook
  the personal overlay has. `ollama/settings.*.json` also deny unused tools by
  bare name, so their schemas never reach the local model's context. `--tools`
  in `bin/claude-ollama` is the primary allowlist and that deny list is the
  backstop. `bin/check-config` fails when the Ollama deny lists differ. A local
  model's weights are not trusted, so Bash runs in Claude Code's own sandbox,
  configured by the `sandbox` block in `ollama/profile-template.json` (rendered
  per size). Sandboxed commands write the project, a temp dir and
  `~/.cache/claude-sandbox`, reach loopback addresses, `github.com`, the npm, Go
  and PyPI registries and GitHub downloads, and cannot read credentials or
  `~/.claude`. The launcher execs `claude` and `qwen` through
  `shared/sandbox-env`, which points Go, npm, pnpm, pip, uv, yarn and bun at
  caches under that one folder, so no cache an unsandboxed process executes from
  (`~/.npm/_npx`, `~/Library/pnpm`, `~/go/pkg/mod`, `~/.cache/claude-custom`) is
  writable. `bin/check-config` asserts the block's exact values, and a
  misspelled key is silently ignored, so the check must change with the block.
  The profiles set `sandbox.enabled` and `autoAllowBashIfSandboxed: true`, so
  sandboxed commands run without a prompt (a skill's `!` commands included);
  `excludedCommands` (`cmux`, `gh`, `short`, `git push`) run outside the
  sandbox, each after the `Bash` prompt, and `permissions.ask` holds only
  `Bash(git commit *)`, `Bash(git push *)` and
  `Bash(dangerouslyDisableSandbox:true)`; `bin/check-config` checks both. The
  profiles also set `CLAUDE_CODE_EXTRA_BODY` to
  `{"thinking":{"type":"disabled"}}` so Ollama skips reasoning;
  `bin/check-config` checks it. `shared/hooks/git-push-guard.py` (Ollama-only,
  PreToolUse on Bash) denies force pushes, remote deletes, `--mirror`,
  `--prune`, `-c alias.*`, pushes to `main` or `master`, and any push not
  spelled `git push ...` at the head of a command (`-C`, `--git-dir`, a path to
  `git`), which the `Bash(git push *)` ask rule and `excludedCommands` would
  otherwise miss. The personal overlay also denies unused tools by bare name
  (`Artifact`, `Workflow`, `ScheduleWakeup`, `SendFeedback` and the deferred
  ones), since a bare deny removes the tool's schema from the request;
  `bin/check-config` fails when an Ollama profile lacks one of those bare
  denies. The personal overlay's sandbox allows the same caches and loopback
  addresses; `bin/check-config` checks they match the Ollama profiles.
- `bin/claude-ollama` resolves its own symlink to find `ollama/`. It unsets
  `ANTHROPIC_API_KEY`, passes `--settings ollama/settings.<size>.json`,
  `--system-prompt-file ollama/system-prompt.md` (replacing Claude Code's
  default system prompt),
  `--append-system-prompt-file ~/.claude-ollama/append-prompt.md` (written each
  launch from `ollama/CLAUDE.local.md`), `--strict-mcp-config` plus an inline
  `--mcp-config` for the code-search server, `--model` with the profile's
  `model` (it also unsets `ANTHROPIC_MODEL`, which would otherwise win over the
  settings file), and restricts tools with `--tools` (built-in tools only; MCP
  tools still load). Before launching, it pulls the base model and creates the
  `-cc` model when `ollama show` can't find the `-cc` model. When the installed
  model's `num_ctx` differs from its Modelfile, it recreates that model `FROM`
  itself with the new `num_ctx` (no pull). `doctor` and `--print-config` are
  dispatched before any pull or launch; `doctor` reads hook names from the
  profile's settings file, not from `~/.claude/hooks`.
- The session config dir `~/.claude-ollama` is `CLAUDE_CONFIG_DIR`:
  `prepare_session_config` seeds `.claude.json` with `hasCompletedOnboarding`
  (an existing file is kept), copies `~/.claude/CLAUDE.md` and
  `~/.claude/skills`, and makes the `tmp` folder that `CLAUDE_CODE_TMPDIR`
  names. `CLAUDE_OLLAMA_CMUX=0` turns the browser tools off; a cmux terminal
  (`CMUX_SOCKET_PATH` set and `cmux` on `PATH`) turns them on. The `dev` server
  drives one cmux browser surface with plain `cmux browser` commands
  (`open-split`, `goto`, `wait`, `console list`, `errors list`,
  `snapshot --interactive`, `click` and friends) in the `claude-ollama` browser
  profile (`profiles list`, else `profiles add`); `page_check` opens only
  loopback URLs, every page tool sends the browser back to the dev server when
  the page left it (`ensure_local`, an error when it will not come back), and
  values go to cmux as `--selector=`/`--text=` so none is read as an option. The
  `repo` server runs `gh` itself (`shared/mcp/github_tools.py`: nine read tools,
  `GH_REPO` from `origin`, or from a `repo` argument that is the origin or a
  line of `~/.config/claude-custom/gh-repos`, `--flag=value` argv, `Refused` for
  bad arguments); its GitHub tools are listed only while `gh` is on `PATH`.
- There is no side model: each Ollama profile sets
  `ANTHROPIC_DEFAULT_HAIKU_MODEL` to its own main model, has no `modelOverrides`
  and no subagent model, and denies `Agent` (it is not in `--tools` either),
  since a subagent would only rerun the main model. Wide searches go through
  `semantic_search` instead (`tool-nudge.py`). Never map a Claude ID to the main
  model in `modelOverrides`: Claude Code then names it after that ID, so the
  banner says Haiku or Sonnet. `bin/check-config` checks all of this.
  `personal/settings.tokens.json` keeps `CLAUDE_CODE_SUBAGENT_MODEL=haiku` with
  `CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1` (Claude Code v2.1.257 or later).
- `bin/claude-ollama` reads the configured sizes from `ollama/` (a
  `settings.<size>.json` plus a `Modelfile.<size>`), never a hardcoded list. A
  first arg that matches launches that size. Otherwise, on a terminal it runs
  `go/cmd/model-picker` (which renders on stderr and prints the chosen size on
  stdout); without one it uses 27b. A first arg that is neither a size nor a
  flag is dropped so it doesn't reach `claude` as a prompt.
- `shared/mcp/dev-server.py` is the `dev` MCP server the Ollama profiles start
  beside `repo`. It reads `.next/dev/lock` (only its port), the dev script's
  port flag and `/_next/mcp` (Next.js 16+), the session's own log, and through
  `lsof` the listening ports of processes whose working folder is inside the
  project folder (those never block `dev_start`); it never trusts a lock's URL.
  It keeps the scheme the server prints (an `https` log line,
  `--experimental-https` in the script, or an `https://` lock `appUrl`), tries
  the other scheme when a candidate does not answer, and probes https with
  certificate checks off, since the host is always `localhost`. `page_check`
  takes `path` on the probed server or `url`, a full `http(s)://` URL on
  `localhost`, `127.0.0.1` or `[::1]` opened without probing. `dev_start`
  launches nothing while the lock's or the requested script's port is held, even
  by a server too busy to answer HTTP; a held framework default doesn't count,
  since the framework moves to the next port. It stops only the servers its
  session started. The read-only tools are allowed by full name
  (`mcp__dev__dev_status`, `dev_logs`, `dev_errors`, `page_check`,
  `page_snapshot`, `page_act`; the page tools run `cmux browser` subcommands
  themselves, never a bare `cmux` command); `dev_start` and `dev_stop` still
  ask, and no bare `mcp__dev` may be allowed. `shared/hooks/dev-server-guard.py`
  (Ollama-only, PreToolUse on Bash) denies `pnpm dev`-style starts and points
  the model at `dev_start`, and denies `open` on a loopback URL and points it at
  `page_check`.
- `shared/mcp/repo-tools.py` is the `repo` MCP server the Ollama profiles start
  beside code-search and allow without a prompt (`mcp__repo` in
  `permissions.allow`; `bin/check-config` checks it and that
  `ollama/CLAUDE.local.md` points the model at it). It runs inside the sandbox.
  `git_status`, `git_diff`, `git_log` and `git_show` run git with `--no-pager`,
  `--no-ext-diff`, `--no-textconv`, no fsmonitor, and revisions after
  `--end-of-options` (paths after `--`), so no argument is read as an option and
  no diff program runs. The server pins the repository it starts in (`GIT_DIR`
  and `GIT_WORK_TREE`), so a `.git` the session plants in a subfolder later,
  with its own config, is never used. Paths must be relative and never climb
  with `..`: two outside paths would make `git diff` compare any files (implicit
  `--no-index`). The nine GitHub tools are listed only when `gh` is on `PATH`
  (`shared/mcp/github_tools.py`). They reach only the project's `origin` and the
  `owner/name` lines of `~/.config/claude-custom/gh-repos` (per machine, beside
  `enabled-tools`; `#` starts a comment; matched case-insensitively; read on
  every call; the sandboxed session cannot write it); any other `repo` is
  `Refused` with the file's path. Output over 20000 characters is cut with a
  note on how to narrow it.
- Drafts: `shared/skills/pr-draft` (a PR description from the project's pull
  request template) and `shared/skills/pr-review-draft` (a review in
  Conventional Comments) save through the `repo` server's `draft_pr` and
  `draft_review` tools (`shared/mcp/draft_store.py`, listed only when
  `CLAUDE_OLLAMA_DRAFTS_DIR` is set) to `~/.claude-ollama/drafts/<id>.json`
  (0700/0600), the one folder both the sandboxed session can write and the
  console can find. They never post. `ollama/drafts/opener.py` runs outside the
  sandbox (`--watch-pid`, `CLAUDE_OLLAMA_OPEN_DRAFTS=0` turns it off) and opens
  the newest new draft, at most one every 5 s, at `/drafts/<id>` through a 0600
  redirect page under the console state dir, so the console token never lands in
  argv; it uses `cmux browser open-split` in a cmux terminal, else `open`, and
  starts `claude-ollama ui` when `/health` fails. The `draft_open` tool asks for
  a page again by writing `<id>.open` beside the draft, which the opener claims;
  the save and open replies carry no link, since the session never holds the
  console token. The console's `/drafts` pages edit each item's markdown, save,
  and post with your own `gh` (`gh pr create`, or `gh api .../pulls/N/reviews`
  with inline comments): the click is the approval. The console derives
  `owner/name` from the project's `origin` (the session can't write
  `.git/config`), never from the draft, and a post carries the draft's hash, so
  a draft changed after you loaded it is refused (409). Tests:
  `ollama/drafts/opener.test.sh` (stub `open`, `cmux`, console),
  `shared/mcp/repo-tools.test.sh`, the console's vitest suite.
- `shared/mcp/code-search.py` is the `semantic_search` MCP server (JSON-RPC over
  stdio, stdlib only). It ranks 40-line chunks by their words (BM25) on every
  search, adds a vector ranking through Ollama `/api/embed` only while
  `GET /api/ps` shows the embedding model loaded, keeps its index in memory and
  reloads `.git/code-search/index.json` when `--index` (the only writer)
  produced a newer one. `claude-ollama` starts `code-search.py --index` in the
  background on launch (`CLAUDE_OLLAMA_NO_INDEX=1` skips it) with
  `--watch-pid $$`, so it stops embedding when the session ends; an `flock` on
  `.git/code-search/index.lock` keeps it to one indexer per repo, and it saves
  the vectors it made when it stops early. `bin/claude-ollama` pulls its model
  (`CODE_SEARCH_MODEL`, default `qwen3-embedding:0.6b`); the model picker's "Set
  up embedding model" row pulls it too. The default name appears once in each of
  `bin/claude-ollama`, `code-search.py` and
  `go/internal/picker/profiles/embedding.go`, and `bin/check-config` checks they
  agree. The Ollama profiles allow the tool in `permissions.allow`.
- `ollama/server.env` documents the Ollama server env the profiles expect,
  including `OLLAMA_MAX_LOADED_MODELS`, which `bin/claude-ollama` reads from the
  running server: at 2 or more (the main and embedding models) it exports
  `CODE_SEARCH_EMBED=1` (the search server then loads and uses the embedding
  model) and warms the model before the indexer; otherwise `semantic_search`
  ranks by words only. `bin/ollama-agent` passes it as `-server-env`, so a new
  LaunchAgent starts from its values. Before each launch `bin/claude-ollama`
  runs `ollama-agent -apply` (`CLAUDE_OLLAMA_AGENT` overrides the command; tests
  stub it) when the running server lacks a value: it merges `server.env` into
  the `local.ollama` plist, stops `brew services ollama` if loaded, reloads, and
  waits for `/api/version`. It refuses while the Ollama app runs
  (`go/internal/agent/apply`). `bin/claude-ollama` sends a background warm-up
  `keep_alive` request to `OLLAMA_HOST` (default `localhost:11434`) before
  `exec claude`.
- `go/internal/agent/` has five packages (`apply` is the `-apply` mode):
  `launchd` (renders and reads the plist, saves atomically, builds the
  `launchctl bootout`/`bootstrap` reload command), `variables` (the known
  `OLLAMA_*` list, the `server.env` parser and `ParseAssignment` for `-set`),
  `snapshot` (the `-json` view: current, recommended and conflicts) and `ui`
  (the Bubble Tea model; `Config.Reload` is injected so tests never call
  launchctl). Saving rewrites the whole plist, so hand edits to keys other than
  `EnvironmentVariables` are lost.
- `ollama/CLAUDE.local.md` is the appended system prompt for every size, for
  small local models, not memory files. Keep it terse: the 27b has a 64k
  context, the other sizes 96k. `ollama/sizes.json` is the single source for
  each size's `context`: `bin/ollama-profiles` writes it to `Modelfile.<size>`
  (`num_ctx`), `CLAUDE_CODE_MAX_CONTEXT_TOKENS`, and the `ollama create` names
  that `model` and the `ANTHROPIC_DEFAULT_*_MODEL` vars refer to. A managed
  `availableModels` that lacks the model makes Claude Code substitute a `[1m]`
  ID, which assumes a 1M window; `claude-ollama doctor` warns when that happens.
  Each profile's own `availableModels` lists only its main model;
  `bin/check-config` checks it. `ollama/system-prompt.md` replaces Claude Code's
  default system prompt for both sizes; keep it short and don't put
  size-specific rules in it.
- The personal overlay is loaded with `--settings` by the `claude` shell
  function (`personal/claude.sh` for bash/zsh/ksh, `personal/claude.fish` for
  fish), wired into rc files by `bin/claude-custom install`, never merged into
  `~/.claude/settings.json`. `--settings` holds one file: a second `--settings`
  replaces the first, so `bin/claude-ollama` launches don't get the personal
  overlay (the Ollama profiles carry their own deny globs and hooks). Top-level
  scalars in the overlay override the user file, so don't add keys to the
  overlay that `~/.claude/settings.json` already sets. Both functions get the
  file from `personal/settings-path`, which drops the bare denies listed in
  `~/.config/claude-custom/enabled-tools` and sets `sandbox.enabled` to false
  when `~/.config/claude-custom/sandbox-off` exists (both per machine, outside
  the repo). The overlay sets `sandbox.enabled` and the ask rule
  `Bash(dangerouslyDisableSandbox:true)`, so every personal session (subagents
  and `--agent pr-review` included) runs Claude's shell commands inside Claude
  Code's sandbox and asks before one runs outside it; `bin/check-config` checks
  both. It lets sandboxed commands write only `~/.cache/claude-sandbox` beyond
  the project and the temp dir, reach loopback addresses, and never read
  `~/.local/share/claude-custom` (the console token); `personal/launch` runs
  `claude` through `shared/sandbox-env` unless `sandbox-off` exists. The Ollama
  profiles use the same sandbox with their own `sandbox` block;
  `claude-ollama qwen` runs Qwen Code inside macOS Seatbelt
  (`ollama/qwen-sandbox.sb`, the same cache folder), and the launcher unsets an
  outer `SANDBOX`, which `advanced.excludedEnvVars` keeps a project `.env` from
  setting.
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

- `go/internal/history` records every write to `~/.claude/settings.json` and the
  `local.ollama` plist before the rename, as `index.jsonl` plus
  `<id>.before`/`<id>.after` in `<state>/history` (0700 folder, 0600 files).
  `CLAUDE_CUSTOM_HISTORY=off` turns it off; the console's History page and
  `/api/history` read the same format, and restore writes the before bytes back.
  The claude-ollama sandbox can't read it, since settings may hold env values.
  Any new writer of a user config should call `history.Record`, not keep its own
  backup. `catalog.Ensure` refetches the tool catalog when it is missing or
  older than seven days.

- The log dir is the contract between `bin/pr-review-local` and `web/console`:
  the events route tails the JSONL logs there, the page binds 127.0.0.1 only,
  and the AI Elements components are vendored in `web/console/src/components`
  (`ui/` and `ai-elements/`).
