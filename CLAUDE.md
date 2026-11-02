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
  The `/profiles` pages drive `GET /api/profiles` and
  `GET`/`PUT /api/profiles/<id>`, which edit
  `$XDG_CONFIG_HOME/claude-custom/profiles/<id>.json` (validated by
  `web/console/src/lib/profile-rules.ts`; an empty PUT deletes the file). The
  `/workspaces` page drives `GET`/`PUT /api/workspaces`
  (`web/console/src/lib/workspaces.ts`): it lists the `projects` of the
  launcher's `~/.claude-ollama/.claude.json` with `hasTrustDialogAccepted` and
  each folder's `.claude/skills`, and a PUT of `{path, trusted}` sets that flag
  (a new folder must exist and is keyed by its real path), recorded in history.
  `POST /api/workspaces/check` (`web/console/src/lib/skill-check.ts`) runs
  `bin/skill-check --size SIZE FOLDER` for a recorded, trusted folder (a print
  mode session runs the folder's hooks without the dialog), which starts
  `claude-ollama` there in print mode, reads the `init` event's `skills`, stops
  the launch and prints JSON (`claude_version`, `skills`, `error`); the page
  names the folder's skills missing from that array. Tests:
  `bin/skill-check.test.sh` (stub launcher and `claude`).
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
  file's tests (`X.test.sh` beside `X`, mappings in the script; a `go/` file
  adds `test-go`, a `web/console/` file adds `test-web`; a `Makefile` edit runs
  `make test`). Its tests: `.claude/verify.test.sh`
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
  skipped, unpinned; exit 1 when one is behind or unpinned; a behind or unpinned
  line is followed by a `fix:` line naming `bin/model-upgrade SIZE` for a size's
  base or `bin/ollama-models pin NAME` otherwise, and a count line ends the
  listing when something needs a fix), removes third-party and orphan `-cc`
  models after asking (`prune --yes --only NAME...` removes just the named
  models that are still prunable, for the console's Models page), and writes a
  registry manifest sha256 to `ollama/model-digests.json`; tests:
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
- Sync check: `claude-custom sync-check [--write] [--against FILE]` prints the
  local fingerprint summary, one `section: <short>` line each (`commit`,
  `dirty`, `claude_version`, `models`, `server_env`, `hooks`, `sandbox`,
  `fingerprint`), then the sections that differ from the beacon at
  `${XDG_CONFIG_HOME:-~/.config}/claude-custom/beacon.json` (or
  `--against FILE`) as `section: local X vs beacon Y (<host>, <age>)`, with each
  changed model digest and hook name spelled out; exit 0 when equal, 1 when
  different, 2 without a beacon. `--write` writes that beacon (0600) for you to
  copy to the other machine. `bin/sync-fingerprint` prints the JSON
  (`--out FILE` writes it 0600 in a 0700 folder, `--summary FILE` and
  `--age FILE` read one back); tests: `bin/sync-fingerprint.test.sh` (stub
  `curl`, `pgrep`, `ps`, `claude`, temp git repo) and
  `bin/claude-ollama.test.sh` for `sync-check`, the launch beacon and doctor's
  beacon line
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
  ruff, shellcheck and `bash -n` from PATH, and rejects newly added comments.
  For a `.ts`/`.tsx` file in a package with a `tsconfig.json` and
  `node_modules/.bin/tsc` it also runs `tsc --noEmit` and keeps only the lines
  about the edited file, so an unknown name or member fails the edit that wrote
  it while errors elsewhere never block. It caches passes by content hash under
  `~/.cache/claude-custom/edit-check` (`EDIT_CHECK_CACHE_DIR` overrides).
  `shared/hooks/stop-verify.py` also runs on PostToolUse Edit/Write/MultiEdit,
  where it appends the edited path to a per-session log under
  `~/.cache/claude-custom/edited-files` (`STOP_VERIFY_STATE_DIR` overrides). On
  Stop it does nothing unless that log has files inside the project. Otherwise
  it runs `fallow audit` on each edited JS/TS file in JS/TS projects and the
  project's `.claude/verify` with the edited files as arguments, falling back to
  `make test`, `go test ./...` or `pnpm test` when none exists (an empty
  `.claude/no-verify` opts out). A pass clears the log; a failure keeps it. Its
  message lists one line per new fallow finding in the edited files (at most 20;
  fallow tool errors don't block) and keeps a failing command's error lines plus
  a 15-line tail, each line clipped to 300 characters. It blocks once per turn
  (`stop_hook_active`). Both exit 2 so the model sees stderr.
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
- `shared/skills/find-docs/SKILL.md` is the `/find-docs` skill: current library
  docs from Context7 through its CLI (`claude-custom ctx7 library`, then
  `claude-custom ctx7 docs`), adapted from the upstream skill pinned in
  `shared/skills/find-docs/UPSTREAM`. `bin/claude-custom install` links it into
  `~/.claude/skills/` and `claude-ollama` copies it into its session. The skill
  runs the CLI through `claude-custom ctx7 library|docs ...` (at most 80 lines,
  every other ctx7 command refused). Both overlays run `claude-custom ctx7 *`
  outside the sandbox (`excludedCommands`) and allow it without a prompt
  (`permissions.allow`), so it uses your own network, proxy, certificates and
  `~/.config/context7` (a `ctx7 login` or `CONTEXT7_API_KEY` raises the quota);
  the Qwen Seatbelt profile still hides that folder. An exclusion applies only
  when every segment of the command line matches, so the skill runs it as one
  plain command with no pipe. Because it runs unsandboxed, the wrapper never
  lets `npx` resolve `ctx7` from the project or the sandbox's npm cache, which
  the session can write: it runs from `$HOME/.cache/claude-custom/ctx7` (never
  an environment variable; no sandbox may write it) with `--prefix` and
  `--cache` pinned there, and where that folder cannot be written (under
  Seatbelt, or inside the sandbox) it runs from a fresh temp folder as
  `--prefix` instead, never the working folder. Claude Code itself keeps the
  `claude-custom ctx7 *` exemption narrow: a pipe or `;` segment that does not
  match sends the line back into the sandbox, and a file redirect or command
  substitution still prompts. The CLI version is pinned once, as `ctx7_version`
  in `bin/claude-custom`; `bin/check-config` checks the wrapper, the prompt
  files and both overlays, checks the link, and that `PREFERENCES.md`,
  `CLAUDE.local.md` and `QWEN.local.md` name the skill.
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
- Mockup spike: `claude-ollama mock-spike [size] [--runs N] [--brief NAME]...`
  (`bin/mock-spike --model M [--base-url URL] [--out FILE]`) streams three
  mockup briefs through Ollama `/api/chat` with the json-render catalog prompt
  from `web/console/src/lib/mock-spike/catalog.ts`, scores each reply (patch
  lines, elements, catalog validation, first-patch time) with
  `web/console/src/lib/mock-spike/score.ts`, prints a `verdict:` line (`sound`,
  `repairable`, `poor`) and saves `~/bench-results/mock-spike-*.json`. The CLI
  is `web/console/scripts/mock-spike.mts`, run through the console's `tsx` so
  any Node the console supports works; the wrapper installs the console's
  packages when they are missing. Tests: `bin/mock-spike.test.sh` (stub node and
  pnpm) and the console's vitest suite. The console's `/mockups` page renders
  the newest report's specs with json-render
  (`web/console/src/lib/mock-spike/registry.tsx` maps the catalog to plain
  primitives inside `MockFrame`, whose `.mock-frame` block in `globals.css`
  carries its own neutral palette and font, so a mockup never takes the
  console's theme) and shows each run's structural and prop issues; `reports.ts`
  rescores every reply, so stored scores are never trusted. The page also starts
  the spike through `console-run` (the `mock-spike` entry in
  `console-commands.ts`, size param), lists its runs, and names the folder it
  reads with every `mock-spike-*.json` found and why any was skipped. The spike
  prints a `=== run N/M brief` marker before each run and every reply line as it
  completes, so the run page (`live-mock-sheet.tsx`, through `RunView` for the
  `mock-spike` command) and the Mockups page's "Streaming now" section compile
  the patches after each marker with `lib/mock-spike/live.ts` and render each
  cell while the model is still writing. The prompt also carries
  `lib/mock-spike/design-rules.ts` (a dozen hierarchy, grouping and content
  rules) and one style paragraph from the preset chosen with `--preset ID`
  (`lib/mock-spike/presets.ts`: `calm-saas` default, `dense-admin`, `editorial`,
  `playful`, `brutalist`); the spike prints `preset: ID` and stores it in the
  report, and each preset's `--mock-*` palette lives in `globals.css` as
  `.mock-frame[data-preset=ID]`, since no TS file may hold a raw colour. The
  Mockups run card has a Preset select.
- `shared/hooks/tool-nudge.py` is wired only in the Ollama profiles
  (UserPromptSubmit resets its per-session state under
  `${CLAUDE_CONFIG_DIR:-~/.claude}/cache/tool-nudge/`). As PreToolUse on Bash
  and `mcp__code-search__semantic_search` it denies every Bash command that runs
  a text search (`grep`, `rg`, `ag`, `ack`, `git grep`, or `find` with a name or
  path filter) at the head of any command in it, until the MCP tool has been
  called in the turn. A search after a pipe is a filter and passes. Calling the
  tool unlocks text search for the turn even when it errors, so a dead server
  can't lock the model out. As PreToolUse on Read, Skill and Bash it also denies
  reading, listing or searching inside `node_modules` until the `find-docs`
  skill or a `ctx7` command ran in the turn (Next's generated `AGENTS.md` sends
  models to `node_modules/next/dist/docs` otherwise); a package's own
  `node_modules/<name>/package.json` is an install check, not docs, and always
  passes. The profiles allow `Skill(find-docs)` without a prompt;
  `bin/check-config` checks it.
- `shared/hooks/tdd-guard.py` enforces the TDD rule in both overlays. As
  PreToolUse on Edit, Write and MultiEdit it denies an edit to a code file (by
  suffix, or a shebang) that is not itself a test until, in this session, a test
  file in the same scope (the directory, or the nearest `package.json` root for
  JS/TS) was edited and a test command ran after that edit (`go test`,
  `make test*`/`check*`, `pnpm|npm|yarn|bun test`, `vitest`, `pytest`,
  `X.test.sh`, `.claude/verify`, as any segment of the command). As PostToolUse
  on the same tools and on Bash it records those events under
  `${CLAUDE_CONFIG_DIR:-~/.claude}/cache/tdd-guard/`. Editing the test again
  relocks the scope until the next run. The third denial of the same file in a
  row passes and is logged as `allow-after-strikes`; any test edit or run resets
  that count. Test files, files under `test`, `tests`, `__tests__`, `testdata`,
  `fixtures`, `eval` or `.claude`, and non-code files always pass.
  `CLAUDE_CUSTOM_TDD=0` turns it off. Tests: `shared/hooks/tdd-guard.test.sh`.
- `shared/hooks/friction_budget.py` is the friction budget the efficiency guards
  share (`bash-output-guard.py`, `read-range-guard.py`, `tool-nudge.py`; never
  the safety guards or `tdd-guard.py`, which has its own strikes). Each of them
  passes its denial through `deny_reason(hook, event, reason, alternative)`,
  which keys it by hook, tool and a fingerprint (Bash: the command minus digits,
  quoted strings and each path's last segment; Read: the path plus a 300-line
  bucket of `offset` and `limit`; otherwise the sorted input JSON) and counts it
  in `${CLAUDE_CONFIG_DIR:-~/.claude}/cache/friction/<session_id>.json`. The
  first three denials of one fingerprint keep their reason; the fourth and later
  get a plan reset instead (one line naming what the model keeps trying, the
  hook's one allowed alternative, and an order to stop retrying) and write a
  `"kind": "friction"` telemetry line with the fingerprint's hash, never the
  command. As a UserPromptSubmit hook (Ollama-only, in
  `ollama/hooks.extra.json`) it resets that file each turn; without that reset
  (the personal overlay) the file never exists and every denial stays plain.
  `CLAUDE_CUSTOM_FRICTION=0` turns it off. `shared/hooks/repeat-call-cache.py`
  (Ollama-only, PreToolUse and PostToolUse on Read, `mcp__repo__git_status` and
  `mcp__code-search__semantic_search`) keeps a per-turn result cache in the same
  file: after a call it records the call number, the output's sha256 and size,
  and an invalidation stamp (the file's mtime for Read, `HEAD` plus the index
  mtime for `git_status`, none for a search); an error result (`Error` text or
  an error flag) is never recorded. Before an exact same-turn repeat whose stamp
  is unchanged it denies with
  `same result as call #N this turn, unchanged since; use it` and writes a
  friction line carrying `saved_bytes`. A Read's served content (64 KiB or less)
  is also kept as a 0600 snapshot under `cache/friction/<session_id>.snapshots/`
  (stale ones pruned at each record). When the same Read repeats after the
  file's mtime changed, the hook diffs the snapshot against the file: identical
  content is the same denial; otherwise it rewrites the call through
  `updatedInput` (`permissionDecision: allow`) to the changed span plus 3 lines
  of margin, at most 300 lines, with `additionalContext`
  `lines A-B changed since call #N; showing only them` (or
  `showing only A-C (read on from C+1 for the rest)` when cut); a file with no
  snapshot passes through whole. Recovery recipes are data:
  `ollama/recipes/<hook>.json` holds `{"match": regex, "steps": [...]}` entries
  for `bash-output-guard`, `read-range-guard`, `tool-nudge` and `tdd-guard`;
  `shared/hooks/recovery_recipes.py` appends the first match's steps (numbered,
  at most 3, `Recovery: 1. ...; 2. ...`) to the plan-reset line, and
  `tdd-guard.py` appends them to the `additionalContext` it returns on the
  strike that lets an edit through (naming the expected test file). An unmatched
  reason gets no steps. `bin/check-config` validates every recipe file (hook
  exists, regex compiles, one to three non-empty steps) and fails when an Ollama
  profile lacks either hook. `bin/tool-telemetry-report` prints a friction
  section (trips per hook, cache hits, bytes saved) and a `guards` table
  (denials, trips and trips per 100 denials per hook) ending in `lint:` lines: a
  hook over 20 trips per 100 denials across 30 or more denials is
  `lint: <hook>: message unclear or rule too strict: <most common reason>`, else
  `lint: none flagged`. `claude-ollama doctor` runs that report on the session's
  telemetry log when it exists and prints `ok   guards: none flagged` or one
  `warn guards: <hook>: <lint text>` per flagged hook. Tests:
  `shared/hooks/friction_budget.test.sh`,
  `shared/hooks/repeat-call-cache.test.sh`, `shared/hooks/tdd-guard.test.sh`,
  `bin/tool-telemetry-report.test.sh`, `bin/claude-ollama.test.sh` and the three
  guards' tests.
- `shared/hooks/name-nudge.py` is wired only in the Ollama profiles, as
  PreToolUse on Edit, Write and MultiEdit. It never denies: when the written
  text declares a placeholder name (`tmp`, `data2`, `obj`, `handleStuff`, a
  `Helper`/`Utils` suffix) or a Write names a code file that way (`utils.ts`,
  `misc.py`), it returns one `additionalContext` line asking for a name that
  says what the thing holds or does. Only code files count (by suffix, or a
  shebang for an extensionless one). Tests: `shared/hooks/name-nudge.test.sh`.
- `shared/hooks/context-budget.py` and `shared/hooks/handoff-relaunch.py`
  (Ollama-only, in `ollama/hooks.extra.json`) chain short sessions through
  `/handoff` instead of letting the small model compact. The first is a
  PostToolUse hook on every tool: it sums the last assistant `usage` in the
  event's `transcript_path` (`input_tokens` plus both cache counts), and at
  `CLAUDE_OLLAMA_HANDOFF_PCT` (default 70) of `CLAUDE_CODE_MAX_CONTEXT_TOKENS`
  (silent when unset) adds one `additionalContext` per session telling the model
  to finish its edit, call `Skill handoff save` and stop; the state file is
  `${CLAUDE_CONFIG_DIR:-~/.claude}/cache/context-budget/<session_id>.json`
  (`nudged_at`), and each nudge is one `"kind": "budget"` telemetry line
  (`hook_telemetry.record_hook_event`). The second is a Stop hook with
  `CLAUDE_OLLAMA_RELAUNCH_DIR` set and that state nudged but not relaunched.
  Without a note in `<git common dir>/handoff/` (from the event's `cwd`) newer
  than the nudge it blocks the stop once
  (`{"decision":"block","reason": "Context budget at N%: call the handoff skill with save now, then stop."}`,
  `blocked_once` in the state; never when `stop_hook_active` is true), then
  stays silent. With a fresh note it writes
  `{"note": path, "prompt": text, "percent": N}` to
  `$CLAUDE_OLLAMA_RELAUNCH_DIR/relaunch`, marks the state `relaunched` and sends
  SIGTERM to the pid in `claude.pid` there, only when `ps -o comm=` names a node
  or claude process; it never exits 2. The prompt is the newest `type: user`
  transcript line whose `message.content` is a string or only `text` blocks,
  skipping text starting with `/`, `<system-reminder>` or `<local-command` and
  empty text, newlines collapsed and clipped to 200 characters (`""` when none);
  `handoff-relaunch.py --inspect TRANSCRIPT` prints it. `bin/claude-ollama`
  (`launch_claude`) exports that dir as
  `~/.claude-ollama/relaunch/<launcher pid>` (0700, removed by its EXIT trap;
  `prepare_relaunch_dir` removes sibling dirs whose pid no longer runs), runs
  `claude` in the background with the tty's stdin, writes `claude.pid`, forwards
  SIGINT/SIGTERM and waits; while the sentinel exists it reads it with jq,
  removes it, prints
  `context budget reached at N%: handoff saved, resuming "<prompt>"`
  (`relaunching claude` without one), appends a `relaunched` incident (`detail`
  the note, `tokens` the percent of the profile's
  `CLAUDE_CODE_MAX_CONTEXT_TOKENS`) to `$CLAUDE_OLLAMA_INCIDENTS_FILE` when it
  is set and its folder exists, and runs `claude` again with the same flags, a
  trailing prompt (a last argument that neither starts with `-` nor follows a
  flag) replaced by one word, `/handoff <prompt>`, or `/handoff` when the prompt
  is empty or starts with `-`. Without a sentinel it exits with claude's status;
  `CLAUDE_OLLAMA_RELAUNCH=0` keeps the single `exec`. `bin/check-config` fails
  when a profile lacks either hook. Tests:
  `shared/hooks/context-budget.test.sh`, `shared/hooks/handoff-relaunch.test.sh`
  (stub `ps`, a sleeping process, an inline transcript),
  `bin/claude-ollama.test.sh` (`STUB_CLAUDE_RELAUNCH_ONCE`,
  `STUB_CLAUDE_RELAUNCH_PROMPT`).
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
  writable. It also sets `NODE_USE_ENV_PROXY=1`, since Node's `fetch` (a
  sandboxed `npx`, for one) otherwise ignores the sandbox's `HTTPS_PROXY` and
  every request fails. `bin/check-config` asserts the block's exact values, and
  a misspelled key is silently ignored, so the check must change with the block.
  The profiles set `sandbox.enabled` and `autoAllowBashIfSandboxed: true`, so
  sandboxed commands run without a prompt (a skill's `!` commands included);
  `excludedCommands` (`cmux`, `gh`, `short`, `git push`, `claude-custom ctx7`)
  run outside the sandbox, each after the `Bash` prompt except the allowed
  `ctx7`, and `permissions.ask` holds only `Bash(git commit *)`,
  `Bash(git push *)` and `Bash(dangerouslyDisableSandbox:true)`;
  `bin/check-config` checks both. The profiles also set `CLAUDE_CODE_EXTRA_BODY`
  to `{"thinking":{"type":"disabled"}}` so Ollama skips reasoning;
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
- `bin/sync-fingerprint` (bash 3.2, jq) says what a checkout runs: `commit`
  (HEAD of `repo_dir`), `dirty` (tracked changes only), `models` (per size the
  `-cc` model's `/api/tags` digest or `missing`, plus the base's pin state as
  doctor sees it: `ok`, `mismatch`, `missing`, `unpinned`), `server_env` (the
  running server's `OLLAMA_*` values, read like doctor does; `{}` when down),
  `hooks` (sha256 per `shared/hooks/*.py` and `*.sh`, by basename, `*.test.sh`
  left out), `sandbox` (sha256 of the rendered `sandbox` block of
  `ollama/settings.27b.json`), `claude_version` (first line of
  `claude --version`, else null), `host`, `ts`, and `fingerprint`, the sha256 of
  the canonical JSON (`jq -cS`) of everything but `host` and `ts`. Every
  `bin/claude-ollama` launch writes it to
  `$CLAUDE_CONSOLE_STATE_DIR/beacon/<host>.json` (0700 folder, 0600 file) in the
  background before the hand-off (`CLAUDE_OLLAMA_BEACON=0` skips it), and
  `claude-custom install` (so `update`, through `finish-update`) refreshes it.
  `claude-ollama doctor` prints `ok   beacon: <age> ago, commit matches`,
  `warn beacon: stale, commit X vs HEAD Y: run claude-custom update` or
  `warn beacon: none yet`; it never fails doctor. `claude-custom sync-check`
  compares sections by canonical JSON, not by the stored `fingerprint`, so a
  hand-edited beacon still diffs. Nothing is sent over the network.
- `bin/claude-ollama` resolves its own symlink to find `ollama/`. It unsets
  `ANTHROPIC_API_KEY`, passes `--settings ollama/settings.<size>.json`,
  `--system-prompt-file ollama/system-prompt.md` (replacing Claude Code's
  default system prompt),
  `--append-system-prompt-file ~/.claude-ollama/append-prompt.md` (written each
  launch from `ollama/CLAUDE.local.md`, plus `ollama/CLAUDE.cmux.md` in a cmux
  terminal unless `CLAUDE_OLLAMA_CMUX=0`), `--strict-mcp-config` plus an inline
  `--mcp-config` for the code-search server, `--model` with the profile's
  `model` (it also unsets `ANTHROPIC_MODEL`, which would otherwise win over the
  settings file), and restricts tools with `--tools` (built-in tools only; MCP
  tools still load). Before launching, it pulls the base model and creates the
  `-cc` model when `ollama show` can't find the `-cc` model. When the installed
  model's `num_ctx` or a sampling parameter differs from its Modelfile, it
  recreates that model `FROM` itself with every Modelfile `PARAMETER` (no pull).
  `doctor` and `--print-config` are dispatched before any pull or launch;
  `doctor` reads hook names from the profile's settings file, not from
  `~/.claude/hooks`.
- The session config dir `~/.claude-ollama` is `CLAUDE_CONFIG_DIR`:
  `prepare_session_config` seeds `.claude.json` with `hasCompletedOnboarding`
  (an existing file is kept), copies `~/.claude/CLAUDE.md` and
  `~/.claude/skills`, adds the skills in `ollama/skills/` (Matt Pocock's, pinned
  in `ollama/skills/UPSTREAM`, minus `chief-of-staff`, `claude-handoff`,
  `code-review`, `implement-spec` and `research`, which need subagents or the
  web, plus cmux's `cmux-markdown`, pinned in
  `ollama/skills/cmux-markdown/UPSTREAM`; a skill of yours with the same name
  wins, and plugins never load in this session), and makes the `tmp` folder that
  `CLAUDE_CODE_TMPDIR` names. `ollama/CLAUDE.cmux.md` tells the model to open
  every markdown file it writes with `/cmux-markdown`; `bin/check-config` checks
  it names the skill and that the launcher appends it only with the cmux tools
  on. `CLAUDE_OLLAMA_CMUX=0` turns the browser tools off; a cmux terminal
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
  beside `repo`. It finds app dirs by walking the tree for `package.json` files
  with a `dev` or `start` script (skipping hidden folders, symlinks and
  `node_modules`, never through git, so an untracked app counts), reads
  `.next/dev/lock` (only its port), the dev script's port flag and `/_next/mcp`
  (Next.js 16+), the session's own log, and through `lsof` the listening ports
  of processes whose working folder is inside the project folder (those never
  block `dev_start`); it never trusts a lock's URL. It keeps the scheme the
  server prints (an `https` log line, `--experimental-https` in the script, or
  an `https://` lock `appUrl`), tries the other scheme when a candidate does not
  answer, and probes https with certificate checks off, since the host is always
  `localhost`. `page_check` takes `path` on the probed server or `url`, a full
  `http(s)://` URL on `localhost`, `127.0.0.1` or `[::1]` opened without
  probing. `dev_start` launches nothing while the lock's or the requested
  script's port is held, even by a server too busy to answer HTTP; a held
  framework default doesn't count, since the framework moves to the next port.
  It stops only the servers its session started. `dev_deps` reports whether a
  package dir's `node_modules` is installed and newer than its lockfile and the
  installed version of each named package (default: every dependency in
  `package.json`), read from `node_modules/<name>/package.json` in the dir and
  its parents, so the model never lists `node_modules`. `dev_install` runs the
  lockfile's package manager (`pnpm`, `yarn`, `bun`, else `npm`) in any package
  dir outside `node_modules`, tracked or not: `install` with no packages, else
  `add` (npm: `install`) of the named packages (`dev: true` for devDependencies;
  names must match a package spec, never an option), outside the Bash sandbox
  like `dev_start`, and returns the result plus `dev_deps` for them. The
  read-only tools are allowed by full name (`mcp__dev__dev_status`, `dev_logs`,
  `dev_errors`, `dev_deps`, `page_check`, `page_snapshot`, `page_act`; the page
  tools run `cmux browser` subcommands themselves, never a bare `cmux` command);
  `dev_start`, `dev_stop` and `dev_install` still ask, and no bare `mcp__dev`
  may be allowed. `shared/hooks/dev-server-guard.py` (Ollama-only, PreToolUse on
  Bash) denies `pnpm dev`-style starts and points the model at `dev_start`,
  denies `open` on a loopback URL and points it at `page_check`, and denies a
  `pnpm` that shares its line with `cd &&`, a pipe or `;`, since `pnpm *` is an
  `excludedCommands` entry and only a one-segment line leaves the sandbox.
  Inside the sandbox pnpm's hardlinks hit EPERM and corrupt the virtual store,
  so Bash `pnpm -C DIR install|add|test` runs outside it after the Bash prompt;
  `dev_install` stays as the tool form, and `pnpm exec`, `dlx`, `x` and `create`
  are denied so no arbitrary package runs unsandboxed.
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
- Incidents: `ollama/incidents/watcher.py` (stdlib only) runs outside the
  sandbox beside the draft opener (`--watch-pid $$`, `CLAUDE_OLLAMA_INCIDENTS=0`
  turns it off, `CLAUDE_OLLAMA_INCIDENT_WATCHER` overrides the script for
  tests). It follows the Ollama server log (`server_log_path`) from its end,
  reopening when the file shrinks, and the session's transcripts under
  `~/.claude-ollama/projects` for new `compact_boundary` lines, and classifies
  each new line with an ordered regex table into `aborted` (`context canceled`),
  `evicted` (an unload or a runner start), `truncated`
  (`truncating input prompt`), `reprefilled` (a llama.cpp
  `prompt eval time ... / N tokens` count within 300 tokens of `n_ctx` or of the
  previous `total time ... / N tokens`), `compacted` (with `preTokens`) or
  `unknown` (a line naming the model or a runner that fits no rule, never
  dropped); the rest of a load sequence (`loaded runners`, `template selection`)
  is skipped. Each rule has an id (`aborted/context-canceled`,
  `truncated/input-prompt`, `evicted/unload`, `evicted/runner-start`,
  `ignored/load-sequence`, `reprefilled/prompt-eval`, `compacted/transcript`).
  Each incident is one JSON line (`ts`, `cause`, `detail` of 200 chars,
  `tokens`, `rule`, null for `unknown`) appended to
  `$CLAUDE_CONSOLE_STATE_DIR/incidents/<utc-time>-<pid>.jsonl` (0700/0600), the
  newest also in `<file>.latest`, and `incidents/current` names the running
  session's file. A `reprefilled` row also carries `preceded_by`, the last
  `{kind, ts}` event seen in the log before it (`embed`: an `/api/embed`
  request; `load`: a runner start; `unload`; `expired`: a keep-alive expiry), or
  null; no other cause has the key. The watcher counts hits per rule, the
  `unmatched` lines (the `unknown` rows) and the log lines seen, and appends a
  `{"kind": "health", "ts", "rules", "unmatched", "lines"}` row (never to
  `.latest`) every 60 s in follow mode (`--health-interval`) and once at exit
  and in `--once`; every reader skips rows with a `kind`.
  `watcher.py --check-rules --log PATH [--model NAME] [--lines N]` (default 400)
  replays the log's last lines, prints each rule id with its hits, then `blind`
  (exit 1: 50 or more lines name the model or a runner and no rule matched) or
  `ok`; `claude-ollama doctor` runs it as `check_classifier` on
  `server_log_path` and fails when the classifier is blind (`rules: N` counts
  the rules that hit). The launcher exports `CLAUDE_OLLAMA_INCIDENTS_FILE` to
  the session, and `shared/hooks/incident-note.py` (UserPromptSubmit, in
  `ollama/hooks.extra.json` after `tool-nudge.py`; `bin/check-config` fails when
  an Ollama profile lacks it) adds one `additionalContext` line naming the last
  incident and the counts per cause when new ones appeared, remembering the
  reported count under `${CLAUDE_CONFIG_DIR:-~/.claude}/cache/incident-note/`.
  The console's Logs page has an Incidents tab (`source=incidents` on
  `/api/logs/path` and `/api/logs/events`, which read only the file
  `incidents/current` names inside that folder) with a count per cause and a
  classifier-health pill from the latest health row (`saw N lines, M unmatched`
  or `no health row yet`) above the lines; each line shows the preceding event
  and rule as sub-labels (`reprefilled · after embed · reprefilled/prompt-eval`;
  `web/console/src/lib/incidents.ts`: `parseIncident`, `parseHealth`,
  `latestHealth`). Tests: `ollama/incidents/watcher.test.sh`
  (`fixtures/server-log.txt` covers every cause and passes `--check-rules`),
  `shared/hooks/incident-note.test.sh`, `bin/claude-ollama.test.sh` (stub
  watcher; doctor runs the real one on a stub log), the console's vitest suite.
- Messages proxy:
  `bin/messages-proxy --upstream URL --port N --log FILE [--port-file PATH] [--watch-pid PID]`
  (stdlib only) listens on `127.0.0.1:N` (`0` picks a free port and
  `--port-file` publishes it, 0600) and forwards `POST /v1/messages`,
  `GET /v1/models`, `/api/version` and `/api/tags` to Ollama unchanged (404 for
  any other route), SSE streamed back as it arrives; it exits when the watched
  pid dies. It answers 403 when the `Host` is not `127.0.0.1`, `localhost` or
  `[::1]` (any port) or an `Origin` is not a loopback origin, and forwards the
  original `Origin` so Ollama's own check still runs, since the proxy rewrites
  `Host` to the upstream. For each `POST /v1/messages` it hashes the body's
  sections in order (`system`, `tools`, each `messages` entry, each as
  `json.dumps(sort_keys=True, separators=(",", ":"))`) as cumulative sha256
  prefixes, compares them with the previous request's and appends one JSON line
  to `--log` (0700 dir, 0600 file): `ts`, `request_id` (uuid4, also sent
  upstream as `X-Claude-Ollama-Request`), `sections`, `stable_sections`,
  `diverged_at` (`system`, `tools`, `message:N` or null), `offset` (byte within
  that section's canonical text), `diff` (at most 200 chars from there) and
  `prompt_bytes`; nothing else of the body is logged. `bin/claude-ollama` starts
  it before `launch_claude` unless `CLAUDE_OLLAMA_PROXY=0`
  (`CLAUDE_OLLAMA_PROXY_BIN` overrides the script; tests stub it), with
  `--watch-pid $$`, the log at `$CLAUDE_CONSOLE_STATE_DIR/proxy/requests.jsonl`
  when that dir exists, else `~/.claude-ollama/proxy/requests.jsonl`, waits for
  the port file and writes `~/.claude-ollama/proxy-settings.json` with
  `env.ANTHROPIC_BASE_URL` pointed at the proxy (the settings file `claude`
  gets); when the port never appears it warns and keeps the direct URL. It only
  observes: no rewriting, no tool pruning. Tests: `bin/messages-proxy.test.sh`
  (stub upstream), `bin/claude-ollama.test.sh` (stub proxy).
- Residency lease: `bin/ollama-lease` (bash 3.2, `jq`) keeps one file per
  holder, `<pid>.json` with `{name, model, num_ctx, rung, started}`, under
  `${CLAUDE_OLLAMA_LEASE_DIR:-~/.claude-ollama/lease}` (0700/0600), guarded by a
  `lease.lock` directory taken with `mkdir` (macOS has no `flock` command; a
  lock older than a minute is removed). Every call removes the files whose pid
  is dead.
  `acquire NAME [--model M] [--pid N] [--num-ctx N] [--rung R] [--exclusive] [--wait SECONDS]`
  succeeds at once when no `session` lease is held by another pid, or when the
  running server's `OLLAMA_MAX_LOADED_MODELS` (read like `claude-ollama` does)
  is at least the number of distinct models the holders plus the request would
  load; otherwise it exits 3 with one stderr line,
  `ollama lease: held by <name> (pid N, model M); run after that session ends or set OLLAMA_MAX_LOADED_MODELS=2`,
  after polling every `CLAUDE_OLLAMA_LEASE_POLL` seconds (default 1) for
  `--wait`. `--exclusive` refuses while any other holder exists.
  `release NAME [--pid N]` removes that pid's file, `holders` prints
  `live NAME pid N model M rung R` or `stale NAME pid N model M` (and removes
  the stale file), and
  `heartbeat --watch-pid N [--model M] [--fast-marker FILE]` sends a
  `keep_alive` generate request for the leased model every
  `${CLAUDE_OLLAMA_LEASE_HEARTBEAT:-120}` seconds (halved while the marker
  exists) until the pid dies. `bin/claude-ollama` acquires `session` (model,
  `num_ctx`) right after the model checks and before the indexer, so the
  indexer's `embedding` lease (held by the `sh -c` pid that execs
  `code-search.py --index`; a refusal sets `CODE_SEARCH_EMBED=0`, words only)
  never crowds the session out; `launch_claude` starts the heartbeat and the
  EXIT trap (`end_launch`) stops it, releases the lease and removes the relaunch
  dir. `review` and `mock-spike` acquire their own names with the size's model,
  `speed-check` and `thinking-check` acquire `--exclusive`, and each exits 3 on
  a refusal. `CLAUDE_OLLAMA_LEASE=0` turns all of it off;
  `CLAUDE_OLLAMA_LEASE_BIN` overrides the script for tests. `doctor` prints
  `ok   lease held by NAME (pid N, model M)`,
  `warn stale lease NAME (pid N) removed` or `ok   no lease holders`. Tests:
  `bin/ollama-lease.test.sh` (stub `pgrep`, `ps`, `curl`, sleeping pids),
  `bin/claude-ollama.test.sh`.
- Degrade ladder: `ollama/incidents/ladder.py` (stdlib only; it imports
  `FileTail`, `IncidentLog`, `process_alive` and `now_iso` from `watcher.py`)
  runs outside the sandbox beside the watcher (`launch_claude` starts it after
  `prepare_relaunch_dir` with
  `--incidents $CLAUDE_OLLAMA_INCIDENTS_FILE --relaunch-dir DIR --watch-pid $$ --context NUM_CTX`;
  `CLAUDE_OLLAMA_LADDER=0` turns it off, `CLAUDE_OLLAMA_LADDER_BIN` overrides it
  for tests; `bin/check-config` fails when the launcher stops starting it). It
  follows the session's incidents file from its start and binds each rung to
  evidence, at most once per session: three `reprefilled` rows whose
  `preceded_by.kind` is `embed` within 10 minutes fire `embeddings-off` (touches
  `$CLAUDE_OLLAMA_RELAUNCH_DIR/embed-off`); three after `expired` fire
  `heartbeat` (touches `heartbeat-fast`, which halves the lease heartbeat
  interval); three `truncated` rows fire `context-down` (writes `ladder` as
  `{"rung", "context", "reason"}`, the context being the next lower size in
  `ollama/sizes.json` or 75% of the current rounded down to 1024 and never below
  16384, then sends SIGTERM to the pid in `claude.pid` only when `ps -o comm=`
  names a node or claude process, like `handoff-relaunch.py`). A fired rung
  appends a `degraded` incident (`detail: "<rung>: <reason>"`,
  `rule: "ladder/<rung>"`, also to `.latest`); a row no rung is bound to only
  appends `{"kind": "ladder", "ts", "note": "<cause> after <kind>: no rung"}`
  once per note. `ladder.py --inspect FILE` prints the `<rung>: <reason>` lines
  an incidents file would fire, or `none`. The launcher's relaunch loop also
  wakes on a `ladder` file: it prints `claude-ollama: ladder <rung>: <reason>`,
  writes `~/.claude-ollama/ladder-profile.json` (the size's profile plus
  `context`) through `shared/profile-overlay settings` into
  `ladder-settings.json`, so `CLAUDE_CODE_MAX_CONTEXT_TOKENS` keeps the headroom
  margin, re-acquires the session lease with `--rung`, and runs `claude` again
  with the same flags, a trailing prompt dropped and `--continue` added; a
  handoff sentinel in the same pass still wins the arguments. Every relaunch
  exports `CODE_SEARCH_EMBED=0` while `embed-off` exists, and `code-search.py`
  itself answers words only while that file is in `$CLAUDE_OLLAMA_RELAUNCH_DIR`.
  Tests: `ollama/incidents/ladder.test.sh` (inline incident rows, a sleeping
  pid, a stub `ps`), `bin/claude-ollama.test.sh` (stub ladder,
  `STUB_CLAUDE_LADDER_ONCE`), `shared/mcp/code-search.test.sh`.
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
  context, the other sizes 96k. It must name every tool the session can call
  (the launcher's `--tools` list and each MCP server's tool names);
  `bin/check-config` fails when one is missing. `ollama/sizes.json` is the
  single source for each size's `context`: `bin/ollama-profiles` writes it to
  `Modelfile.<size>` (`num_ctx`) and, minus `output_tokens` and
  `summary_reserve` from `ollama/headroom.json`, to
  `CLAUDE_CODE_MAX_CONTEXT_TOKENS`, so the prompt at the 88% compaction trigger
  plus the output and the compaction summary still fit in `num_ctx`
  (`bin/check-config` asserts the sum, `doctor` reports the headroom, and a
  profile's `context` override keeps the same margin through
  `shared/profile-overlay`); the `ollama create` names are the ones that `model`
  and the `ANTHROPIC_DEFAULT_*_MODEL` vars refer to. A managed `availableModels`
  that lacks the model makes Claude Code substitute a `[1m]` ID, which assumes a
  1M window; `claude-ollama doctor` warns when that happens. Each profile's own
  `availableModels` lists only its main model; `bin/check-config` checks it.
  `ollama/system-prompt.md` replaces Claude Code's default system prompt for
  both sizes; keep it short and don't put size-specific rules in it.
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
  the repo). `~/.config/claude-custom/profiles/<id>.json` (`claude-code`, or
  `ollama-<size>`) layers on top through `shared/profile-overlay` (POSIX sh +
  jq): `settings` applies tool states, `sandbox:false` (claude-code only),
  `context` and `thinking:true` (Ollama only; it drops the
  `CLAUDE_CODE_EXTRA_BODY` that turns thinking off, so Claude Code's own
  adaptive request reaches Ollama); `tools`, `env`, `mcp`, `parameters`,
  `summary` and `check` serve `bin/claude-ollama`. `env` exports only its
  `env_allowlist` (`CLAUDE_OLLAMA_TELEMETRY`, `CLAUDE_OLLAMA_NO_INDEX`,
  `CLAUDE_OLLAMA_OPEN_DRAFTS`, `CLAUDE_OLLAMA_CMUX`, `CLAUDE_OLLAMA_RELAUNCH`,
  `CLAUDE_OLLAMA_HANDOFF_PCT`, `CLAUDE_OLLAMA_INCIDENTS`), which must equal
  `PROFILE_ENV_KEYS` in `web/console/src/lib/profile-rules.ts`
  (`bin/check-config` checks it); the console's Profiles page shows each key by
  the plain label and default in `PROFILE_ENV_FIELDS`, never the variable name,
  and hides the handoff and incident fields from the `claude-code` profile. It
  refuses a symlinked profile, and `Agent` never reaches an Ollama profile. The
  overlay sets `sandbox.enabled` and the ask rule
  `Bash(dangerouslyDisableSandbox:true)`, so every personal session (subagents
  and `--agent pr-review` included) runs Claude's shell commands inside Claude
  Code's sandbox and asks before one runs outside it; `bin/check-config` checks
  both. It lets sandboxed commands write only `~/.cache/claude-sandbox` beyond
  the project and the temp dir, reach the same hosts as the Ollama profiles, and
  never read `~/.local/share/claude-custom` (the console token);
  `personal/launch` runs `claude` through `shared/sandbox-env` unless
  `profile-overlay sandbox-off` says the `sandbox-off` file or the `claude-code`
  profile turned the sandbox off. The Ollama profiles use the same sandbox with
  their own `sandbox` block; `claude-ollama qwen` runs Qwen Code inside macOS
  Seatbelt (`ollama/qwen-sandbox.sb`, the same cache folder), and the launcher
  unsets an outer `SANDBOX`, which `advanced.excludedEnvVars` keeps a project
  `.env` from setting.
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
