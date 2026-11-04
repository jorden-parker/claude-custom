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
- **Work harness** (`bin/claude-ollama`, `bin/claude-ollama-doctor`,
  `bin/claude-ollama-qwen`, `bin/lib/`, `ollama/`, `go/cmd/model-picker/`):
  starts `claude` against a local `llama-server` (Homebrew's `llama.cpp`) in
  router mode at `LLAMA_SERVER_URL` (default `http://127.0.0.1:11435`), serving
  pinned GGUF weights of Qwen 3.8 27b, Qwen 3.6 35b or Granite 4.2 3b. The
  overlay only applies to that launch. Ollama itself is gone from the harness;
  the names stay (`claude-ollama`, `~/.claude-ollama`, `CLAUDE_OLLAMA_*`,
  `ollama/`, `ollama-lease`, `ollama-models`, `ollama-agent`, the
  `ollama-<size>` profiles, called "the Ollama profiles" below, and the `-cc`
  preset ids), and only the bench-off still runs an Ollama server.
  `claude-ollama qwen [size]` runs Qwen Code on the same model and MCP servers
  inside macOS Seatbelt (`ollama/qwen-sandbox.sb`, copied to the project's
  `.qwen/sandbox-macos-claude-ollama.sb` and excluded from git at each launch;
  `QWEN_SANDBOX=sandbox-exec`, never `SANDBOX`), with `~/.claude-ollama/qwen` as
  its `QWEN_HOME`; `qwen doctor [size]` checks that setup. The launcher runs its
  usual pre-launch steps (weights, presets, fit, lease, indexer, warm-up), then
  hands off to `bin/claude-ollama-qwen launch SIZE [args]`, which stages the
  Qwen home and the Seatbelt profile and execs `qwen`; `qwen doctor` and
  `qwen --print-config` dispatch to its `doctor` and `--print-config` modes
  (`CLAUDE_OLLAMA_QWEN_BIN` overrides the script in tests). Its settings come
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
  `web/console/src/lib/profile-rules.ts`; an empty PUT deletes the file). Each
  profile's Env tab groups the harness switches under "Prompt and context",
  "Guards", "Model residency", "Diagnostics" and "Browser"
  (`PROFILE_ENV_GROUPS`, `envFieldsByGroup`). The `/settings` page
  (`settings-overview.tsx`) reads the same `GET /api/profiles`, whose summaries
  carry each profile's `env`, and tables every switch by key, label and default
  with one column per profile linking to its editor; it has no write route. Its
  "Actions" row links to `/diagnose` (nav entry after Logs), which gathers the
  one-click diagnostics: a "Why did the last run go wrong?" card starts the
  `why` console command (`claude-ollama why --json`, no params) through
  `console-run`, shows the run's lines while it runs and, when it ends, parses
  the JSON object from its `line` events (`web/console/src/lib/diagnose.ts`:
  `parseWhyReport`) into verdict, evidence, a copyable fix and the prefix hit
  rate, with a Raw output toggle; a "Rescue report" card starts the `rescue`
  command (`claude-ollama rescue SIZE`, size param) and, when it ends, shows the
  five summary lines and the report path (`parseRescueSummary`), with Copy
  report and Open buttons that read `GET /api/rescue/latest`
  (`web/console/src/lib/rescue-report.ts`: only the newest `*.md` under
  `~/.claude-ollama/rescue/`; 404 when none) and copy it to the clipboard or
  render it as markdown; a read-only "Rule cards" card lists
  `GET /api/rule-cards` (`web/console/src/lib/rule-cards.ts` runs
  `$CLAUDE_CUSTOM_HOME/shared/hooks/rule-cards.py --list`, 502 on a failure, and
  reads each card's body from `ollama/rule-cards/<id>.md`; `parseRuleCard`
  splits the front matter) with a link to the `CLAUDE_OLLAMA_RULE_CARDS` row on
  `/settings` (each switch row carries its key as its `id`); and a read-only
  "Recovery recipes" card lists `GET /api/recipes`
  (`web/console/src/lib/recipes.ts` reads `ollama/recipes/*.json`;
  `parseRecipeEntries`). Both run cards reopen the newest run of their command
  on load, and the page renders with no runs, no cards and no recipes. The Logs
  page's Proxy tab links "Record requests for replay" to the
  `CLAUDE_OLLAMA_PROXY_RECORD` row on `/settings`. Tests: `diagnose.test.ts`,
  the three route tests and the four card tests. The `/workspaces` page drives
  `GET`/`PUT /api/workspaces` (`web/console/src/lib/workspaces.ts`): it lists
  the `projects` of the launcher's `~/.claude-ollama/.claude.json` with
  `hasTrustDialogAccepted` and each folder's `.claude/skills`, and a PUT of
  `{path, trusted}` sets that flag (a new folder must exist and is keyed by its
  real path), recorded in history. `POST /api/workspaces/check`
  (`web/console/src/lib/skill-check.ts`) runs
  `bin/skill-check --size SIZE FOLDER` for a recorded, trusted folder (a print
  mode session runs the folder's hooks without the dialog), which starts
  `claude-ollama` there in print mode, reads the `init` event's `skills`, stops
  the launch and prints JSON (`claude_version`, `skills`, `error`); the page
  names the folder's skills missing from that array. Tests:
  `bin/skill-check.test.sh` (stub launcher and `claude`).
- **Agent TUI** (`go/cmd/ollama-agent/`; the name stays): a Go/Bubble Tea app
  that edits the `local.llama-server` LaunchAgent, which runs
  `llama-server --models-preset ~/.claude-ollama/presets/models.ini --models-max N --host 127.0.0.1 --port 11435 --log-file ~/.claude-ollama/logs/llama-server.log --metrics`.
  Its settings are the `[*]` keys of `ollama/server.ini` plus `models-max` from
  its `[router]` section; changes go to
  `~/.claude-ollama/presets/server.local.ini` (only the keys that differ).
  `-json` prints the settings without writing; `-set KEY=VALUE` (repeatable)
  changes just those, renders the user presets and reloads; `-apply` writes the
  agent from the settings and reloads it. The console's Server page uses `-json`
  and `-set`. See `go/cmd/ollama-agent/README.md`.

Every file is additive. Nothing here replaces a base config. The layer order is
in `docs/layers.md` and install/revert steps in `docs/install.md`. Read them
before changing how any file gets applied.

## Commands

- Hook tests: `shared/hooks/*.test.sh` (each prints `all passed`, or `FAIL:`
  lines and exits 1)
- Everything at once: `make test` (`.claude/verify` with no arguments runs it).
  `make test` runs the targets in parallel and keeps going past a failure
  (`$(MAKE) -k -j$(NPROC) test-all`); `make test-all` runs them one after
  another when interleaved output gets in the way. `check-tests-wired` fails
  when a `*.test.sh` outside `eval/` and `shared/hooks/` is named in no make
  target. The Stop hook runs `.claude/verify FILE...` with the files the agent
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
  `bin/claude-ollama` and the `claude-custom ollama|qwen|tools` subcommands; one
  dispatch case each for `doctor` and `qwen`). Doctor tests:
  `bin/claude-ollama-doctor.test.sh` (`make test-doctor`; stub `sysctl`,
  `gguf-inspect`, watcher). Qwen tests: `bin/claude-ollama-qwen.test.sh`
  (`make test-qwen`; stub `qwen`, `shasum`). The launcher and doctor tests start
  `shared/testing/stub-llama-server.py` through
  `shared/testing/stub-llama-lib.sh` and point `LLAMA_SERVER_URL` at it;
  `shared/testing/test-guard TEST` runs a test under a Seatbelt profile that
  blocks writes to `~/.claude-ollama` and `~/Library/LaunchAgents`, port 11435
  and `launchctl`, and `make test` wraps the harness tests in it.
- Launcher libraries (`bin/lib/`, sourced, never run): `size-profile.sh` (sizes,
  `use_size`, model, the preset section and its `ctx-size`, headroom, profile
  overlay, the launch settings composition, fetch domains, MCP config),
  `model-server.sh` (the backend seam: `server_url`, `server_up`,
  `server_build`, `/models` entries, `model_load`/`model_unload`, server
  settings and `models_max`, the weights folder, pins and `fetch_weights`; a
  file's sha256 is cached by size and mtime through `weights-sha.sh`, shared
  with `bin/ollama-models`, so a launch hashes the weights only after they
  change; its Python twin is `shared/model_server.py`; tests:
  `bin/lib/model-server.test.sh`), `memory-fit.sh` (lease switch,
  `ollama-lease fit` reading), `nvm-node.sh` (nvm's Node), `session-logs.sh`
  (console state dir, telemetry, proxy log, beacon, watcher, tool budget paths),
  `cmux-terminal.sh` and `doctor-checks.sh` (`report` and the checks both
  doctors share). Each lib sources the libs it reads from, so `shellcheck` sees
  every name; `.claude/verify` runs the launcher, doctor and qwen tests for any
  `bin/lib/` edit.
- Weights manager (the name stays):
  `bin/ollama-models list|outdated [SIZE...]|prune [--yes]|pin SIZE [--revision REV]`
  works on the GGUF files in `~/.claude-ollama/weights`
  (`CLAUDE_OLLAMA_WEIGHTS_DIR` overrides it). `list` marks each file `pinned`,
  `mismatch` (sha256 differs from its pin), `candidate` (a `.next` file from
  `model-upgrade`), `orphan` (no size or embedding names it) or `partial`
  (`.part`). `outdated` compares each size's (and `embedding`'s) pinned revision
  with the Hugging Face repo's `main`: `current`, `behind` (followed by a `fix:`
  line naming `bin/model-upgrade SIZE`, or `bin/ollama-models pin embedding`) or
  `unknown`, and a count line ends the listing when one is behind (exit 1).
  `prune` removes orphan and partial files after asking
  (`prune --yes --only FILE...` removes just the named files that are still
  prunable, for the console's Models page). `pin` writes the repo's `main`
  revision (or `REV`) into `ollama/sizes.json` (or `ollama/embedding.json`) and
  its LFS sha256 into `ollama/model-digests.json`, then runs
  `bin/ollama-profiles`. Tests: `bin/ollama-models.test.sh` (stub `curl`, stub
  `ollama-profiles`)
- Model upgrade: `bin/model-upgrade SIZE [--eval] [--keep] [--force]` refuses
  unless llama-server answers, stops when the pin is already `main` (unless
  `--force`), downloads the repo's newest `main` revision of the size's GGUF to
  `<file>.next` in the weights folder (checked against its LFS sha256), adds a
  `[<model>@next]` section to the user presets and restarts the server, then
  runs `speed-check --thinking-only --model`, the cache probe and (with
  `--eval`) `pr-review-eval` and `task-eval` on that preset, saves
  `~/bench-results/upgrade-SIZE-*.json` and restores the presets. On a pass it
  replaces the weights with the candidate and runs
  `ollama-models pin SIZE --revision REV`, then prints the `git add` line; on a
  fail it removes the candidate (`--keep` keeps it). With `--eval` the gate also
  reads the current model's newest `~/bench-results/task-eval-*.json` and fails
  when the candidate's green count drops or its median seconds rise by more than
  25% (without one it only records, `tasks: ... (no baseline)`). Tests:
  `bin/model-upgrade.test.sh` (stub llama-server, stub `curl`, stub tools)
- Task eval:
  `bin/task-eval [size|--model M] [--task NAME]... [--runs N] [--json] [--launcher PATH]`
  times the work harness from prompt to a green test on each task in
  `eval/tasks/` (see `docs/task-eval.md`) and prints a scorecard
  (`task result seconds calls denials` per run, a `total:` line and a paste
  block); `--json` prints the report and saves
  `~/bench-results/task-eval-<utc>.json`.
  `claude-ollama task-eval [size] [args]` warms the size's model and execs it
  with `--launcher` (`CLAUDE_OLLAMA_TASK_EVAL` overrides the script; tests stub
  it). Tests: `bin/task-eval.test.sh` (stub launchers, stub `pmset`;
  `make test-tasks`)
- Config check: `bin/check-config` (prints `all passed`; static checks that the
  `ollama/` and `personal/` config files agree with each other)
- Skill listing: Claude Code lists skills for the model within
  `CLAUDE_CODE_MAX_CONTEXT_TOKENS × 4 × skillListingBudgetFraction` characters
  (default 1%), ranks them by recent use, and cuts the rest to a bare name, so a
  small model never picks them. The Ollama profiles set the fraction to 0.06.
  `bin/skill-listing --context N [--fraction F] DIR...` sizes the listing of
  those skill folders (first folder wins a name, `disable-model-invocation`
  skipped, descriptions cut at 1536) and prints `fits: ...` or `over: ...` (exit
  1); `--entries` prints the lines. `bin/check-config` fails when the shipped
  skills (`shared/skills`, `ollama/skills`) overflow any size's budget, and
  `doctor` prints `ok`/`warn skill listing:` for `~/.claude/skills` plus
  `ollama/skills`. Tests: `bin/skill-listing.test.sh`.
- Sync check: `claude-custom sync-check [--write] [--against FILE]` prints the
  local fingerprint summary, one `section: <short>` line each (`commit`,
  `dirty`, `claude_version`, `models`, `server`, `hooks`, `sandbox`,
  `fingerprint`), then the sections that differ from the beacon at
  `${XDG_CONFIG_HOME:-~/.config}/claude-custom/beacon.json` (or
  `--against FILE`) as `section: local X vs beacon Y (<host>, <age>)`, with each
  changed model digest and hook name spelled out; exit 0 when equal, 1 when
  different, 2 without a beacon. `--write` writes that beacon (0600) for you to
  copy to the other machine. `bin/sync-fingerprint` prints the JSON
  (`--out FILE` writes it 0600 in a 0700 folder, `--summary FILE` and
  `--age FILE` read one back); tests: `bin/sync-fingerprint.test.sh` (stub
  `llama-server` binary, the stub server, `claude`, temp git repo) and
  `bin/claude-ollama.test.sh` for `sync-check`, the launch beacon and doctor's
  beacon line
- Profile generator: `bin/ollama-profiles` renders `ollama/settings.<size>.json`
  from `ollama/sizes.json` and `ollama/profile-template.json`, the llama-server
  presets `ollama/models.ini` (per size a `[<model>]` section with
  `reasoning = off`, a `[<model>@think]` one with `reasoning = on` and a
  `[<model>@<ctx>]` one at the ladder's lower context, plus the embedding
  section `[qwen3-embedding-0.6b]` with `alias = qwen3-embedding:0.6b`; weights
  paths are `@WEIGHTS@/<file>` and sampling keys map through
  `ollama/preset-keys.json`), and `personal/settings.tokens.json` from
  `personal/settings.tokens.template.json`.
  `--user-presets [--check] [--out FILE]` writes
  `~/.claude-ollama/presets/models.ini` (0600): `models.ini` with the weights
  folder filled in, the `[*]` keys of `ollama/server.ini` overlaid by
  `server.local.ini`, plus, per Ollama profile override, `[<model>@<ctx>]`
  sections for its `context` and that context's lower step and a
  `[<model>@profile]` section when it sets `output_tokens` or `parameters`, and
  prints `changed` or `unchanged`. It also copies the profile env catalogue
  `shared/profile-env.json` to `web/console/src/lib/profile-env.generated.json`
  and renders its table in `docs/ollama.md` between the
  `<!-- profile-env:start -->` and `<!-- profile-env:end -->` lines;
  `bin/ollama-profiles --check` (`make check-profiles`) fails when any of them
  is stale (it compares JSON by content, so it needs no Prettier; writing the
  files needs `pnpm install`); tests: `bin/ollama-profiles.test.sh`
- GGUF inspector:
  `bin/gguf-inspect FILE [--file-size N] [--template-out PATH] [--json]` checks
  a GGUF header with strict bounds (never reads tensor data); `--json` prints
  the metadata (tokenizer keys left out), which the lease's memory fit reads;
  tests: `bin/gguf-inspect.test.sh`
- Cache probe:
  `bin/ollama-cache-probe [PRESET] [--prefix-tokens N] [--base-url URL] [--replay DIR] [--json]`
  measures prompt-cache reuse through llama-server's `/v1/messages` on a preset
  id (default the 27b's) in six scenarios (cold after an unload and reload,
  growing chat, same prefix, late edit, early edit, eviction), reading
  `cache_read_input_tokens` and the loaded model's `n_ctx`; `--replay` sends
  recorded proxy bodies in ts order; its tests are
  `bin/ollama-cache-probe.test.sh` (stub server)
- Speed check: `claude-ollama speed-check` (`bin/speed-check`) checks power,
  other sessions, llama-server and disk, downloads the 27b and 35b weights, then
  checks that each `@think` preset thinks and the plain one does not, benches
  each size through `messages-bench` and runs the cache probe, and prints a
  verdict and a paste block; `CLAUDE_OLLAMA_SPEED_CHECK` and
  `SPEED_CHECK_LAUNCHER`/`_BENCH`/ `_PROBE` override the scripts in tests;
  tests: `bin/speed-check.test.sh`. `claude-ollama prepare [size]` downloads and
  verifies one size's pinned GGUF and exits; `claude-ollama prepare-embedding`
  does the same for the `semantic_search` embedding GGUF;
  `claude-ollama thinking-check` (`bin/speed-check --thinking-only`,
  `--model PRESET` for one preset) runs only the thinking check and exits 1 when
  it fails
- Messages bench:
  `bin/messages-bench --model M [--base-url URL] [--thinking omit|claude-code|disabled]`
  times any `/v1/messages` server (cold/warm TTFT, prefill, decode, tool calls);
  runbook and results in `docs/backend-bench.md`; tests:
  `bin/messages-bench.test.sh` (stub server)
- Tool budget:
  `bin/tool-budget --proxy-log FILE --telemetry FILE [--since DAYS] [--json]`
  (stdlib only) joins the proxy log's per-request `ledger` with the tool
  telemetry over the window (default 14 days) and prints one row per tool
  (latest schema bytes, requests carrying it, bytes per session as bytes ×
  requests, calls, `N bytes per call` or `never called`), sorted by bytes per
  session, then `protected (...)`,
  `suggest: drop: A, B (saves N KiB per request)` (or `nothing to drop`) and
  `keep:`. `claude-ollama tool-budget [--since DAYS] [--json]` runs it on the
  session's logs before any pull or launch; tests: `bin/tool-budget.test.sh`
  (inline fixture logs), `bin/claude-ollama.test.sh` (stub script, doctor lines)
- Bench-off (the only place Ollama still runs, on purpose; `bin/check-config`
  fails on an `ollama` command or Ollama API path anywhere else in `bin/`,
  `shared/` or `web/console/src/lib`, apart from a short allowlist: the install
  hint about removing old Ollama models, `prefix-ab --unload ollama` for the
  bench-off's Ollama cell, and tests asserting the absence):
  `bin/backend-bench-off install|download|all` benches Ollama, oMLX and
  vllm-mlx, each with MTP off (stock MLX weights) and on (`oQ4e` MTP weights),
  plus llama.cpp's `llama-server` on the pinned Unsloth GGUFs (`gguf_spec`:
  repo, revision, files) with the Mac settings in `llama_args`, MTP on through
  `--spec-type draft-mtp` (the 27B's separate head goes in `--spec-draft-model`;
  acceptance read from its log), model by model, and streams each run's JSONL
  into one side-by-side HTML page that reloads while it runs
  (`bin/backend-bench-report`, default `~/bench-results/bench-off.html`);
  `run SERVER MODEL` reruns one cell; MTP-on vllm-mlx runs copy the head with
  `bin/extract-mtp-weights`; the console's server list (`bench-choices.ts`) must
  match the script's; each run also replays `BENCH_REPLAY_DIR` through
  `bin/prefix-ab` into a `replay` line and a "Replay cache hit %" row; tests:
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
- Check the work harness: `claude-ollama doctor [size]` (exit 1 when
  llama-server does not answer, the size's preset is not in its `/models`, the
  weights are missing or fail their pin, a hook is missing or the context does
  not match; it warns on a server build below 9200, stale user presets, a GPU
  wired limit (`iogpu.wired_limit_mb`) below model plus KV, naming the
  `sudo sysctl` line, and a memory fit that is short; needs `jq`; the launcher
  resolves the size and execs `bin/claude-ollama-doctor SIZE`, which
  `CLAUDE_OLLAMA_DOCTOR_BIN` overrides in tests) and
  `claude-ollama --print-config [size]` (resolved values, no launch). Follow the
  server log: `claude-ollama logs [-n LINES]` follows
  `~/.claude-ollama/logs/llama-server.log` (the LaunchAgent's `--log-file`);
  `claude-ollama logs --path` prints that path instead of following it. Each
  launch also copies its own stderr, up to the hand-off to `claude`, to
  `$CLAUDE_CONSOLE_STATE_DIR/launcher.log` (0600, moved to `launcher.log.1` past
  1 MiB); the console's Logs page has Server (llama-server), Launcher, Incidents
  and Proxy tabs (`/api/logs/path` and `/api/logs/events` take
  `?source=server|launcher|incidents|proxy`)
- Explain the last bad run: `claude-ollama why [--since MINUTES] [--json]`
  (dispatched like `logs`, before any pull or launch, no size needed) runs
  `ollama/incidents/why.py` (stdlib; `CLAUDE_OLLAMA_WHY_BIN` overrides it for
  tests) on the proxy log and the current incidents file and prints one verdict,
  one evidence line, one `fix:` line, a `prefix:` hit-rate line and a `drift:`
  line; tests: `ollama/incidents/why.test.sh`
- Prefix A/B: `claude-ollama prefix-ab [size] [--limit N] [--json]` (dispatched
  like `review`: the size's model, before any pull or launch) execs
  `bin/prefix-ab --record ~/.claude-ollama/proxy/record --model M --base-url URL`
  (stdlib; `CLAUDE_OLLAMA_PREFIX_AB` overrides it for tests), which replays the
  recorded bodies twice in ts order, verbatim and through the proxy's
  `stabilize_bodies` (the script is imported as a module, no server starts),
  clearing the cache before each pass (`--unload llama-slots`, the default,
  unloads and reloads the preset on a router llama-server, else erases slot 0;
  `ollama` unloads an Ollama model and is kept only for the bench-off's Ollama
  cell; `none` sends nothing; `--auth-token` sets the key sent), and prints a
  two-column table of cache hit % per request (from `cache_read_input_tokens`
  counted against `input_tokens` plus the cached tokens, else prefill time per
  token against the first request, like the probe's fallback), a `mean` row and
  `stabilize: worth it (+N points mean hit rate)` or `stabilize: no gain` (under
  one point); `--json` prints `requests`, `mean`, `gain_points` and `verdict`.
  Tests: `bin/prefix-ab.test.sh` (stub server)
- Rescue report: `claude-ollama rescue [size] [--out FILE] [--since MINUTES]`
  (dispatched like `doctor`: no pull, no launch; `ollama/rescue.py`, stdlib
  only, does the work and `CLAUDE_OLLAMA_RESCUE_BIN` overrides it for tests)
  writes one pasteable markdown file, by default
  `~/.claude-ollama/rescue/<utc-time>.md` (0700 dir, 0600 file), prints its path
  and a five-line summary (`doctor:`, `lease:`, `incidents:`, `proxy:`,
  `memory:`) and exits 0 unless `--out` cannot be written. Its sections, each
  capped and redacted: `doctor` output, `--print-config` output, the
  `sync-fingerprint` JSON, llama-server's `/props` (build, role) and its preset
  models from `/models` with their status (at `LLAMA_SERVER_URL`), the lease
  holders and the session's rung, the last 50 incident rows with per-cause
  counts over the whole file, the proxy log's prefix hit rate (requests that
  kept every section but the newest message) and its top three diverging
  sections with their last diff over the last `--since` minutes (default 120)
  plus the record dir and its count when `~/.claude-ollama/proxy/record` exists,
  the launcher log tail (60 lines), the llama-server log tail (60 lines, through
  `claude-ollama logs --path`), the first 20 lines of the newest note in
  `<git common dir>/handoff/`, and free memory. Any token-looking string (40+
  base64 chars, `sk-`, `ghp_`, `Bearer `) becomes `<redacted>` and `$HOME`
  becomes `~`; whatever it cannot read becomes one `unavailable: <why>` line
  under its heading. Tests: `ollama/rescue.test.sh` (stub launcher, lease and
  fingerprint tools, a stub llama-server, fixture logs),
  `bin/claude-ollama.test.sh` (dispatch).
- Console: `claude-ollama ui [--port N]` serves `web/console` (Next.js with AI
  Elements) at `http://127.0.0.1:8765/`, built on first run with pnpm
  (reinstalled when `pnpm-lock.yaml` is newer than `node_modules/.modules.yaml`,
  rebuilt when a source is newer than `.next/BUILD_ID`). The reviews list is at
  `/reviews`; `claude-ollama reviews [--port N]` runs the same server and prints
  that link. A start on a port that already answers prints the running console's
  tokened link and starts nothing, writing a new token file if the old one was
  lost. Its tests run with `make test-web`.
- Console Models and Server pages: they talk to llama-server at
  `LLAMA_SERVER_URL` (`web/console/src/lib/model-server.ts`). `GET /api/models`
  (`models.ts`) joins the router's `/models` presets with
  `bin/ollama-models list` (the weights files and their states) per size and for
  the embedding model; `POST /api/models/load` and `/api/models/unload` send a
  preset id to `/models/load` or `/models/unload`; the page starts `prepare`,
  `prepare-embedding`, `prune` (`--yes --only FILE...`), `models-outdated` and
  `model-upgrade` through `console-run`. `GET /api/server` reads
  `ollama-agent -json`, and the page changes settings through the `server-set`
  command (`-set KEY=VALUE` per change) and reapplies through `server-apply`
  (`-apply`); `GET /api/server/ping` reports `up`, `loading` or `down` with the
  `/props` build (`model-server-health.ts`).
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
- `bin/claude-custom`, `bin/claude-ollama`, `bin/claude-ollama-doctor`,
  `bin/claude-ollama-qwen`, `bin/lib/*.sh`, `bin/claude-tools` and
  `bin/ollama-agent` must stay bash-3.2 compatible (macOS `/bin/bash`).
  `bin/claude-custom` must never write `~/.zshenv` or `~/.local/bin/claude`. The
  sizes, their preset ids and their weights come from `ollama/sizes.json`;
  `ollama/settings.<size>.json` and `ollama/models.ini` are rendered from it.
  Adding a size means one `sizes.json` entry, then `bin/ollama-profiles`; never
  hand-edit the rendered files. Every size's `gguf` (and
  `ollama/embedding.json`'s) must be a `<file>.gguf` from an `unsloth/`,
  `ibm-granite/` or `Qwen/` `*-GGUF` repo at a pinned 40-hex revision, its
  `base` must be `<repo>/<file>`, and `ollama/model-digests.json` must hold
  exactly those `<repo>/<file>` keys, each with Hugging Face's LFS sha256 of
  that file at that revision
  (`https://huggingface.co/api/models/<repo>/tree/<revision>` lists `lfs.oid`);
  `bin/check-config` checks all of it. The weights live in
  `~/.claude-ollama/weights/<file>`, never in the repo: `fetch_gguf`
  (`bin/lib/model-server.sh`) downloads a missing or mismatched file to
  `<file>.part` from `<repo>/resolve/<revision>/<file>` (resuming with
  `curl -C -`), keeps it only when its sha256 equals the pin and
  `bin/gguf-inspect` passes it, and `bin/claude-ollama` runs it before every
  launch and exits 1 when it fails; `doctor` reports a missing or mismatched
  file.
- Go module `go/` (all three apps; `go/cmd/model-picker/`,
  `go/cmd/claude-tools/`, `go/cmd/ollama-agent/`): `cd go && go test ./...`. One
  test: `cd go && go test ./internal/tools/ui -run TestSwitching`. Run the
  picker or the tools TUI with `cd go && go run ./cmd/model-picker` or
  `cd go && go run ./cmd/claude-tools`. `claude-ollama` builds and runs the
  picker when no size is given on a terminal. See
  `go/cmd/claude-tools/README.md` and `go/cmd/ollama-agent/README.md`.

`claude-custom install` (and `update`, which runs it) sets up llama-server on
macOS: it boots out an old `local.ollama` LaunchAgent when one is loaded and
prints one line on removing the Ollama models by hand (`ollama rm NAME` for
each, then `brew uninstall ollama`; it never runs `ollama` itself), skips the
rest with `brew install llama.cpp` when `llama-server` is not on `PATH`, warns
below build 9200 (`brew upgrade llama.cpp`), writes the user presets
(`bin/ollama-profiles --user-presets`) and runs `ollama-agent -apply`, which
writes and reloads `local.llama-server` (a failed apply only warns). It
downloads no weights; `claude-ollama prepare [size]` does. `update` execs the
pulled `claude-custom finish-update`, which runs the install again.

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
  lockfile). Each rule in `UNBOUNDED_COMMANDS` is built by `needs_bounding_flag`
  or `must_not_open`, which prepend `COMMAND_START` so a rule only matches at
  the start of a command segment and ignores text inside arguments. A new rule
  needs both `expect deny` and `expect allow` cases in the test script.
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
  sourced library. With `CLAUDE_CUSTOM_HOOK_SANDBOX=1` (set by the Ollama
  profiles, never the personal overlay) `shared/hooks/hook_sandbox.py` runs the
  subprocesses of `edit-check.py` and `stop-verify.py` under Seatbelt with
  `shared/hooks/hook-sandbox.sb`: writes only to the project, temp and
  `~/.cache/claude-sandbox` (never the project's `.git` file or folder, the real
  git common dir, `.envrc`, `.vscode`, `.idea`, `.claude` or `.husky`; a project
  root that is `/`, the home folder or an ancestor of it, a hidden folder or
  `Library` directly under home, or under `/System`, `/Library`, `/usr`, `/bin`,
  `/sbin`, `/etc`, `/private/etc`, `/Applications` or `/opt/homebrew`, or that
  does not contain the working folder, is refused and reported, never skipped:
  `edit-check.py` fails with
  `<tool> not run: the project root <dir> is too broad for the hook sandbox`
  (and caches nothing), `stop-verify.py` with `verify not run: ...` or
  `fallow not run: ...`; `edit-check.py` picks the root by walking up from its
  working folder to the first folder with a `.git` entry, stopping below the
  home folder and never asking git, so a planted `.git/config` cannot move it),
  network only to localhost, and a minimal environment (`PATH`, `HOME`, `USER`,
  `LOGNAME`, `SHELL`, `TERM`, `LANG`, `LC_*`, `TMPDIR`, `CLAUDE_CUSTOM_HOME`; no
  tokens). Fallow is never resolved from the project: it runs from a neutral
  folder with `--root`. Tests: `shared/hooks/hook_sandbox.test.sh`.
- `shared/hooks/tool-telemetry.py` is a `PostToolUse` hook on every tool. With
  `CLAUDE_TOOL_TELEMETRY=<file>` set it appends one JSON line per call (time,
  session, tool, bytes, lines, over the trim limit; never the tool input).
  Telemetry is off by default: `claude-ollama` sets that variable to
  `~/.claude-ollama/telemetry/tool-calls.jsonl` only with
  `CLAUDE_OLLAMA_TELEMETRY=1` (and unsets an inherited one otherwise), and a
  symlinked folder or file turns it off for that launch. Both overlays also set
  Claude Code's own `DISABLE_TELEMETRY`, `DO_NOT_TRACK`,
  `DISABLE_ERROR_REPORTING`, `CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY` and
  `CLAUDE_CODE_ENABLE_TELEMETRY=0` (`bin/check-config` checks them). The five
  deny hooks add one `"kind": "deny"` line per denial through
  `shared/hooks/hook_telemetry.py` (hook name and reason, never the command; a
  path that cannot be written never changes the decision), and `.claude/verify`
  maps that module to their tests. An Edit, Write or MultiEdit line also carries
  `input_bytes` (the bytes of `old_string` plus `new_string`, or `content`;
  never the text). `bin/tool-telemetry-report LOG` summarises calls and denials,
  and its `output` section lists per tool the median and p90 `input_bytes` plus
  the `"kind": "nudge"` lines counted per rule, so a model upgrade can be judged
  on decode waste too; it refuses a symlink; its test is
  `bin/tool-telemetry-report.test.sh`. Its `TRIM_LINE_LIMIT` must equal
  `MAX_LINES` in `bash-output-trim.py` (`bin/check-config` checks it).
- `shared/preferences/PREFERENCES.md` holds the prose rules no tool can check,
  including token discipline. `bin/claude-custom install` `@`-imports it into
  `~/.claude/CLAUDE.md`, so both backends load it. Keep it short: the local
  models have 32k-96k context.
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
  plain command with no pipe. Because it runs unsandboxed, a session never runs
  npm: `claude-custom install` installs the CLI once from the committed lockfile
  `shared/ctx7/package-lock.json` with `npm ci --ignore-scripts` into
  `$HOME/.cache/claude-custom/ctx7` (never an environment variable; no sandbox
  may write it), and `claude-custom ctx7` execs that binary under an environment
  allowlist (`PATH`, `HOME`, the proxy and CA variables, `CONTEXT7_API_KEY`), so
  no registry credential reaches the process, with its stderr still passed
  through `redact_secrets`. A missing or stale install is refused with one line
  naming `claude-custom install`. Claude Code itself keeps the
  `claude-custom ctx7 *` exemption narrow: a pipe or `;` segment that does not
  match sends the line back into the sandbox, and a file redirect or command
  substitution still prompts. The CLI version is pinned as `ctx7_version` in
  `bin/claude-custom` and in `shared/ctx7/package.json`, and `bin/check-config`
  checks they agree; it also checks the wrapper, the prompt files and both
  overlays, checks the link, and that `PREFERENCES.md`, `CLAUDE.local.md` and
  `QWEN.local.md` name the skill.
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
- Task eval: `bin/task-eval` measures what the user feels, seconds from prompt
  to a green test. Each `eval/tasks/<name>/` has `task.json` (`prompt`, `test`,
  `timeout_seconds`, `language`), a `fixture/` project whose test fails until
  the change is made, and a `solution.patch` that makes it pass (the test script
  applies every patch through a stub launcher, so each fixture is red before and
  green after). Per run it copies the fixture to a temp dir, `git init`s and
  commits it, runs `LAUNCHER <size> -p "<prompt>" [--model M]` there in print
  mode with `CLAUDE_OLLAMA_NO_INDEX=1`, `CLAUDE_OLLAMA_BEACON=0`,
  `CLAUDE_OLLAMA_PROXY=0`, drafts and incidents off and `CLAUDE_TOOL_TELEMETRY`
  on a temp file, stops the launcher past `timeout_seconds` (SIGTERM to its
  process group, then SIGKILL), runs the test command, and records `green`,
  `red` or `timeout`, wall-clock seconds, `calls`, `denials` (`kind: deny`
  lines) and `nudges` (`budget` or `friction` lines) from the telemetry file,
  `output_bytes`, and at the start the power state (`pmset -g batt`: `ac`,
  `battery`, `unknown`) and `cpu_speed_limit` (`pmset -g therm`). The `total:`
  line is `N/M green, median seconds S, p90 P` over the green runs (`-` when
  none). Five tasks ship: `shell-fix`, `python-impl`, `go-table`,
  `rename-safely` and `read-then-edit` (a 443-line file, so the read-range guard
  matters); there is no `ts-vitest`, since vitest needs `node_modules`.
- Mockup spike: `claude-ollama mock-spike [size] [--runs N] [--brief NAME]...`
  (`bin/mock-spike --model M [--base-url URL] [--out FILE]`) streams three
  mockup briefs through llama-server's streaming `/v1/chat/completions` (SSE
  `choices[0].delta.content`) with the json-render catalog prompt from
  `web/console/src/lib/mock-spike/catalog.ts`, scores each reply (patch lines,
  elements, catalog validation, first-patch time) with
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
  `fixtures`, `eval` or `.claude`, tool config files (`jest.config.ts`,
  `.eslintrc.cjs`; `is_config` in `test_scope.py`) and non-code files always
  pass. `CLAUDE_CUSTOM_TDD=0` turns it off. Tests:
  `shared/hooks/tdd-guard.test.sh`.
- `shared/hooks/test-after-edit.py` is wired only in the Ollama profiles
  (`ollama/hooks.extra.json`), as PostToolUse on Edit, Write and MultiEdit, so
  the small model neither forgets the test nor floods its context with the whole
  suite's log. It never blocks (exit 0, no decision). For a code file it
  resolves the nearest test with `shared/hooks/test_scope.py`, the module
  `tdd-guard.py` shares (`is_code`, `is_test`, `scope_of`, `expected_test_name`
  and `resolve_test`): `X.test.sh` beside `X`; `*_test.go` in the package
  (`go test ./<pkg>` from the module root, with a `cd` when the session sits
  elsewhere); `X.test.ts`/`X.test.tsx`/`X.spec.ts` beside or under `__tests__`
  (`pnpm -C <package root> exec vitest run <file>`); `test_X.py` or `X_test.py`
  (`pytest <file>`); a project `.claude/verify` with the file as argument when
  nothing closer matched; else none. A test file resolves to itself. In
  `suggest` mode (the default) it returns one `additionalContext` line,
  `run now: <command>`, or
  `no test found beside <file>; write <expected test path> first`, and executes
  nothing. `CLAUDE_OLLAMA_TEST_AFTER_EDIT=run` executes the command under macOS
  Seatbelt, `sandbox-exec -f <profile>` with the same `ollama/qwen-sandbox.sb`
  that `claude-ollama qwen` stages (copied verbatim to a 0600 temp file; the
  `-D` params `HOME_DIR`, `TARGET_DIR` (the session `cwd`), `TMP_DIR`,
  `CACHE_DIR` (`~/.cache/claude-sandbox`), `QWEN_DIR` and `RUNTIME_DIR` (a
  scratch dir), and `bin/check-config` fails when `SEATBELT_PARAMS` and the
  profile's `(param ...)` names differ), with `shared/host-env` inside the
  sandboxed command; on any other platform, or without `sandbox-exec`
  (`CLAUDE_OLLAMA_SANDBOX_EXEC` overrides the lookup; `TEST_AFTER_EDIT_PLATFORM`
  overrides `sys.platform` in tests), it only suggests,
  `(not run: no sandbox on this platform)`. It is enabled only from the profile
  file (`~/.config/claude-custom/profiles/<id>.json`), which the sandboxed
  session cannot write. Run mode also falls back to the suggestion, with
  `(not run: <reason>)` appended, when the edited file is itself a test (by
  name, after resolving links; names match in any case), when the resolved test
  or `.claude/verify` was edited earlier in the session, when the edited file
  would be the program, or when the edited path lies outside the event's `cwd`;
  those identities are `(st_dev, st_ino)` pairs, never strings. The hook records
  every edited path with its device and inode per session under
  `${CLAUDE_CONFIG_DIR:-~/.claude}/cache/test-after-edit/` (written through a
  temp file and `os.replace`); a record that exists but cannot be read or parsed
  is left alone and refuses every run, `(not run: session record unreadable)`.
  The resolver never looks above that `cwd` for `go.mod`, `package.json`, `.git`
  or `.claude/verify`, and a file under `.claude` is never a test to run
  (`RUNNABLE_TEST_DIRS`; tdd-guard's `TEST_DIRS` keeps `.claude` so such edits
  still pass it). It runs with a 60 s timeout (`TEST_AFTER_EDIT_TIMEOUT`
  overrides it in tests) and a 2 MiB output cap, caches a pass by the content
  hashes of the edited file and the test under
  `~/.cache/claude-custom/test-after-edit` (`TEST_AFTER_EDIT_CACHE_DIR`
  overrides), and returns `tests: pass (<command>, 2.1s)` (`cached` on a hit),
  `tests: FAIL (<command>):` plus the first failing line and the next three (300
  characters each, never the log), or
  `tests: timed out after 60s (<command>); run it yourself`.
  `CLAUDE_OLLAMA_TEST_AFTER_EDIT=0` turns it off; the console's Profiles page
  offers the three as one select under Guards. Each call is one
  `"kind": "test-after-edit"` telemetry line (`mode`, `found`, `result`,
  `seconds`; never the output), which `bin/tool-telemetry-report` sums in its
  `tests:` line (calls, pass, fail, timeouts, median seconds).
  `bin/check-config` fails when an Ollama profile lacks the hook. Tests:
  `shared/hooks/test-after-edit.test.sh`, `shared/hooks/test_scope.test.sh`.
- `shared/hooks/friction_budget.py` is the friction budget the efficiency guards
  share (`bash-output-guard.py`, `read-range-guard.py`; never the safety guards
  or `tdd-guard.py`, which has its own strikes). Per-session hook state (this
  file and the ones `tdd-guard.py`, `rule-cards.py`, `context-budget.py`,
  `handoff-relaunch.py` and `incident-note.py` keep) goes through
  `shared/hooks/hook_state.py` (locked, atomic, pruned after 7 days). Each of
  them passes its denial through
  `deny_reason(hook, event, reason, alternative)`, which keys it by hook, tool
  and a fingerprint (Bash: the command minus digits, quoted strings and each
  path's last segment; Read: the path plus a 300-line bucket of `offset` and
  `limit`; otherwise the sorted input JSON) and counts it in
  `${CLAUDE_CONFIG_DIR:-~/.claude}/cache/friction/<session_id>.json`. The first
  three denials of one fingerprint keep their reason; the fourth and later get a
  plan reset instead (one line naming what the model keeps trying, the hook's
  one allowed alternative, and an order to stop retrying) and write a
  `"kind": "friction"` telemetry line with the fingerprint's hash, never the
  command. As a UserPromptSubmit hook (Ollama-only, in
  `ollama/hooks.extra.json`) it resets that file each turn; without that reset
  (the personal overlay) the file never exists and every denial stays plain.
  `CLAUDE_CUSTOM_FRICTION=0` turns it off. `shared/hooks/repeat-call-cache.py`
  (Ollama-only, PreToolUse and PostToolUse on Read and
  `mcp__code-search__semantic_search`; `git_status` is never cached, since no
  cheap stamp tracks edits to tracked or untracked files) keeps a per-turn
  result cache in the same file: after a call it records the call number, the
  output's sha256 and size, and an invalidation stamp (the file's mtime for
  Read, none for a search); an error result (`Error` text or an error flag) is
  never recorded. Before an exact same-turn repeat whose stamp is unchanged it
  denies with `same result as call #N this turn, unchanged since; use it` and
  writes a friction line carrying `saved_bytes`. A Read's served content (64 KiB
  or less) is also kept as a 0600 snapshot under
  `cache/friction/<session_id>.snapshots/` (stale ones pruned at each record).
  When the same Read repeats after the file's mtime changed, the hook diffs the
  snapshot against the file: identical content is the same denial; otherwise it
  rewrites the call through `updatedInput` (`permissionDecision: allow`) to the
  changed span plus 3 lines of margin, at most 300 lines, with
  `additionalContext` `lines A-B changed since call #N; showing only them` (or
  `showing only A-C (read on from C+1 for the rest)` when cut); a file with no
  snapshot passes through whole. Recovery recipes are data:
  `ollama/recipes/<hook>.json` holds `{"match": regex, "steps": [...]}` entries
  for `bash-output-guard`, `read-range-guard` and `tdd-guard`;
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
- `shared/hooks/rule-cards.py` (Ollama-only, in `ollama/hooks.extra.json`;
  PreToolUse on Edit, Write, MultiEdit, Read and Bash) delivers the situational
  rules just in time, so `ollama/CLAUDE.local.md` holds only what every turn
  needs. Each card in `ollama/rule-cards/<id>.md` is 3 to 8 lines under a
  `triggers:` front matter (`suffix: .sh`, `suffix: .ts,.tsx`,
  `path: web/console/`, `command: git commit`, `tool: Write`; a value list is
  comma-separated). A file tool matches by the `file_path` suffix or by a path
  prefix (relative to the event's `cwd`); Bash matches when a trigger's words
  head any command segment, split on shell separators; `tool` matches the tool
  name. The hook never denies: it returns one `additionalContext` with the
  bodies of the matching cards not yet delivered this session (state
  `${CLAUDE_CONFIG_DIR:-~/.claude}/cache/rule-cards/<session_id>.json`, so a
  handoff relaunch delivers them again), at most `CONTEXT_CAP` (1200) characters
  per call, path cards before suffix, command, then tool, the rest on the next
  call. A malformed card (no trigger, no body, unknown kind) is skipped with a
  line on stderr. `--list` prints each id with its triggers and exits 1 when one
  is malformed (`claude-ollama doctor` prints `ok   rule cards: N` or a warn
  naming the card); `--match TOOL JSON` prints the ids one call would deliver.
  `CLAUDE_OLLAMA_RULE_CARDS=0` turns the hook off (no output, no state; `--list`
  and `--match` ignore it); `CLAUDE_OLLAMA_RULE_CARDS_DIR` overrides the folder
  (default `$CLAUDE_CUSTOM_HOME/ollama/rule-cards`). `bin/check-config` fails
  when a card is malformed, two share an id, a body is over the cap, a card's
  line also sits in `CLAUDE.local.md`, `system-prompt.md` or `PREFERENCES.md`,
  or an Ollama profile lacks the hook. Tests: `shared/hooks/rule-cards.test.sh`,
  `bin/claude-ollama.test.sh` (doctor).
- `shared/hooks/name-nudge.py` is wired only in the Ollama profiles, as
  PreToolUse on Edit, Write and MultiEdit. It never denies: when the written
  text declares a placeholder name (`tmp`, `data2`, `obj`, `handleStuff`, a
  `Helper`/`Utils` suffix) or a Write names a code file that way (`utils.ts`,
  `misc.py`), it returns one `additionalContext` line asking for a name that
  says what the thing holds or does. Only code files count (by suffix, or a
  shebang for an extensionless one). Tests: `shared/hooks/name-nudge.test.sh`.
- `shared/hooks/edit-nudge.py` is wired beside it (Ollama profiles only,
  PreToolUse on Edit, Write and MultiEdit) and never denies: decode on a laptop
  is memory-bandwidth bound, so it returns one `additionalContext` line when an
  Edit's `old_string` is over 40 lines or 1500 characters while `new_string`
  changes fewer than a quarter of those lines (`edit/echoed-old-string`), a
  Write targets an existing file over 60 lines (`write/rewrites-file`), or a
  MultiEdit carries more than 8 edits (`multiedit/too-many-edits`). Each nudge
  is one `"kind": "nudge"` telemetry line with its `rule` id, never the text.
  `CLAUDE_OLLAMA_EDIT_NUDGE=0` (the console's "Nudge wasteful edits" switch)
  turns it off; `bin/check-config` fails when an Ollama profile lacks it. Tests:
  `shared/hooks/edit-nudge.test.sh`.
- `shared/relaunch_dir.py` (stdlib only) owns the relaunch dir protocol (terms
  in `CONTEXT.md`): its path (`~/.claude-ollama/relaunch/<launcher pid>`), the
  signal files (requests `relaunch` `{note, prompt, percent}`, `ladder`
  `{rung, context, reason}`, `ladder-up` `{rung, reason}`; flag `embed-off`),
  `claude.pid`, and the SIGTERM sent only when `ps -o comm=` names a node or
  claude process. Requests are validated against their schema and written
  through a temp file and `os.replace` (0600); `take` reads and removes one, and
  a malformed one is removed with a stderr line. Python callers import
  `RelaunchDir` (`handoff-relaunch.py`, `ladder.py` and `code-search.py` add
  `shared/` to `sys.path`); `bin/claude-ollama` (`relaunch_signal`) and the
  console's promote run its CLI:
  `[--dir D | --root R --pid N] prepare|request NAME JSON|take|has|raise|lower|path NAME|claude-pid PID`
  (`--dir` defaults to `CLAUDE_OLLAMA_RELAUNCH_DIR`; exit 1 absent, 2 usage or
  schema, 3 no such folder). `prepare --pid N` makes the folder 0700, clears
  every signal file and removes sibling folders whose pid no longer runs.
  Nothing else names a signal file. Tests: `shared/relaunch_dir.test.sh`; the
  launcher test's stub `claude` writes through the CLI.
- `shared/hooks/context-budget.py` and `shared/hooks/handoff-relaunch.py`
  (Ollama-only, in `ollama/hooks.extra.json`) chain short sessions through
  `/handoff` instead of letting the small model compact. The first is a
  PostToolUse hook on every tool: it sums the last assistant `usage` in the
  event's `transcript_path` (`input_tokens` plus both cache counts), and at
  `CLAUDE_OLLAMA_HANDOFF_PCT` (default 70) of `CLAUDE_CODE_MAX_CONTEXT_TOKENS`
  (silent when unset), or 4000 tokens before Claude Code's own compaction point
  when that comes first (window = max context minus
  `min(CLAUDE_CODE_MAX_OUTPUT_TOKENS, 20000)`, compacting at
  `min(window × CLAUDE_AUTOCOMPACT_PCT_OVERRIDE%, window − 13000)`), adds one
  `additionalContext` per session telling the model to finish its edit, call
  `Skill handoff save` and stop; the state file is
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
  `~/.claude-ollama/relaunch/<launcher pid>` (made by `relaunch_dir.py prepare`,
  removed by its EXIT trap), runs `claude` in the background with the tty's
  stdin, records `claude.pid`, forwards SIGINT/SIGTERM and waits; while the
  `relaunch` request exists it takes it through the module, prints
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
  (`repeat-call-cache.py`) are in `ollama/hooks.extra.json` and follow the
  shared hooks for each event. `bin/check-config` fails when an Ollama profile
  lacks a hook the personal overlay has. `ollama/settings.*.json` also deny
  unused tools by bare name, so their schemas never reach the local model's
  context. `--tools` in `bin/claude-ollama` is the primary allowlist and that
  deny list is the backstop. `bin/check-config` fails when the Ollama deny lists
  differ. A local model's weights are not trusted, so Bash runs in Claude Code's
  own sandbox, configured by the `sandbox` block in
  `ollama/profile-template.json` (rendered per size). Sandboxed commands write
  the project, a temp dir and `~/.cache/claude-sandbox`, reach loopback
  addresses, `github.com`, the npm, Go and PyPI registries and GitHub downloads,
  and cannot read credentials or `~/.claude`. The launcher execs `claude` and
  `qwen` through `shared/sandbox-env`, which points Go, npm, pip, uv, yarn, bun
  and pnpm's metadata caches at caches under that one folder, so no cache an
  unsandboxed process executes from (`~/.npm/_npx`, `~/go/pkg/mod`,
  `~/.cache/claude-custom`) is writable. pnpm's content store is never moved: a
  `node_modules` remembers the store it was linked from, and pnpm pointed at
  another one asks to wipe and reinstall it, a prompt a Bash tool never answers.
  It also sets `NODE_USE_ENV_PROXY=1`, since Node's `fetch` (a sandboxed `npx`,
  for one) otherwise ignores the sandbox's `HTTPS_PROXY` and every request
  fails. `bin/check-config` asserts the block's exact values, and a misspelled
  key is silently ignored, so the check must change with the block. The profiles
  set `sandbox.enabled` and `autoAllowBashIfSandboxed: true`, so sandboxed
  commands run without a prompt (a skill's `!` commands included);
  `excludedCommands` (`cmux`, `gh`, `short`, `git push`, `git commit`,
  `claude-custom ctx7`, `pnpm`) run outside the sandbox, each after the `Bash`
  prompt except the allowed `ctx7`, and `permissions.ask` holds only
  `Bash(git commit *)`, `Bash(git push *)` and
  `Bash(dangerouslyDisableSandbox:true)`; `bin/check-config` checks both. The
  profiles also set `CLAUDE_CODE_EXTRA_BODY` to
  `{"thinking":{"type":"disabled"}}` (harmless: the plain presets already set
  `reasoning = off`); `bin/check-config` checks it.
  `shared/hooks/git-push-guard.py` (Ollama-only, PreToolUse on Bash) denies
  force pushes, remote deletes, `--mirror`, `--prune`, `-c alias.*`, pushes to
  `main` or `master`, and any push not spelled `git push ...` at the head of a
  command (`-C`, `--git-dir`, a path to `git`), which the `Bash(git push *)` ask
  rule and `excludedCommands` would otherwise miss. The personal overlay also
  denies unused tools by bare name (`Artifact`, `Workflow`, `ScheduleWakeup`,
  `SendFeedback` and the deferred ones), since a bare deny removes the tool's
  schema from the request; `bin/check-config` fails when an Ollama profile lacks
  one of those bare denies. The personal overlay's sandbox allows the same
  caches and loopback addresses; `bin/check-config` checks they match the Ollama
  profiles.
- `bin/sync-fingerprint` (bash 3.2, jq) says what a checkout runs: `commit`
  (HEAD of `repo_dir`), `dirty` (tracked changes only), `models` (per size its
  preset id, GGUF file, pin state from `ollama-models list` (`ok`, `mismatch`,
  `missing`) and, when `ok`, `sha256:<pin>` as its digest), `server` (`build`,
  from `/props` or `llama-server --version`, null when neither answers, and
  `settings`: the `[*]` keys of `server.ini`, the user presets and
  `server.local.ini`, plus `models-max`), `hooks` (sha256 per
  `shared/hooks/*.py` and `*.sh`, by basename, `*.test.sh` left out), `sandbox`
  (sha256 of the rendered `sandbox` block of `ollama/settings.27b.json`),
  `claude_version` (first line of `claude --version`, else null), `host`, `ts`,
  and `fingerprint`, the sha256 of the canonical JSON (`jq -cS`) of everything
  but `host` and `ts`. Every `bin/claude-ollama` launch writes it to
  `$CLAUDE_CONSOLE_STATE_DIR/beacon/<host>.json` (0700 folder, 0600 file) in the
  background before the hand-off (`CLAUDE_OLLAMA_BEACON=0` skips it), and
  `claude-custom install` (so `update`, through `finish-update`) refreshes it.
  `claude-ollama doctor` prints `ok   beacon: <age> ago, commit matches`,
  `warn beacon: stale, commit X vs HEAD Y: run claude-custom update` or
  `warn beacon: none yet`; it never fails doctor. `claude-custom sync-check`
  compares sections by canonical JSON, not by the stored `fingerprint`, so a
  hand-edited beacon still diffs. Nothing is sent over the network.
- Launch settings: `bin/claude-ollama` keeps each settings layer as a plain
  variable (the fetch domains, `profile_file` when it exists, the ladder
  context, the proxy URL) and `compose_launch_settings` turns them into one file
  through
  `shared/profile-overlay compose BASE OUT [--fetch-domain HOST]... [--profile FILE] [--context N] [--proxy-url URL]`,
  which applies them in that fixed order onto `ollama/settings.<size>.json`:
  fetch domains (lift the bare `WebFetch` deny, allow each host, deny loopback
  hosts, `skipWebFetchPreflight`), then the profile with `--context` replacing
  its `context` (the same rules as `settings`, so the max context follows a
  lowered context), then `env.ANTHROPIC_BASE_URL`. It runs on every launch,
  `--print-config` and `doctor`, after the proxy starts, on a ladder
  context-down and on its recovery. With no layer in effect `claude` gets
  `ollama/settings.<size>.json` itself; otherwise it gets
  `~/.claude-ollama/launch-settings/<launcher pid>.json` (0600, removed when the
  launch ends; `doctor` and `--print-config` compose into a temp file), the only
  derived settings file. Tests: `shared/profile-overlay.test.sh`,
  `bin/claude-ollama.test.sh`.
- `bin/claude-ollama` resolves its own symlink to find `ollama/`. It unsets
  `ANTHROPIC_API_KEY`, passes `--settings` with the launch settings above,
  `--system-prompt-file ollama/system-prompt.md` (replacing Claude Code's
  default system prompt),
  `--append-system-prompt-file ~/.claude-ollama/append-prompt.md` (written each
  launch from `ollama/CLAUDE.local.md`, plus `ollama/CLAUDE.cmux.md` in a cmux
  terminal unless `CLAUDE_OLLAMA_CMUX=0`), `--strict-mcp-config` plus an inline
  `--mcp-config` for the code-search server, `--model` with the profile's
  `model` (it also unsets `ANTHROPIC_MODEL`, which would otherwise win over the
  settings file), and restricts tools with `--tools` (built-in tools only; MCP
  tools still load). `--model` is the composed preset id (`<model>`,
  `<model>@think`, `<model>@<ctx>` or `<model>@profile`, from
  `shared/profile-overlay`). Before launching, it downloads and checks the
  size's weights, renders the user presets (and runs `ollama-agent -apply` when
  they changed), waits for llama-server, fetches the embedding weights, runs the
  memory fit, exits 1 when llama-server's `/models` lacks the preset id, claims
  the session lease, then asks the router to load the preset (and the embedding
  preset when embeddings are on) in the background. `doctor` and
  `--print-config` are dispatched before any download or launch; `doctor`
  (`bin/claude-ollama-doctor`) reads hook names from the profile's settings
  file, not from `~/.claude/hooks`.
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
  `semantic_search` instead. Never map a Claude ID to the main model in
  `modelOverrides`: Claude Code then names it after that ID, so the banner says
  Haiku or Sonnet. `bin/check-config` checks all of this.
  `personal/settings.tokens.json` keeps `CLAUDE_CODE_SUBAGENT_MODEL=haiku` with
  `CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1` (Claude Code v2.1.257 or later).
- `bin/claude-ollama` puts nvm's Node first on the session's PATH, since nvm is
  a shell function that a fish shell, a cmux command or launchd never loads:
  with `$NVM_DIR` (default `~/.nvm`) installed it reads the nearest `.nvmrc`
  above the working folder, else nvm's `default` alias, follows aliases, picks
  the newest installed `versions/node/v<spec>*` and prints
  `claude-ollama: node: <path> (nvm <spec> from <file>)` (or `(nvm default)`); a
  spec nvm has not installed leaves PATH alone with a
  `nvm has no node <spec> installed` line, and no nvm install says nothing.
  `doctor` prints `ok   node <path> (...)`, `(no nvm)` for the PATH node, or
  `warn node: none on PATH`. Tests: `bin/claude-ollama.test.sh`.
- `bin/claude-ollama` reads the configured sizes from `ollama/` (a
  `settings.<size>.json` whose size is a key of `ollama/sizes.json`; the
  console's `sizes.ts` uses the same rule), never a hardcoded list. A first arg
  that matches launches that size. Otherwise, on a terminal it runs
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
  Inside the sandbox pnpm cannot hardlink from the user's store, so it falls
  back to a store under the temp dir, decides every existing `node_modules`
  belongs to another store and prompts to wipe it, which hangs the tool; so Bash
  `pnpm -C DIR install|add|test` runs outside it, and so does `git commit`,
  whose lefthook or husky hooks run pnpm (the commit still asks first);
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
  tests). It follows the llama-server log (`server_log_path`,
  `~/.claude-ollama/logs/llama-server.log`) from its end, reopening when the
  file shrinks, and the session's transcripts under `~/.claude-ollama/projects`
  for new `compact_boundary` lines, and classifies each new line with an ordered
  regex table into `aborted` (`http client error: Canceled`, a cancelled
  request), `truncated` (`exceeds the available context size` and its siblings),
  `reprefilled` (`forcing full prompt re-processing`, or a child's
  `prompt eval time ... / N tokens` count of 1000 or more within 300 tokens of
  its `n_ctx` or of its previous `total time ... / N tokens`), `evicted`
  (`stopping model instance name=`, `evicting idle LRU name=`, or a
  `spawning server instance` line), `compacted` (with `preTokens`) or `unknown`
  (a line naming the session's preset or an `instance` that fits no rule, never
  dropped); the rest of the router's load sequence (`[ preset]`,
  `proxying request to model`, queue and exit lines) is skipped. Each rule has
  an id (`aborted/cancelled`, `truncated/context-overflow`,
  `reprefilled/full-reprocess`, `evicted/unload`, `evicted/runner-start`,
  `ignored/load-sequence`, `reprefilled/prompt-eval`, `compacted/transcript`).
  `forcing full prompt re-processing` is logged only at verbosity 4, which the
  LaunchAgent does not pass, so `reprefilled/prompt-eval` is the rule that fires
  in practice. `ollama/incidents/incident_log.py` (stdlib only) owns the record
  and is the only writer: the watcher, the ladder and the launcher
  (`append_incident` runs
  `incident_log.py append --file F --cause C --detail D [--tokens N] [--rule R]`)
  all append through it. Each incident is one JSON line (`ts`, `cause`, `detail`
  of 200 chars, `tokens`, `rule`, null for `unknown`) appended to
  `$CLAUDE_CONSOLE_STATE_DIR/incidents/<utc-time>-<pid>.jsonl` (0700/0600), the
  newest also in `<file>.latest`, and `incidents/current` names the running
  session's file; rows with a `kind` (`health`, `ladder`) go through
  `record_kind_row` and never reach `.latest`. A `reprefilled` row also carries
  `preceded_by`, the last `{kind, ts}` event seen in the log before it (`embed`:
  the router proxying a request to the embedding preset; `load`: a child spawn
  or model load; `unload`: a stop or LRU eviction), or null; no other cause has
  the key. The causes are the keys of `ollama/incidents/causes.json` (cause to
  console log level: the watcher's six plus `relaunched` and `recovered` from
  the launcher and `degraded` from the ladder); appending any other cause raises
  (the CLI exits 2). `bin/ollama-profiles` copies that file, key order kept, to
  `web/console/src/lib/incident-causes.generated.json`, which `incidents.ts`
  imports for `INCIDENT_CAUSES` and the levels, and `make check-profiles` fails
  when the copy is stale. Tests: `ollama/incidents/incident_log.test.sh`. The
  watcher counts hits per rule, the `unmatched` lines (the `unknown` rows) and
  the log lines seen, and appends a
  `{"kind": "health", "ts", "rules", "unmatched", "lines"}` row (never to
  `.latest`) every 60 s in follow mode (`--health-interval`) and once at exit
  and in `--once`; every reader skips rows with a `kind`.
  `watcher.py --check-rules --log PATH [--model NAME] [--lines N]` (default 400)
  replays the log's last lines, prints each rule id with its hits, then `blind`
  (exit 1: 50 or more lines name the preset or an instance and no rule matched)
  or `ok`; `claude-ollama doctor` runs it as `check_classifier` on
  `server_log_path` and fails when the classifier is blind (`rules: N` counts
  the rules that hit). The launcher exports `CLAUDE_OLLAMA_INCIDENTS_FILE` to
  the session, and `shared/hooks/incident-note.py` (UserPromptSubmit, in
  `ollama/hooks.extra.json` after `friction_budget.py`; `bin/check-config` fails
  when an Ollama profile lacks it) adds one `additionalContext` line naming the
  last incident and the counts per cause when new ones appeared, remembering the
  reported count under `${CLAUDE_CONFIG_DIR:-~/.claude}/cache/incident-note/`.
  The console's Logs page has an Incidents tab (`source=incidents` on
  `/api/logs/path` and `/api/logs/events`, which read only the file
  `incidents/current` names inside that folder) with a count per cause and a
  classifier-health pill from the latest health row (`saw N lines, M unmatched`
  or `no health row yet`) above the lines; each line shows the preceding event
  and rule as sub-labels (`reprefilled · after embed · reprefilled/prompt-eval`;
  `web/console/src/lib/incidents.ts`: `parseIncident`, `parseHealth`,
  `latestHealth`). Tests: `ollama/incidents/watcher.test.sh`
  (`fixtures/llama-server-log.txt` covers every cause and passes
  `--check-rules`), `shared/hooks/incident-note.test.sh`,
  `bin/claude-ollama.test.sh` (stub watcher; doctor runs the real one on a stub
  log), the console's vitest suite.
- Messages proxy:
  `bin/messages-proxy --upstream URL --port N --log FILE [--port-file PATH] [--watch-pid PID]`
  (stdlib only) listens on `127.0.0.1:N` (`0` picks a free port and
  `--port-file` publishes it, 0600) and forwards `POST /v1/messages`,
  `POST /v1/messages/count_tokens`, `GET /v1/models`, `GET /health` and
  `GET /models` to llama-server unchanged (404 for any other route), SSE
  streamed back as it arrives; it exits when the watched pid dies. It answers
  403 when the `Host` is not `127.0.0.1`, `localhost` or `[::1]` (any port) or
  an `Origin` is not a loopback origin, and forwards the original `Origin` so
  the server's own check still runs, since the proxy rewrites `Host` to the
  upstream. For each `POST /v1/messages` it hashes the body's sections in order
  (`system`, `tools`, each `messages` entry, each as
  `json.dumps(sort_keys=True, separators=(",", ":"))`) as cumulative sha256
  prefixes, compares them with the previous request's and appends one JSON line
  to `--log` (0700 dir, 0600 file): `ts`, `request_id` (uuid4, also sent
  upstream as `X-Claude-Ollama-Request`), `sections`, `stable_sections`,
  `diverged_at` (`system`, `tools`, `message:N` or null), `offset` (byte within
  that section's canonical text), `diff` (at most 200 chars from there),
  `prompt_bytes` and `ledger`
  (`{"system": bytes, "tools": {"<name>": bytes}, "messages": bytes}` of the
  canonical text, so the console can show what each tool schema costs; a tool
  without a name is `tool:N`); nothing else of the body is logged.
  `--record DIR` also saves each body verbatim as `DIR/<request_id>.json` (0700
  dir, 0600 files) for `messages-bench --replay` and
  `ollama-cache-probe --replay`; never on by default, the launcher passes
  `--record ~/.claude-ollama/proxy/record` only when
  `CLAUDE_OLLAMA_PROXY_RECORD=1`. `bin/claude-ollama` starts it before
  `launch_claude` unless `CLAUDE_OLLAMA_PROXY=0` (`CLAUDE_OLLAMA_PROXY_BIN`
  overrides the script; tests stub it), with `--watch-pid $$`, the log at
  `<console state dir>/proxy/requests.jsonl` (`CLAUDE_CONSOLE_STATE_DIR`, else
  `~/.local/share/claude-custom/console`, the folder the console reads; the
  proxy creates it 0700), waits for the port file and recomposes the launch
  settings with `env.ANTHROPIC_BASE_URL` pointed at the proxy (the proxy layer
  of `compose_launch_settings`); when the port never appears it warns and keeps
  the direct URL. By default it only observes: no rewriting, no tool pruning.
  `--stabilize` (the launcher passes it only when
  `CLAUDE_OLLAMA_PROXY_STABILIZE=1`) adds the prefix stabiliser: when two
  consecutive requests differ inside `system` by a span that, widened to whole
  lines, is at most 400 bytes with the rest identical, each changed line's text
  (digits `#`, weekday and month names `<weekday>`/`<month>`) is learned as
  volatile for the session; a hard rule table seeds the set (a line that is only
  a date or time, a line starting with `Today's date`, `Current date` or
  `The current time`). Every volatile line found in `system` is removed from its
  place and appended after the rest (a string gets them as final lines; an array
  of text blocks gets them at the end of its last text block, a block left empty
  is dropped), so the bytes before it are stable; nothing is dropped, `tools`
  are never rewritten (a changed schema is logged, not moved) and `messages` are
  never touched. The forwarded body is the re-serialised JSON, the sections and
  `prompt_bytes` are hashed on what was forwarded, `--record` keeps the
  original, and the row gains `stabilized` (the masked lines moved) and
  `moved_bytes`. The console's Logs page has a Proxy tab (`source=proxy` on both
  log routes, reading only `$CLAUDE_CONSOLE_STATE_DIR/proxy/requests.jsonl`)
  with a header (prefix hit rate, average prompt bytes, the top three diverging
  sections), each row as `diverged_at · offset · diff` (`stable · N sections`
  when nothing changed) and a ledger panel listing the latest request's tool
  schemas by bytes with a bar (`web/console/src/lib/proxy-log.ts`:
  `parseProxyRow`, `prefixHitRate`, `topDivergingSections`, `latestLedger`,
  `ledgerTools`, `proxyFrame`). Tests: `bin/messages-proxy.test.sh` (stub
  upstream), `bin/claude-ollama.test.sh` (stub proxy), the console's vitest
  suite.
- Tool budget: every tool schema in a request is prefill the model pays on every
  cache miss, so `bin/tool-budget` ranks each schema's bytes × requests (the
  latest `ledger` bytes from the proxy log) against its calls (telemetry rows
  without a `kind`), both inside `--since DAYS`. A tool is suggested for
  dropping only with zero calls over at least 20 requests and 200 schema bytes,
  and never when it is in `PROTECTED_TOOLS` (`Bash`, `Read`, `Edit`, `Write`,
  `Skill`, `mcp__code-search__semantic_search`; the report says
  `built-in list in bin/tool-budget`). `claude-ollama tool-budget` passes
  `$(proxy_log_dir)/requests.jsonl` and
  `${CLAUDE_TOOL_TELEMETRY:-telemetry log}` (`CLAUDE_OLLAMA_TOOL_BUDGET_BIN`
  overrides the script for tests); `doctor` prints
  `ok   tool budget: nothing to drop` or
  `warn tool budget: drop X, Y (saves N KiB per request): claude-ollama tool-budget`
  (`warn tool budget: not checked (...)` when the script fails). The console's
  Settings page has a Tool budget card on `GET /api/tool-budget`
  (`web/console/src/lib/tool-budget-report.ts` runs the script with `--json` on
  `$CLAUDE_CONSOLE_STATE_DIR/proxy/requests.jsonl` and `CLAUDE_TOOL_TELEMETRY`,
  else `<state dir>/telemetry/tool-calls.jsonl`): a bar per tool, the
  suggestion, and per Ollama profile an "Apply suggestion to <profile>" button
  that confirms the names, then `GET`s the profile and `PUT`s its override with
  each suggested profile tool set to `off`
  (`web/console/src/lib/tool-budget.ts`: `parseToolBudgetReport`, `budgetBars`,
  `applySuggestion`, which skips names the profile does not list, such as MCP
  tools); the claude-code profile gets no button. Tests:
  `web/console/src/lib/tool-budget*.test.ts`,
  `src/app/api/tool-budget/route.test.ts`,
  `src/components/tool-budget-card.test.tsx`.
- Why: `claude-ollama why [--since MINUTES] [--json]` execs
  `ollama/incidents/why.py --proxy-log FILE --incidents-dir DIR` (stdlib only;
  `CLAUDE_OLLAMA_WHY_BIN` overrides it for tests; `--now ISO` fixes the clock
  for tests) with the proxy log the launcher writes and
  `$CLAUDE_CONSOLE_STATE_DIR/incidents`, before any pull or launch. It reads the
  proxy rows, the file `incidents/current` names (refused outside that folder)
  plus its `.latest` row (counted once), skips rows with a `kind`, keeps the
  last `--since` minutes, joins each incident to the last request at most 5 s
  before it, and prints a one-screen verdict chosen by a fixed priority:
  `truncated` > `evicted` (evicted rows, or `reprefilled` after `embed`, `load`
  or `unload`) > `prompt drift at system|tools` (a request that diverged before
  the messages, preferring the one joined to an incident) > `compacted` >
  `degraded` > `reprefilled` with no known event > `nothing wrong`; `aborted`
  never decides. The lines are `verdict:` (cause, summary, window), `evidence:`
  (counts, the last time, the preceding event or the diverging section, offset
  and diff, and the joined request: `the request Ns before it diverged at X` or
  `no request within 5s before it`), `fix:` (one command or variable:
  `bin/ollama-profiles` and `claude-ollama doctor`,
  `ollama-agent -set models-max=2` plus `CLAUDE_OLLAMA_LEASE`,
  `move the volatile line after the stable prefix: "<diff>"` followed by
  `CLAUDE_OLLAMA_PROXY_STABILIZE=1` and `claude-ollama prefix-ab`,
  `CLAUDE_OLLAMA_HANDOFF_PCT`, `ladder.py --inspect`,
  `ollama-agent -set ctx-checkpoints=256`, or `nothing to do`),
  `prefix: N% of M requests stable through tools` (a request counts when
  `diverged_at` is null or a `message:N`; the first row, with nothing to
  compare, is skipped) and `drift:` with the top three diverging sections and
  counts (`none`). `--json` prints one object (`verdict`, `summary`, `evidence`,
  `fix`, `prefix`, `diverging`, `incidents`, `window`). Tests:
  `ollama/incidents/why.test.sh` (inline fixture logs for every rung, the join
  window, `--since`, `.latest` and empty or unreadable inputs),
  `bin/claude-ollama.test.sh` (stub `why`; `why` never launches, starts no proxy
  and no watcher).
- Residency lease: `bin/ollama-lease` (bash 3.2, `jq`) keeps one file per
  holder, `<pid>.json` with `{name, model, num_ctx, rung, started}`, under
  `${CLAUDE_OLLAMA_LEASE_DIR:-~/.claude-ollama/lease}` (0700/0600), guarded by a
  `lease.lock` directory taken with `mkdir` (macOS has no `flock` command; a
  lock older than a minute is removed). Every call removes the files whose pid
  is dead.
  `acquire NAME [--model M] [--pid N] [--num-ctx N] [--rung R] [--exclusive] [--wait SECONDS]`
  succeeds at once when no `session` lease is held by another pid, or when the
  router's `models-max` (`models_max`: the LaunchAgent plist's `--models-max`,
  else `/props` `max_instances`, else 2) is at least the number of distinct
  models the holders plus the request would load; otherwise it exits 3 with one
  stderr line,
  `ollama lease: held by <name> (pid N, model M); run after that session ends or run claude-custom agent -set models-max=2`,
  after polling every `CLAUDE_OLLAMA_LEASE_POLL` seconds (default 1) for
  `--wait`. `--exclusive` refuses while any other holder exists.
  `release NAME [--pid N]` removes that pid's file, `holders` prints
  `live NAME pid N model M rung R` or `stale NAME pid N model M` (and removes
  the stale file). There is no heartbeat: every preset sets
  `sleep-idle-seconds = -1`, so the router never unloads an idle model.
  `bin/claude-ollama` acquires `session` (preset id, `num_ctx`) right after the
  preset check and before the indexer, so the indexer's `embedding` lease (held
  by the `sh -c` pid that execs `code-search.py --index`; a refusal sets
  `CODE_SEARCH_EMBED=0`, words only) never crowds the session out; the EXIT trap
  (`end_launch`) releases the lease and removes the relaunch dir. `review` and
  `mock-spike` acquire their own names with the size's model, `speed-check` and
  `thinking-check` acquire `--exclusive`, and each exits 3 on a refusal.
  `CLAUDE_OLLAMA_LEASE=0` turns all of it off; `CLAUDE_OLLAMA_LEASE_BIN`
  overrides the script for tests. `doctor` prints
  `ok   lease held by NAME (pid N, model M)`,
  `warn stale lease NAME (pid N) removed` or `ok   no lease holders`.
  `fit --model M --num-ctx N [--embedding E]` prints one JSON line
  `{model_bytes, kv_bytes, embedding_bytes, total_bytes, free_bytes, fits, margin_bytes, estimate}`:
  `M` and `E` are preset ids (or aliases) looked up in the user presets (else
  `ollama/models.ini` with the weights folder filled in), and the model and
  embedding bytes are the size of each preset's GGUF file (exit 1 naming
  `claude-ollama prepare` when it is missing); the KV bytes are `num_ctx` times
  the per-token K and V widths read from `bin/gguf-inspect --json`
  (`block_count / full_attention_interval * head_count_kv * (key_length + value_length)`,
  or the sum over a per-layer `head_count_kv` array) times the bytes per element
  of the server's `cache-type-k` (f16 2, q8_0 1, q4_0 0.5), or 25% of the model
  bytes scaled by `num_ctx / 65536` with `estimate: rough` when a field is
  missing (so a context-down rung lowers the estimate too); the free bytes are
  `sysctl -n hw.memsize` minus the active and wired pages of `vm_stat` on macOS,
  or `MemAvailable` from `/proc/meminfo` (`CLAUDE_OLLAMA_MEMINFO` overrides the
  path) when that file is readable, plus the GGUF file size of the model and
  embedding preset when `/models` shows it `loaded`, since their pages are
  already counted as used (the router's `/models` carries no size). It exits 1
  with `ollama lease: no preset M in <presets file>` or
  `ollama lease: cannot read the free memory`. `bin/claude-ollama` runs it
  before claiming the session lease (`CLAUDE_OLLAMA_FIT=0` skips it; a fit that
  fails prints `claude-ollama: memory fit: unknown (<reason>)` and the launch
  goes on) and prints
  `claude-ollama: memory fit: model 16.0 GiB + kv 8.0 GiB + embedding 0.6 GiB = 24.6 GiB of 28.9 GiB free`.
  When it does not fit the launcher starts on the lowest rung that does:
  `claude-ollama: ladder embeddings-off: does not fit with the embedding model (N GiB short)`
  (exports `CODE_SEARCH_EMBED=0`, takes no embedding lease, touches `embed-off`
  in the relaunch dir), then
  `claude-ollama: ladder context-down: does not fit at num_ctx N (N GiB short); starting at M`
  (the next lower size's context from `ollama/sizes.json`, else 75% rounded to
  1024 and never below 16384, through the same context layer of the launch
  settings, one step only;
  `claude-ollama: memory fit: still N GiB short at num_ctx M with the embeddings off`
  when even that is short, then
  `claude-ollama: not starting: the model does not fit in memory (set CLAUDE_OLLAMA_FIT=0 to start anyway)`
  and exit 1; `review`, `mock-spike` and `task-eval` refuse the same way,
  without the ladder). The session lease records the rung and the lower
  `num_ctx`, and the ladder is started with one `--rung R` per rung in effect.
  `doctor` prints `ok   memory fit: ...` or
  `warn memory fit: ... (N GiB short)`. Tests: `bin/ollama-lease.test.sh` (the
  stub llama-server, stub `sysctl`, `vm_stat`, a `meminfo` file, sleeping pids),
  `bin/claude-ollama.test.sh` (`STUB_MEMSIZE`).
- Degrade ladder: `ollama/incidents/ladder.py` (stdlib only; it imports
  `FileTail` and `process_alive` from `watcher.py` and `IncidentLog`,
  `incident`, `incident_rows` and `now_iso` from `incident_log.py`) runs outside
  the sandbox beside the watcher (`launch_claude` starts it after
  `prepare_relaunch_dir` with
  `--incidents $CLAUDE_OLLAMA_INCIDENTS_FILE --relaunch-dir DIR --watch-pid $$ --context NUM_CTX --model M --embedding E --lease-bin PATH [--rung R]...`;
  `CLAUDE_OLLAMA_LADDER=0` turns it off, `CLAUDE_OLLAMA_LADDER_BIN` overrides it
  for tests; `bin/check-config` fails when the launcher stops starting it). It
  follows the session's incidents file from its start and binds each rung to
  evidence, at most once per session: three `reprefilled` rows whose
  `preceded_by.kind` is `embed` within 10 minutes fire `embeddings-off` (touches
  `$CLAUDE_OLLAMA_RELAUNCH_DIR/embed-off`); three `truncated` rows fire
  `context-down` (writes `ladder` as `{"rung", "context", "reason"}`, the
  context being the next lower size in `ollama/sizes.json` or 75% of the current
  rounded down to 1024 and never below 16384, then sends SIGTERM to the pid in
  `claude.pid` only when `ps -o comm=` names a node or claude process, like
  `handoff-relaunch.py`). A fired rung appends a `degraded` incident
  (`detail: "<rung>: <reason>"`, `rule: "ladder/<rung>"`, also to `.latest`); a
  row no rung is bound to only appends
  `{"kind": "ladder", "ts", "note": "<cause> after <kind>: no rung"}` once per
  note. Recovery ratchet: the ladder remembers the newest row of each fired
  rung's cause (a `--rung R` given at start counts as fired at launch), and once
  `embeddings-off` or `context-down` has seen none for `--quiet-seconds`
  (default 1200) it runs
  `ollama-lease fit --model M --num-ctx N [--embedding E]` (the context before
  that rung, the other rung's degradation kept; at most once a minute) and, when
  `fits` is true, writes `$CLAUDE_OLLAMA_RELAUNCH_DIR/ladder-up` as
  `{"rung", "reason": "20 minutes without <description>, memory fits"}`. It
  proposes the last rung down first, one rung at a time: the next is considered
  only after the launcher removed the file, which also lets that rung fire again
  on new evidence. There is no heartbeat rung, since no preset unloads when
  idle. `ladder.py --inspect FILE` prints the `<rung>: <reason>` lines an
  incidents file would fire, then `up <rung>: 20 minutes without <description>`
  for each pending recovery, or `none`. The launcher honours `ladder-up` only on
  a handoff relaunch (never on its own, and never on a ladder relaunch): it
  removes `embed-off` and allows the embeddings again for `embeddings-off`, or
  drops the ladder context and returns to the profile settings for
  `context-down`, prints
  `claude-ollama: ladder up: <rung> recovered (<reason>)`, appends a `recovered`
  incident (`detail: "<rung>: <reason>"`, `rule: "ladder/up"`) and re-acquires
  the session lease with the rung still in effect, if any. The launcher's
  relaunch loop also wakes on a `ladder` file: it prints
  `claude-ollama: ladder <rung>: <reason>`, recomposes the launch settings with
  the rung's `context` as the context layer, so `CLAUDE_CODE_MAX_CONTEXT_TOKENS`
  follows it, re-acquires the session lease with `--rung`, and runs `claude`
  again with the same flags, a trailing prompt dropped and `--continue` added; a
  handoff sentinel in the same pass still wins the arguments. Every relaunch
  exports `CODE_SEARCH_EMBED=0` while `embed-off` exists, and `code-search.py`
  itself answers words only while that file is in `$CLAUDE_OLLAMA_RELAUNCH_DIR`.
  Tests: `ollama/incidents/ladder.test.sh` (inline incident rows, a sleeping
  pid, a stub `ps`, a stub `ollama-lease` with `STUB_FIT`),
  `bin/claude-ollama.test.sh` (stub ladder, `STUB_CLAUDE_LADDER_ONCE`,
  `STUB_CLAUDE_LADDER_UP`), `shared/mcp/code-search.test.sh`. The console's
  Server page has a Residency card
  (`web/console/src/components/residency-card.tsx`,
  `web/console/src/lib/lease.ts`): `GET /api/lease` runs
  `bin/ollama-lease holders` with `CLAUDE_CUSTOM_HOME` and answers
  `{holders, rung, fit}` (the live `session` holder's rung and the newest
  `claude-ollama: memory fit:` line of the launcher log under the console state
  dir), and the "Promote back up" button posts `{rung}` to
  `POST /api/lease/promote`, which runs
  `shared/relaunch_dir.py request ladder-up --pid <pid>`
  (`reason: "promoted from the console"`) for the live session, refusing (409) a
  session on another rung or without a relaunch dir; the same-origin rule of
  `proxy.ts` applies.
- `shared/mcp/code-search.py` is the `semantic_search` MCP server (JSON-RPC over
  stdio, stdlib only). It ranks 40-line chunks by their words (BM25) on every
  search, adds a vector ranking through llama-server's `/v1/embeddings` (the
  `qwen3-embedding:0.6b` alias of the `[qwen3-embedding-0.6b]` preset) only
  while the router's `/models` shows that preset `loaded`, keeps its index in
  memory and reloads `.git/code-search/index.json` when `--index` (the only
  writer) produced a newer one. `claude-ollama` starts `code-search.py --index`
  in the background on launch (`CLAUDE_OLLAMA_NO_INDEX=1` skips it) with
  `--watch-pid $$`, so it stops embedding when the session ends; an `flock` on
  `.git/code-search/index.lock` keeps it to one indexer per repo, and it saves
  the vectors it made when it stops early. `bin/claude-ollama` downloads its
  GGUF (`ollama/embedding.json`; `CODE_SEARCH_MODEL`, default
  `qwen3-embedding:0.6b`, names the preset); the model picker's "Set up
  embedding model" row runs `claude-ollama prepare-embedding` too. The default
  name appears once in each of `bin/lib/size-profile.sh`, `code-search.py` and
  `go/internal/picker/profiles/embedding.go`, and `bin/check-config` checks they
  agree. The Ollama profiles allow the tool in `permissions.allow`.
- `ollama/server.ini` holds the llama-server settings every preset shares
  (`[*]`: `n-gpu-layers = 99`, `flash-attn = on`, `batch-size` and
  `ubatch-size = 2048`, `cache-type-k`/`cache-type-v = q8_0`, `parallel = 1`,
  `cache-ram = 8192`, `ctx-checkpoints = 128`, `checkpoint-min-step = 128`,
  `cache-reuse = 256`, `prio = 2`, `sleep-idle-seconds = -1`, `jinja = true`)
  and `[router]` `models-max = 2`, which goes on the LaunchAgent command line.
  `bin/claude-ollama` reads `models-max` (`models_max`): at 2 or more (the main
  and embedding presets) it exports `CODE_SEARCH_EMBED=1` (the search server
  then uses the embedding preset) and loads the embedding preset beside the
  session's; otherwise `semantic_search` ranks by words only. Before each launch
  `bin/claude-ollama` runs `bin/ollama-profiles --user-presets` and, when that
  prints `changed`, `ollama-agent -apply` (`CLAUDE_OLLAMA_AGENT` overrides the
  command; tests stub it), then waits for llama-server to answer and asks the
  router to load the session's preset in the background (`/models/load`) before
  `exec claude`.
- `go/internal/agent/` has five packages: `apply` (`-apply` and `-set`: saves
  `server.local.ini`, renders the user presets, writes the plist, stops
  `brew services` `llama.cpp` when loaded, reloads), `launchd` (renders and
  reads the `local.llama-server` plist and its `--models-max`, saves atomically,
  builds the `launchctl bootout`/`bootstrap` reload command), `variables` (the
  built-in settings, the `server.ini`/`server.local.ini` parser, overrides and
  `ParseAssignment` for `-set`), `snapshot` (the `-json` view: current,
  recommended and conflicts) and `ui` (the Bubble Tea model; `Config.Reload` is
  injected so tests never call launchctl). Saving rewrites the whole plist.
- `ollama/CLAUDE.local.md` is the appended system prompt for every size, for
  small local models, not memory files. Keep it terse: the 27b has a 64k
  context, the 35b 96k and the 3b 32k. It must name every tool the session can
  call (the launcher's `--tools` list and each MCP server's tool names);
  `bin/check-config` fails when one is missing. `ollama/sizes.json` is the
  single source for each size's `context` and `output_tokens`:
  `bin/ollama-profiles` writes them to the size's preset in `ollama/models.ini`
  (`ctx-size`, `n-predict`) and to `CLAUDE_CODE_MAX_OUTPUT_TOKENS`, and the full
  context to `CLAUDE_CODE_MAX_CONTEXT_TOKENS`: Claude Code itself keeps every
  prompt plus its output 3000 tokens under that number and compacts at
  `min(window × 88%, window − 13000)` of the window left after the output, so
  subtracting the output again only made it compact at half of `ctx-size` (a
  size without `output_tokens` takes `headroom.json`'s; `bin/check-config`
  asserts the context equals `ctx-size`, that `n-predict`,
  `CLAUDE_CODE_MAX_OUTPUT_TOKENS` and `sizes.json` agree per size, and that
  `precomputeCompactionEnabled` is false, since a background summary is a second
  full prefill on the one local model; `doctor` and `--print-config` print the
  compaction point, and a profile's `context` override sets the max context
  tokens through `shared/profile-overlay`); the preset section names are the
  ones that `model` and the `ANTHROPIC_DEFAULT_*_MODEL` vars refer to. A managed
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
  the repo). `~/.config/claude-custom/profiles/<id>.json` (`claude-code`, or
  `ollama-<size>`) layers on top through `shared/profile-overlay` (POSIX sh +
  jq): `settings` applies tool states, `sandbox:false` (claude-code only),
  `context` (the model becomes `<model>@<ctx>`), `output_tokens` (1024 to 16384:
  `CLAUDE_CODE_MAX_OUTPUT_TOKENS` and the preset's `n-predict`; with
  `parameters`, the model becomes `<model>@profile`) and `thinking:true` (Ollama
  profiles only: the model becomes `<model>@think`, whose preset sets
  `reasoning = on`, and the `CLAUDE_CODE_EXTRA_BODY` that turns thinking off is
  dropped; a profile with both `thinking` and `context` is refused); `tools`,
  `env`, `mcp`, `parameters`, `summary` and `check` serve `bin/claude-ollama`.
  `env` exports only the keys of the profile env catalogue
  `shared/profile-env.json` (an ordered list of
  `{key, group, kind, default, min, max, step | choices, label, help, ollamaOnly}`,
  `kind` one of `switch`, `integer`, `choice`; values are not checked there):
  the 0/1 switches `CLAUDE_OLLAMA_TELEMETRY` (default off),
  `CLAUDE_OLLAMA_NO_INDEX`, `CLAUDE_OLLAMA_OPEN_DRAFTS`, `CLAUDE_OLLAMA_CMUX`,
  `CLAUDE_OLLAMA_RELAUNCH`, `CLAUDE_OLLAMA_INCIDENTS`, `CLAUDE_OLLAMA_PROXY`
  (default on), `CLAUDE_OLLAMA_PROXY_RECORD` (default off),
  `CLAUDE_OLLAMA_PROXY_STABILIZE` (off), `CLAUDE_CUSTOM_FRICTION` (on),
  `CLAUDE_OLLAMA_LEASE` (on), `CLAUDE_OLLAMA_LADDER` (on), `CLAUDE_OLLAMA_FIT`
  (on), `CLAUDE_OLLAMA_BEACON` (on), `CLAUDE_OLLAMA_RULE_CARDS` (on) and
  `CLAUDE_OLLAMA_EDIT_NUDGE` (on), plus `CLAUDE_OLLAMA_HANDOFF_PCT` (a whole
  percent from 30 to 85, default 70), `CLAUDE_OLLAMA_TEST_AFTER_EDIT` (`0`,
  `suggest` or `run`, default `suggest`) and `CLAUDE_CODE_EFFORT_LEVEL` (`low`,
  `medium` or `xhigh`, default `xhigh`; Claude Code's own variable, read by Qwen
  3.8's chat template through llama-server when the profile's thinking is on,
  ignored by Qwen 3.6). Adding a switch is one catalogue entry, then
  `bin/ollama-profiles` (which renders the console's copy and the
  `docs/ollama.md` table) and a mention here (`bin/check-config` fails when this
  file lacks a key). `context-budget.py` and `test-after-edit.py` read their
  defaults from the catalogue through `shared/hooks/profile_env.py`
  (`catalogue_default`); the bash launchers keep their own `${VAR:-1}` defaults.
  `web/console/src/lib/profile-rules.ts` builds `PROFILE_ENV_KEYS` and
  `PROFILE_ENV_FIELDS` from the rendered copy (an `integer` becomes a `number`
  field with a `range`) and throws on an unknown group or kind. The console's
  Profiles page shows each key by the plain label, default and help sentence in
  `PROFILE_ENV_FIELDS`, never the variable name, grouped under the field's
  `group`, and hides every Ollama-only field from the `claude-code` profile,
  which of the harness switches sees only `CLAUDE_CUSTOM_FRICTION`. It refuses a
  symlinked profile, and `Agent` never reaches an Ollama profile. The overlay
  sets `sandbox.enabled` and the ask rule
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
  `local.llama-server` plist before the rename, as `index.jsonl` plus
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
