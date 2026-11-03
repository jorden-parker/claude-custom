# Work harness (Ollama)

Each size has its own base model, `-cc` model and profile files:

| Size  | Model                 | Base model        | `-cc` model      |
| ----- | --------------------- | ----------------- | ---------------- |
| `27b` | Qwen 3.8 27B, dense   | `qwen3.8:27b-mlx` | `qwen3.8-27b-cc` |
| `35b` | Qwen 3.6 35B-A3B, MoE | `qwen3.6:35b-mlx` | `qwen3.6-35b-cc` |

27b (the default size):

```sh
ollama pull qwen3.8:27b-mlx   # 18 GB; optional, see below
claude-custom install         # creates qwen3.8-27b-cc
claude-ollama 27b [args...]   # or plain claude-ollama
```

35b:

```sh
ollama pull qwen3.6:35b-mlx   # 24 GB; optional, see below
claude-custom install         # creates qwen3.6-35b-cc
claude-ollama 35b [args...]
```

Both sizes:

```sh
claude-custom ollama 27b      # same as claude-ollama 27b: launches 27b directly
claude-custom ollama          # pick a size in a menu
claude-ollama -p "hello"      # no size: menu, then the args go straight to claude
claude-ollama --help          # usage and the list of sizes
```

With no size, or a word that isn't a configured size (`28b`), `claude-ollama`
opens a picker ([model-picker](../go/cmd/model-picker/README.md)) and drops the
unknown word. Without a terminal (scripts, pipes) it uses 27b instead. The
picker needs Go 1.26+; passing a size never does.

Sizes are declared in `ollama/sizes.json`. `bin/ollama-profiles` renders
`settings.<size>.json` and `Modelfile.<size>` from
`ollama/profile-template.json` and `ollama/profile-template.Modelfile`; the
rendered files are committed, and `bin/ollama-profiles --check` fails when they
are stale. Each size's `output_tokens` caps one reply: it becomes the
Modelfile's `num_predict` and the profile's `CLAUDE_CODE_MAX_OUTPUT_TOKENS`
(decode is the slow path on a laptop, every output token sweeping the active
weights), and `bin/check-config` fails when the two disagree with `sizes.json`.
To add a size, add an entry to `sizes.json`, run `bin/ollama-profiles`, and
commit. The picker and `--help` pick up a new size without any script change.

Two GGUF sizes, `27b-gguf` (Qwen3.8 27B) and `35b-gguf` (Qwen3.6 35B-A3B), use
Unsloth's Q4_K_XL files from Hugging Face for comparison with the MLX sizes.
`claude-ollama speed-check` imports them and compares them with the MLX sizes
(see `docs/backend-bench.md`), and `claude-ollama prepare SIZE` pulls or imports
one size without starting `claude`. `claude-ollama thinking-check` checks that
thinking is off on the MLX sizes and prints PASS or FAIL.

`claude-custom install` creates the `-cc` models from `ollama/Modelfile.<size>`
once the base models are pulled. `claude-ollama` also does this itself for
either size: when the `-cc` model is missing, it pulls the base model and
creates the `-cc` model before starting `claude`. A failed pull stops the
launch.

There is no side model. Claude Code's Haiku slot uses the main model, and the
profiles deny `Agent`: a subagent would only rerun the main model on a fresh
context. Use `semantic_search` for wide searches instead; `grep`, `rg` and
`find` stay allowed for exact names. The profiles map no Claude ID to the main
model: Claude Code names the model after the ID that maps to it, so the banner
would say Haiku or Sonnet.

Compaction is avoided: at 88% of the window Claude Code would make the small
model summarize most of its context in one call, slow and lossy. Instead
`context-budget.py` (PostToolUse) reads the last `usage` in the transcript and,
at `CLAUDE_OLLAMA_HANDOFF_PCT` (default 70) of `CLAUDE_CODE_MAX_CONTEXT_TOKENS`,
tells the model once per session to finish its edit, run the `handoff` skill
with `save` and stop. `handoff-relaunch.py` (Stop) blocks the first stop after
that nudge when no note in `<git common dir>/handoff/` is newer than it, asking
for the save once more; with a fresh note it writes the note's path, the last
real prompt from the transcript (200 characters at most) and the percent as JSON
to `$CLAUDE_OLLAMA_RELAUNCH_DIR/relaunch` (a per-launcher dir under
`~/.claude-ollama/relaunch/`, whose signal files `shared/relaunch_dir.py`
defines) and sends SIGTERM to the pid in `claude.pid` there (only when `ps` says
it is a node or claude process). `claude-ollama` runs `claude` in a loop: while
that request exists it takes it, prints
`context budget reached at N%: handoff saved, resuming "<prompt>"`, writes a
`relaunched` incident (the Logs page's Incidents tab and `incident-note.py` show
it) and starts `claude` again with the same flags and `/handoff <prompt>` as the
prompt, which resumes from the note and finishes that request first.
`CLAUDE_OLLAMA_RELAUNCH=0` execs `claude` once as before.

Claude Code asks for adaptive thinking at high effort. Ollama only understands
enabled or disabled, so it would reason at high effort on every turn. The
profiles set `CLAUDE_CODE_EXTRA_BODY` to `{"thinking":{"type":"disabled"}}`,
which Ollama reads first. To measure it, run
`bin/messages-bench --thinking claude-code|disabled`. To turn thinking on for
one size, set `"thinking": true` in its profile (the Model thinking switch on
the console's `/profiles/ollama-<size>` page, Sandbox & model tab): the launch
then drops that variable from the derived settings, so Claude Code's own
adaptive request reaches Ollama and the model reasons before every reply. With
thinking on, Qwen 3.8 (the 27b) also reads an effort level: Claude Code sends
its effort as `output_config.effort`, Ollama passes a name the model's
`/api/show` metadata lists (`low`, `medium`, `xhigh`) through to the chat
template, which injects a matching instruction before the system prompt. Claude
Code's default `high` is not one of them, so Ollama falls back to the model
default, `xhigh`. The "Thinking effort when thinking is on" select on the same
profile page sets `CLAUDE_CODE_EFFORT_LEVEL` for the launch, which outranks
`/effort` and every settings file. Qwen 3.6 (the 35b) has on/off only and
ignores the level. Check what a model offers with
`curl -s localhost:11434/api/show -d '{"model":"qwen3.8-27b-cc"}' | jq .thinking`.
Thinking tokens count against `CLAUDE_CODE_MAX_OUTPUT_TOKENS`, and
`thinking-check` still measures the model with thinking off, since it never
reads a profile. The profiles also set every telemetry, error-report, survey,
feedback-draft, update-check and marketplace-install switch off
(`DISABLE_TELEMETRY`, `DO_NOT_TRACK`, `DISABLE_ERROR_REPORTING`,
`DISABLE_AUTOUPDATER`, `DISABLE_BUG_COMMAND`,
`CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY`, `CLAUDE_CODE_SEND_FEEDBACK=0`,
`CLAUDE_CODE_DISABLE_OFFICIAL_MARKETPLACE_AUTOINSTALL`, `feedbackDrafts: off`,
`feedbackSurveyRate: 0`) beside `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC`, and
`bin/check-config` checks them.

Plain `claude` stays on the personal setup. The profile only exists for that
launch.

### Model picker

`go/cmd/model-picker/` is the terminal menu `claude-ollama` opens to choose a
size. Each `settings.<size>.json` in `ollama/` with a matching
`Modelfile.<size>` is one entry, showing the size, its `-cc` model and its base
model. A last row "Set up embedding model" pulls the `semantic_search` model and
stays in the menu.

```sh
claude-custom ollama                       # opens the picker, then launches the chosen size
cd go && go run ./cmd/model-picker ../ollama  # the picker on its own; prints the chosen size
```

Keys: `↑/k`, `↓/j`, `enter` to launch, `esc`/`q`/`ctrl+c` to cancel. Cancelling
launches nothing. The picker is built by `claude-custom install` and rebuilt on
launch only when a Go source file is newer than the binary. Details:
[`go/cmd/model-picker/README.md`](../go/cmd/model-picker/README.md).

### Ollama server settings

The profiles expect an Ollama server on `localhost:11434` with the settings in
`ollama/server.env`. Before each launch, `claude-ollama` checks the running
server; when a value is missing (or no server runs) it calls
`claude-custom agent -apply`, which writes the values into the `local.ollama`
LaunchAgent, stops `brew services ollama` if it is loaded, reloads the agent and
waits for the server. It refuses while the Ollama menu-bar app runs; quit it
first. On a failure the launch goes on with a warning. The launcher also sends a
warm-up request with `keep_alive` 30m (`CLAUDE_OLLAMA_KEEP_ALIVE` overrides) so
the first prompt doesn't wait for the model to load.
`OLLAMA_MAX_LOADED_MODELS=2` (the shipped value) keeps the main and embedding
models loaded: the launcher exports `CODE_SEARCH_EMBED=1` so `semantic_search`
loads and uses `qwen3-embedding:0.6b` (about 2.2 GB), and warms it before
starting the indexer. At 1 the embedding model would evict the main model, so
searches rank by words only. `OLLAMA_NUM_PARALLEL=1` gives the main model one
request slot: Ollama allocates one KV cache per slot, so the default of up to
four would hold four times the context in memory and crowd out the second model.
The Homebrew service (`brew services start ollama`) uses these paths; add any
`server.env` value it lacks with `claude-custom agent`:

| What        | Homebrew value                                |
| ----------- | --------------------------------------------- |
| Binary      | `/opt/homebrew/opt/ollama/bin/ollama`         |
| Command     | `ollama serve`                                |
| Working dir | `/opt/homebrew/var`                           |
| Log         | `/opt/homebrew/var/log/ollama.log`            |
| Service     | `~/Library/LaunchAgents/sh.brew.ollama.plist` |

Without Homebrew, start the server with the same settings:
`env $(cat ollama/server.env) ollama serve`.

launchd doesn't read `~/.zshenv` or any other shell rc file, so variables
exported there never reach a server that `brew services` or the Ollama app
starts. `claude-custom agent` (`go/cmd/ollama-agent/`) edits a `local.ollama`
LaunchAgent that sets them, starting from `server.env`, and reloads it. Stop the
Homebrew service and the app first; the TUI warns when either is running.
`claude-custom agent -apply` does the same without the menu: it sets every
`server.env` value, keeps the agent's other variables, and stops the Homebrew
service itself.

### Checking the setup

`claude-ollama doctor [size]` checks the environment without pulling or
launching anything. It needs `jq` on PATH (`brew install jq`); without it the
launcher exits with an error. It reports each model (main, embedding), whether
`num_ctx` in the Modelfile leaves `CLAUDE_CODE_MAX_CONTEXT_TOKENS` plus
`CLAUDE_CODE_MAX_OUTPUT_TOKENS` at least the `summary_reserve` from
`ollama/headroom.json` (so a compaction at 88% still fits with its summary),
whether each hook named in `ollama/settings.<size>.json` exists and is
executable under `shared/hooks/`, whether Ollama answers at `OLLAMA_HOST`, and
whether the running server has every variable from `ollama/server.env`. Anything
missing exits 1. The server-env check is how to confirm `server.env` is applied.
The server's environment is read with `pgrep`/`ps` (or `/proc` on Linux).

`claude-ollama --print-config [size]` prints the resolved values (model, base
model, embedding model, context sizes, settings path, tools) and the exact
`claude` command, without launching.

`claude-ollama logs [-n LINES]` follows the Ollama server log with `tail -F` (50
lines of history by default). It reads the log path from the `local.ollama`
LaunchAgent plist when one exists, else uses the Homebrew service log
(`$HOMEBREW_PREFIX/var/log/ollama.log`), else the Ollama app's
`~/.ollama/logs/server.log`, and exits 1 when none exists. A server started by
hand with `ollama serve` prints to its own terminal and has no file to follow.

When something goes wrong on a machine you are not sitting at (the work laptop,
say), do not describe the symptoms: run `claude-ollama rescue` there and paste
the file it names. It writes one redacted markdown report under
`~/.claude-ollama/rescue/` with the `doctor` and `--print-config` output, the
sync fingerprint, the running server env and loaded runners, the lease holders
and rung, the last incidents, the proxy's prefix hit rate and top diverging
sections, the launcher and server log tails, the newest handoff note and free
memory, and prints a five-line summary. Tokens become `<redacted>` and your home
folder becomes `~`, so the file is safe to paste; anything it cannot read shows
as `unavailable: <why>` rather than stopping the report. `--since 30` narrows
the proxy window, `--out FILE` picks the file. To capture the real prompts for a
later `messages-bench --replay`, `ollama-cache-probe --replay` or
`claude-ollama prefix-ab`, launch with `CLAUDE_OLLAMA_PROXY_RECORD=1` once; the
report then names the record folder and how many requests it holds.

Sample `doctor` output (all healthy):

```
ok   jq on PATH
ok   model qwen3.8-27b-cc
ok   embedding model qwen3-embedding:0.6b
ok   digest qwen3.8:27b-mlx matches its pin
ok   num_ctx 65536 leaves 4096 tokens over CLAUDE_CODE_MAX_CONTEXT_TOKENS 53248 plus output 8192 (reserve 4096)
ok   hook bash-output-guard.py present
ok   ollama reachable at http://localhost:11434
ok   server env OLLAMA_FLASH_ATTENTION=1
```

### Trusted models

Every model the harness pulls comes from the Ollama library and is pinned by the
sha256 of its registry manifest in `ollama/model-digests.json`. After pulling a
base, and before each launch, `claude-ollama` compares the digest Ollama reports
in `/api/tags` with the pin and exits 1 on a mismatch; `doctor` prints
`ok   digest NAME matches its pin` or a `fail` line.

The two GGUF sizes come from Unsloth on Hugging Face. Each is pinned twice: its
file's sha256 in `model-digests.json` and a repo commit in `sizes.json`. The
first launch of that size downloads the file (about 17.6 GB or 22.4 GB, plus
Ollama's copy while importing), checks the sha256, runs `bin/gguf-inspect` on
the header, imports with Ollama's own renderer and parser (the file's chat
template is not used), and deletes the download. Changing a pin means repeating
a review: run `bin/gguf-inspect` on the new file's header and diff its chat
template against upstream's. These sizes have no vision: the projector file is
not used, so image paste does not work on them.

### The command sandbox

Bash runs in Claude Code's own sandbox. Each `ollama/settings.<size>.json` sets
it: writes go to the project, a temp dir and `~/.cache/claude-sandbox`; the
network reaches loopback addresses (dev servers, and so Ollama's own API on
11434), `github.com`, `registry.npmjs.org`, `proxy.golang.org`,
`sum.golang.org`, `pypi.org`, `files.pythonhosted.org`,
`objects.githubusercontent.com`, `codeload.github.com` and `context7.com` (the
`/find-docs` skill), and any other host prompts first; sandboxed commands cannot
read SSH keys, cloud credentials, the keychain, `~/.claude`, `~/.qwen` or the
console state folder. `GH_TOKEN`, `GITHUB_TOKEN` and `SHORTCUT_API_TOKEN` are
unset for sandboxed commands. The launcher runs `claude` through
`shared/sandbox-env`, which points Go, npm, pnpm, pip, uv, yarn and bun at
caches under `~/.cache/claude-sandbox`, so `go test` and `pnpm install` work
inside the sandbox while the caches your own shell and the hooks execute from
(`~/.npm/_npx`, `~/Library/pnpm`, `~/go/pkg/mod`, `~/.cache/claude-custom`,
which holds the Stop hook's log and the machine copy of the personal overlay)
stay unwritable. Hooks and the MCP servers run outside the sandbox through
`shared/host-env`, which drops those cache variables again, so a hook's
`go test` or `npx fallow` never executes from the sandbox's cache (a
`GOMODCACHE` of your own is dropped with them for that one process). Sandboxed
commands run without a prompt (`autoAllowBashIfSandboxed: true`), which is what
lets a skill's `!` commands such as `git status` run; `git commit`, `git push`
and `Bash(dangerouslyDisableSandbox:true)`, a retry outside the sandbox, still
ask, and `git-push-guard.py` denies a push written as `git -C`, `--git-dir` or a
path to `git`, which that ask would miss.

The launcher also puts nvm's Node first on PATH before the hand-off. nvm is a
shell function loaded from `.zshrc` or `.bashrc`, so a session started from
fish, a cmux command or launchd otherwise falls back to Homebrew's Node and
`npx` runs the wrong version. With `~/.nvm` (or `$NVM_DIR`) installed, the
launcher reads the nearest `.nvmrc` above the working folder, else nvm's
`default` alias, picks the newest installed match and prints
`claude-ollama: node: <path> (nvm 20 from /path/.nvmrc)`; `claude-ollama doctor`
reports the same `node` line.

Six command families run outside the sandbox through `excludedCommands`: `cmux`,
`gh`, `short`, `git push`, `claude-custom ctx7` (the `/find-docs` CLI, which
then uses your own network, proxy and certificates, and resolves the pinned
`ctx7` from `~/.cache/claude-custom`, which the sandbox cannot write) and `pnpm`
(inside the sandbox its hardlinks from the store fail with EPERM and corrupt
`node_modules/.pnpm`, so installs and tests kept breaking). All but `ctx7` still
prompt. An exclusion applies only when every segment of the command line
matches, so a piped `claude-custom ctx7 ... | head` runs inside the sandbox;
`shared/hooks/dev-server-guard.py` therefore denies a `pnpm` that shares its
line with `cd &&`, a pipe or `;` and asks for `pnpm -C DIR SCRIPT`, and denies
`pnpm exec`, `dlx`, `x` and `create`, which would run any package unsandboxed
(`npx` inside the sandbox covers those). MCP servers and hooks run outside the
sandbox too, as they do in the personal overlay.

What this gives up, compared with the older session sandbox:

- The browser is not locked to localhost. `page_check` opens only loopback URLs
  and every page tool sends the browser back to the dev server when the page has
  left it (and refuses when it cannot), but the page itself may load anything:
  cmux's WKWebView does not support request routes, so there is no allowlist.
  The page opens in a cmux browser profile named `claude-ollama` (its own
  cookies and storage, added when missing), never in your own.
- The GitHub read tools reach the project's `origin` and the repositories listed
  one `owner/name` per line in `~/.config/claude-custom/gh-repos` (`#` starts a
  comment; the sandboxed session cannot write the file). Writes such as
  `gh pr comment` are plain Bash commands behind the `Bash` prompt.
- `short` runs as the user's own command after the `Bash` prompt.
- `git fetch`, `pull` and `push` use the user's own git credentials.
- Loopback is open on every port, so a session can call Ollama's API (pull or
  delete models); `claude-ollama` checks the model pins before each launch.
- Hooks run the project's own tools (`node_modules/.bin`, the `npx fallow`
  fallback) outside the sandbox, and the session can write the project, so a
  binary planted there runs as you. That comes with running project tooling from
  hooks; the sandbox cache folder keeps it from spreading to `~/.npm`,
  `~/Library/pnpm` or `~/go`.
- Qwen Code's Seatbelt profile cannot name hosts: outbound TCP is loopback plus
  ports 443 and 80 anywhere.

`bin/ollama-models` manages the installed models:

- `list` marks each one `pinned`, `mismatch` (pinned, different digest),
  `profile` (a `-cc` model a profile uses), `orphan` (a `-cc` model no profile
  uses), `third-party` (not from the Ollama library) or `other`.
- `prune` lists the `third-party` and `orphan` models, asks, then runs
  `ollama rm` on them (`--yes` skips the question).
- `outdated [NAME...]` compares each pin with the manifest the registry serves
  now and prints `current`, `behind`, `unknown` (no manifest), `skipped` (a GGUF
  file pin, checked by hand) or `unpinned` (a name with no pin). It exits 1 when
  a pin is behind or a name is unpinned. Each `behind` or `unpinned` line is
  followed by an indented `fix:` line with the command to run:
  `bin/model-upgrade SIZE` when the pin is a size's base in `sizes.json`, else
  `bin/ollama-models pin NAME`. A count line (`2 behind, 0 unpinned: ...`) ends
  the listing when anything needs a fix.
- `pin NAME[:TAG]` fetches the manifest from `registry.ollama.ai`, writes its
  sha256 to `ollama/model-digests.json` and prints it.

To move a base to a newer upstream tag, run `bin/ollama-models outdated` to see
which pins are behind, then `bin/model-upgrade SIZE`. It pulls the new base into
`MODEL-next`, runs the thinking check and the cache probe (and the review eval
with `--eval`), saves `~/bench-results/upgrade-SIZE-*.json` and prints the `pin`
command. It never writes the pin: run that command, review the diff and commit.

To compare Ollama with other servers, see [backend-bench](backend-bench.md).

### Qwen Code

`claude-ollama qwen [size] [qwen args...]` (or `claude-custom qwen ...`) runs
Qwen Code (`brew install qwen-code`) instead of Claude Code on the size's `-cc`
model: same model preparation and warm-up, same `semantic_search`, `repo` and
`dev` MCP servers. `claude-ollama qwen --print-config [size]` prints the
command. The point is a comparison: Qwen Code keeps its own system prompt and
tool schemas, which are written for Qwen models.

Qwen Code reads `~/.claude-ollama/qwen` as its home (`QWEN_HOME`), never your
`~/.qwen`, which the policy also hides from both harnesses. Each launch rewrites
`settings.json` there from `ollama/qwen-settings.template.json` (model,
`localhost:11434/v1`, the Modelfile's `num_ctx` as `contextWindowSize`,
`reasoning_effort: none` in `extra_body` so Ollama skips thinking, 30-minute
timeouts, `agent`, `web_fetch`, `web_search` and `notebook_edit` off, usage
statistics and auto-update off) and `QWEN.md` (the preferences file,
`ollama/QWEN.local.md`). Each launch rewrites `settings.json`, `QWEN.md` and the
Seatbelt profile from the repo, so a change the session makes to them lasts one
session at most. Qwen Code also reads the project's `.env`, which a session can
write, so the profile's `advanced.excludedEnvVars` keeps `QWEN_SYSTEM_MD` (a
replacement system prompt), the model and key variables and `SEATBELT_PROFILE`
out of it; `QWEN_SANDBOX`, `QWEN_HOME` and the approvals and trust paths are
excluded by Qwen Code itself. `--approval-mode auto-edit` approves edits and
asks before every shell command (the Claude profiles no longer ask for sandboxed
commands; Qwen's Seatbelt profile is coarser). An outer `OPENAI_API_KEY`,
`OPENAI_BASE_URL`, `OPENAI_MODEL`, `QWEN_MODEL` or `QWEN_SANDBOX` never reaches
the session.

Not yet wired for Qwen Code: the hooks (Qwen Code's hook contract matches Claude
Code's, but the hooks match Claude tool names), the picker and the console.
`claude-ollama qwen doctor [size]` checks qwen, the model, context sizes, the
settings template and Ollama, and warns while no hooks are wired. Qwen Code runs
as a whole inside macOS Seatbelt (`tools.sandbox: "sandbox-exec"` in the
template and `QWEN_SANDBOX=sandbox-exec` from the launcher; `SANDBOX` is never
exported, since Qwen Code turns its sandbox off when it is set). The profile is
`ollama/qwen-sandbox.sb`; Qwen Code looks a custom profile up only at
`.qwen/sandbox-macos-<name>.sb` under the current folder, so each launch copies
it to `.qwen/sandbox-macos-claude-ollama.sb` in the project and lists that path
in `.git/info/exclude`. Inside: the project, the temp dir, `QWEN_HOME` and
`~/.cache/claude-sandbox` (the launcher runs `qwen` through `shared/sandbox-env`
too) are writable, `~/.ssh`, `~/.aws`, `~/.config/gh`, `~/.config/context7`,
`~/.npmrc`, the keychain, `~/.claude`, `~/.qwen` and the console state are
unreadable, and outbound TCP reaches loopback (Ollama, dev servers) plus ports
443 and 80 anywhere. `GH_TOKEN`, `GITHUB_TOKEN` and `SHORTCUT_API_TOKEN` are
unset for the launch. `gh` and `git push` fail inside (no keychain, no SSH): run
them from your own terminal. Without `sandbox-exec` (Linux), the launcher says
so and Qwen Code runs as you. `claude-ollama qwen --print-config` and
`qwen doctor` report the sandbox.

### Dev servers and the browser

The `dev` MCP server gives the session ten tools: `dev_status` (which dev
servers answer, at which URL and pid), `dev_start` (runs a `dev` or `start`
script in the background and returns its real URL), `dev_logs` (the server's
output, optionally only errors with their stacks), `dev_errors` (Next.js 16+
`get_errors`, or the log's errors otherwise), `dev_stop`, `dev_deps` (whether a
package dir's `node_modules` is installed and newer than its lockfile, and the
installed version of each named package or of every dependency), `dev_install`
(runs the lockfile's package manager: `install` with no packages, or `add` of
the named packages, `dev: true` for devDependencies, then `dev_deps` for them),
`page_check` (opens or reloads a page in the cmux browser and returns its
browser errors, console warnings and Next.js errors), `page_snapshot` (the open
page's elements with refs) and `page_act` (click, fill, type, press, select,
check or scroll one ref, then the errors it caused). `dev_start`, `dev_stop` and
`dev_install` ask before they run; the others do not. Bash
`pnpm -C DIR install|add|test` runs outside the sandbox after the Bash prompt
(see `excludedCommands` above), so the model may use either, and `dev_deps`
replaces listing `node_modules`; `tool-nudge.py` refuses only a Read inside
`node_modules` until `/find-docs` ran (a package's own
`node_modules/<name>/package.json` is exempt), and Bash is never gated there.
Servers a session starts stop when it ends. The server reads `.next/dev/lock`
for its port and `/_next/mcp` on Next.js 16+; other frameworks get log errors
only. The tools keep the scheme the server prints, so a server started with
`--experimental-https` (or whose `.next/dev/lock` `appUrl` is `https://`) is
probed and opened over `https://localhost:PORT`; when a candidate does not
answer over one scheme the other is tried, so an https server with no https hint
is still found; the probe accepts the local self-signed certificate, and
candidates are still `localhost` only. `page_check` also takes `url`, any
`http://` or `https://` URL on `localhost`, `127.0.0.1` or `[::1]`, and opens it
without probing, for servers `dev_status` cannot see. Bash `open` on a local URL
is denied by `shared/hooks/dev-server-guard.py`, which points the model at
`page_check`. `dev_status` also finds servers listening from the project folder
through `lsof`, whatever their port; those listeners never block `dev_start`.
The page tools run plain `cmux browser` commands: the first `page_check` opens a
browser split beside the terminal without taking focus, in the `claude-ollama`
browser profile, later calls navigate that surface (or open a new one when it
was closed), and the tools read its `console list`, `errors list` and
`snapshot --interactive`. Before a snapshot or an action, and after one, the
tools check the page is still on a loopback URL and send it back to the dev
server otherwise; selectors and text go to cmux as `--selector=` and `--text=`
so a value can never be read as an option. They need a cmux terminal
(`CMUX_SOCKET_PATH` set and `cmux` on `PATH`); `CLAUDE_OLLAMA_CMUX=0` turns them
off. In claude-ollama sessions the Bash guard denies `pnpm dev` and similar
starts, and only there.

The appended prompt (`ollama/CLAUDE.local.md`) carries only what every turn
needs; the situational rules live in `ollama/rule-cards/<id>.md`, and
`shared/hooks/rule-cards.py` adds each card to the context once per session, the
first time a tool call matches its triggers (a file suffix or folder, a command
such as `git commit` or `pnpm`, or a tool such as Write), so a session that
never touches Go never pays for the Go rules. `claude-ollama doctor` counts the
cards and names a malformed one. `CLAUDE_OLLAMA_RULE_CARDS=0` (the console's
"Deliver rule cards just in time" switch) turns the hook off, and
`CLAUDE_OLLAMA_RULE_CARDS_DIR` points it at another folder of cards.

`shared/hooks/edit-nudge.py` watches decode waste the same way: it never denies,
but adds one line of context when an Edit echoes a long `old_string` to change a
few lines, a Write rewrites an existing file over 60 lines, or a MultiEdit
carries more than 8 edits. Each nudge is a `"kind": "nudge"` telemetry line with
its rule id, which `bin/tool-telemetry-report` counts in its `output` section
beside the median and p90 input bytes of Edit and Write calls.
`CLAUDE_OLLAMA_EDIT_NUDGE=0` (the console's "Nudge wasteful edits" switch) turns
it off.

In a cmux terminal the launcher also appends `ollama/CLAUDE.cmux.md` to the
session prompt, which tells the model to open every markdown file it writes with
the vendored `/cmux-markdown` skill (`ollama/skills/cmux-markdown`, pinned to
the cmux repository in its `UPSTREAM` file). The skill runs
`cmux markdown open FILE`, a command excluded from the sandbox, so it asks once
before the panel opens and re-renders on every later save.

### Reviewing a pull request locally

`claude-ollama review [size] PR [--post] [--json]` reviews a GitHub pull request
with the size's model, without Claude Code. `bin/pr-review-local` fetches the PR
with `gh` and `git` (no checkout in the user's tree), skips binaries, lockfiles
and vendored paths, runs Fallow on changed TypeScript
(`audit --base <merge-base>`, introduced findings only) in a temporary worktree
of the PR head that it removes afterwards, and sends one `/v1/messages` request
per changed file: the PR description, the file's diff with 20 lines of context,
the whole file when it is under 400 lines, comments reviewers already left, and
a checklist. The checklist adds pitfall notes for the file's language, chosen by
suffix or shebang (Python, shell, TypeScript/JavaScript, Go) and for test files,
so a shebang-only script still gets the shell notes. A finding is blocking only
when a normal, expected input gives a wrong result, a crash, lost data or a
security hole; malformed input, style and unlikely misuse are non-blocking. The
prompts number every diff and file line, so findings name the line in the new
file. Documentation files (`.md`, `.mdx`, `.rst`, `.txt`, `.adoc`) are reviewed
from the diff only, with a docs note, and their findings never block. The model
answers with a JSON array of findings; a reply that is not JSON is retried once
and then the file is listed as skipped. The verdict is a fixed rule (any
blocking finding → REQUEST CHANGES; any other finding → APPROVE WITH COMMENTS;
else APPROVE); the model only writes the one-sentence summary. The report has
the same sections as the `pr-review` agent (see [install](install.md)):
Blocking, Non-blocking, Nits, Praise, Fallow and Not checked, which always says
that files were reviewed one at a time. Nothing is posted unless `--post` is
given, and then only as a comment review. Expect a 27b to take tens of seconds
per file. While it runs, stderr names each stage (fetch, files to review, each
file before its request, retries, Fallow, summary, CI, post), prints each
finding as one line (`[i/N] path:   issue (blocking)  path:line  summary`) as
soon as the model finishes it, and prints `waiting for the first token, Ns`
every 10 seconds (`--heartbeat-seconds`) until the first token arrives. On a
terminal, one status line shows the wait and the writing in place, and colors
follow `--color auto|always|never` (`auto` colors only a terminal and honours
`NO_COLOR`). stdout holds only the report, styled on a terminal and plain
otherwise.

Each review also writes an event log, one JSON object per line with `t`, `kind`
and the event's fields, flushed as it goes and ending with an `end` line whose
`status` is `ok` or `error`. The file is `YYYYmmdd-HHMMSS-<slug>.jsonl` in UTC
under `--log-dir DIR`, else `PR_REVIEW_LOG_DIR`, else
`~/.local/share/claude-custom/reviews`; `--no-log` turns it off. The log holds
each request's full prompt (`prompt`, with `system` and `user`) and the streamed
reply (`reply_text`), so a log can reach several MB; the directory is `0700` and
the files `0600`, and they stay local. The log opens at the `start` event, once
the PR is known, so stage lines and errors before it show on the terminal only,
and a failure before `start` writes no file. A log that cannot be written is
reported once and the review goes on. While `claude-ollama reviews` serves the
page, the review also prints a terminal-only `live at` link to that review's
page, read from `.web-url` in the log directory. A failed request names the
server's error message (for example a model that does not fit in memory), and a
failed summary is reported on stderr as well as in the report. The reviews page
has a Transcript tab that shows each prompt and the streamed reply, and a
`#transcript` link opens it directly.

`--range BASE..HEAD` reviews local commits instead of a PR, with the same
reviewer and report. It runs no `gh`, so there are no PR comments and no CI (the
report says `CI not checked (local range)`), and `--post` is refused.
`bin/pr-review-eval --model qwen3.8-27b-cc` runs every scenario in
`eval/pr-review/scenarios/` (`telemetry`, `shell-injection`, `async-ts`,
`go-errors`, `weak-test` and `clean-refactor`, the last with no bugs) through
`--range`, or only the ones named with `--scenario`. Each scenario prints a
`== NAME ==` header, one line per planted bug (`caught blocking`, `caught` or
`missed`), a `verdict` line that checks the reviewer's verdict against the
scenario's accepted verdicts, and a score line: bugs caught and caught as
blocking, false blockers (blocking findings on no planted bug), findings on the
clean files, unparsable replies and seconds. The run ends with a `total:` line
that sums them and counts right verdicts. Run it twice before trusting a
one-point change.

### Console

`claude-ollama ui [--port N]` serves a local console at `http://127.0.0.1:8765/`
(loopback only). Every page shares one sidebar that marks the current page and
collapses to icons. Its home page links to each section; the reviews list is at
`/reviews` in the log directory (`$PR_REVIEW_LOG_DIR`, else
`~/.local/share/claude-custom/reviews`), and `claude-ollama reviews [--port N]`
runs the same server and prints that link. A running review streams live: its
changed files, per-file progress, findings and verdict appear as the reviewer
writes them, and finished reviews stay listed. The page only reads those logs;
it calls no model. The first run installs and builds `web/console` with pnpm
(Node 22 or later and pnpm 10 are required; `brew install pnpm` if pnpm is
missing). `/fetch-domains` edits the web fetch hosts file
(`~/.config/claude-custom/fetch-domains`): it toggles suggested docs sites and
adds hosts, checked with the launcher's hostname pattern, and each save takes
effect at the next launch; its saves also appear in `/history`. `/workspaces`
lists the folders recorded in the launcher's own `~/.claude-ollama/.claude.json`
(plain `claude` keeps a separate list in `~/.claude.json`), whether each is
trusted, and the skills under its `.claude/skills` with their frontmatter name
and whether the model may invoke them. Claude Code loads a project's skills,
settings and hooks only in a trusted folder, so an untrusted one shows no
project skills in the `/` menu. A switch sets `hasTrustDialogAccepted` for that
folder, and the form trusts a new folder by its real path (it must exist on this
machine); each save lands in `/history`. A trusted folder's "Check skills"
button (an untrusted folder gets none, and the API refuses it, since a print
mode session runs the folder's own hooks without the trust dialog) runs
`bin/skill-check --size SIZE FOLDER`, which starts `claude-ollama` there in
print mode (`-p hi --max-turns 1 --output-format stream-json --verbose`, with
the indexer, draft opener and telemetry off), reads the `init` event's `skills`
array, stops the launch, and prints JSON with the Claude Code version, that
array and any error (the stderr tail when no session started within `--timeout`
seconds, 120 by default); `CLAUDE_OLLAMA_LAUNCHER` and `CLAUDE_BIN` override the
commands in tests. The page compares the array with the skills it found in the
folder and names the ones Claude Code skipped, which points at a `SKILL.md`
frontmatter Claude Code rejects (an unquoted colon in the description, a name
with spaces or capitals). A per-size profile,
`~/.config/claude-custom/profiles/ollama-<size>.json`, overrides that size's
launch (every key optional):

```json
{
  "tools": { "WebFetch": "allow", "Glob": "off" },
  "context": 65536,
  "thinking": true,
  "parameters": { "temperature": 0.6 },
  "mcp": { "dev": false },
  "env": { "CLAUDE_OLLAMA_TELEMETRY": "0" }
}
```

`tools` takes `default|allow|ask|deny|off` per tool: `allow` and `ask` add the
tool to `--tools` and the settings, `off` and `deny` remove it, `default` leaves
it. `Agent` cannot be enabled for Ollama (there is no side model). A `context`,
`output_tokens` (1024 to 16384, the console's "Output tokens per reply" field)
or `parameters` override recreates the `-cc` model at launch, as the Modelfile
drift fix does, and `doctor` checks the same values. `thinking: true` turns the
model's thinking on for that size (off by default, see above). `env` takes only
the harness switches, each `0` or `1` unless noted:

| Key                             | Default | Meaning                                                                        |
| ------------------------------- | ------- | ------------------------------------------------------------------------------ |
| `CLAUDE_OLLAMA_PROXY`           | 1       | Observe prompt drift through the messages proxy                                |
| `CLAUDE_OLLAMA_RULE_CARDS`      | 1       | Deliver rule cards just in time                                                |
| `CLAUDE_CODE_EFFORT_LEVEL`      | xhigh   | Thinking effort when thinking is on (`low`, `medium`, `xhigh`; Qwen 3.8 only)  |
| `CLAUDE_OLLAMA_RELAUNCH`        | 1       | Hand off before the context fills (`0`: single exec)                           |
| `CLAUDE_OLLAMA_HANDOFF_PCT`     | 70      | Hand off at this whole percent of context, 30 to 85                            |
| `CLAUDE_OLLAMA_NO_INDEX`        | 0       | Skip the code search index                                                     |
| `CLAUDE_CUSTOM_FRICTION`        | 1       | Reset a looping guard after three identical denials                            |
| `CLAUDE_OLLAMA_LADDER`          | 1       | Degrade rung by rung on incident evidence                                      |
| `CLAUDE_OLLAMA_TEST_AFTER_EDIT` | suggest | After each edit: suggest the test (`suggest`), run it (`run`) or neither (`0`) |
| `CLAUDE_OLLAMA_EDIT_NUDGE`      | 1       | Nudge wasteful edits                                                           |
| `CLAUDE_OLLAMA_LEASE`           | 1       | Hold an Ollama residency lease and heartbeat                                   |
| `CLAUDE_OLLAMA_LEASE_HEARTBEAT` | 120     | Whole seconds between keep-alive heartbeats, 30-600                            |
| `CLAUDE_OLLAMA_FIT`             | 1       | Check memory fit before launch                                                 |
| `CLAUDE_OLLAMA_TELEMETRY`       | 1       | Session telemetry                                                              |
| `CLAUDE_OLLAMA_INCIDENTS`       | 1       | Record Ollama incidents                                                        |
| `CLAUDE_OLLAMA_PROXY_RECORD`    | 0       | Record every request body for replay benches                                   |
| `CLAUDE_OLLAMA_PROXY_STABILIZE` | 0       | Move volatile prompt lines after the stable prefix                             |
| `CLAUDE_OLLAMA_BEACON`          | 1       | Write a machine beacon at launch                                               |
| `CLAUDE_OLLAMA_OPEN_DRAFTS`     | 1       | Open drafts in the browser                                                     |
| `CLAUDE_OLLAMA_CMUX`            | 1       | cmux browser tools                                                             |

`CLAUDE_OLLAMA_TEST_AFTER_EDIT` drives `shared/hooks/test-after-edit.py`, which
runs after every Edit, Write or MultiEdit of a code file: `suggest` adds one
line naming the nearest test's command (`run now: ./shared/hooks/x.test.sh`,
`cd go && go test ./internal/x`, `pnpm -C web/console exec vitest run <file>`,
`pytest <file>`, or `.claude/verify <file>`), or the test path to write when
none exists; `run` executes that command for you with a 60 s timeout and reports
`tests: pass` with the seconds, `tests: FAIL` with the first failing lines, or a
timeout, never the whole log, and skips a rerun while neither the file nor its
test changed. `run` executes the test under macOS Seatbelt (`sandbox-exec` with
the same `ollama/qwen-sandbox.sb` profile as `claude-ollama qwen`: it can write
only the project, a scratch folder and `~/.cache/claude-sandbox`, and cannot
read your credentials); on any other platform, or without `sandbox-exec`, it
only suggests. It can be enabled only from the profile file, which the sandboxed
session cannot write, so leave it on `suggest` for a repo you do not trust. Even
in `run` the hook only suggests, naming the reason, when the edited file is
itself a test, when the test or `.claude/verify` was edited earlier in the
session (compared by inode, so a link or a rename does not hide it), when the
session's edit record cannot be read, or when the file lies outside the
session's folder.

The Profiles page's Env tab shows each one by that label with its default and a
help sentence, grouped under Prompt and context, Guards, Ollama residency,
Diagnostics and Browser; the `claude-code` profile sees only the fields that
apply to plain `claude` (telemetry, the index, drafts, cmux and the friction
guard). The `/settings` page tables every switch with its default and each
profile's value, linking to the editors; it changes nothing. Its Actions row
leads to `/diagnose`, where one click runs `claude-ollama why` and shows the
verdict, evidence, fix and prefix hit rate, one click writes a rescue report for
a size and offers Copy report and Open for the newest file in
`~/.claude-ollama/rescue/`, and two read-only cards list the rule cards (with a
link to the `CLAUDE_OLLAMA_RULE_CARDS` switch that turns their delivery off) and
the recovery recipes. The Logs page's Proxy tab links to the
`CLAUDE_OLLAMA_PROXY_RECORD` switch for recording request bodies to replay. A
variable already set in your shell wins. A symlinked profile stops the launch.
`claude-ollama --print-config SIZE` and `doctor` show the profile path and the
overrides in effect. `/history` lists every settings and LaunchAgent change,
with a diff and a Restore button; recording is on by default and
`CLAUDE_CUSTOM_HISTORY=off` turns it off. While it runs, the command writes the
page URL to `.web-url` in the log directory and removes that file when it exits.
The console token lives in `$CLAUDE_CONSOLE_STATE_DIR/tokens/<port>` (default
`~/.local/share/claude-custom/console/tokens/<port>`, mode `0600`), so two
consoles on different ports keep their own tokens. The token is not in the
environment; the session's sandbox denies reading both that folder and the
reviews folder. `pnpm --dir web/console demo --serve` serves fixture reviews
(every event kind) and a live replay.

#### Runs

`/runs` starts jobs from a fixed list (today: Run doctor for a configured size)
and streams each one live: a stage bar when the output has `[n/total] title`
lines, the latest progress line, the output and an end banner. Cancel stops a
running job. Every run is kept in `$CLAUDE_CONSOLE_STATE_DIR/runs` (default
`~/.local/share/claude-custom/console/runs`), one JSONL log per run, written by
`bin/console-run`; a run whose runner died shows as lost. Run logs are kept
until you delete them: nothing removes them. Only one run of a command runs at a
time.

The Reviews page starts a review too: its New review form takes a configured
size and a PR number (digits only), runs `claude-ollama review` as a run, and
links to the review once the log names it. It reviews the repository of the
folder `claude-ollama ui` was started from (shown on the form), so start the
console from the project you mean. The form never passes `--post`, so it never
posts comments to GitHub.

#### Health, Config and Logs

`/health` (Checks) reads the same checks as `claude-ollama doctor` for the size
you pick: a checklist that fills in row by row, with a summary such as "19 ok ·
2 warn · 4 fail", and the last ten doctor runs for that size, linked to `/runs`.
Its settings card shows `claude-ollama --print-config` for the size, with the
`command` value and a copy button. Both only read; "Run checks" starts a doctor
run as `/runs` does.

Under them, "More checks" has one card per further check, each with a Run
button, its latest result and a link to that run. Thinking check runs
`claude-ollama thinking-check` (it pulls the MLX sizes first, so it can be
slow). Config check runs `bin/check-config`. Outdated models runs
`bin/ollama-models outdated`. Qwen doctor runs `claude-ollama qwen doctor` for
the size you pick.

The run page shows doctor, Qwen doctor and outdated-model runs as the same
checklist instead of raw output. A `fix:` line under a failed check appears as
the command plus, when the console can run it, a button: "Upgrade SIZE" starts
`bin/model-upgrade SIZE` (the `model-upgrade` command), "Pin NAME" runs
`bin/ollama-models pin NAME` (`model-pin`; it changes
`ollama/model-digests.json`, so review and commit the diff) and "Apply server
env" runs `ollama-agent -apply` (`server-apply`). Each button opens the new run.

`/logs` follows the Ollama server log live. The path comes from
`claude-ollama logs --path` (LaunchAgent plist, else the Homebrew log, else
`~/.ollama/logs/server.log`). Lines are coloured by level (error red, warn
amber, debug muted), can be filtered by substring, and can be paused and resumed
(while paused, new lines are counted). The view keeps the last 5000 lines. It
starts from the last 64 KiB of the file and restarts from the top when the file
shrinks. The page only reads the log and never takes a path from the request.

The Incidents tab explains a "context get canceled" in a long session. Each
launch starts `ollama/incidents/watcher.py` beside the draft opener
(`CLAUDE_OLLAMA_INCIDENTS=0` turns it off): it follows the Ollama server log
from its end and the session's transcripts under `~/.claude-ollama/projects`,
and appends one JSON line per incident to
`$CLAUDE_CONSOLE_STATE_DIR/incidents/<launch>.jsonl`, with the newest line in
`<launch>.jsonl.latest` and the file's path in `incidents/current`. Causes:
`aborted` (`context canceled`: Claude Code dropped an in-flight request),
`evicted` (a model unloaded or a new runner started), `truncated`
(`truncating input prompt`: the prompt exceeded `num_ctx`), `reprefilled` (a
llama.cpp `prompt eval time = ... / N tokens` line within 300 tokens of `n_ctx`
or of the previous request's `total time ... / N tokens`: the prompt cache was
lost and the whole prompt ran again), `compacted` (a `compact_boundary` entry in
the transcript, with its `preTokens`) and `unknown` (a line naming the model or
a runner that fits no rule). Each line names the rule that matched it (such as
`reprefilled/prompt-eval`) and a `reprefilled` line says what the log showed
last before it (`after embed`, `after load`, `after unload`, `after expired`),
so a reprefill that follows an embedding request stands out. The tab shows a
count per cause above the lines and a classifier-health pill
(`saw N lines, M unmatched`) from the health row the watcher writes every
minute; a growing unmatched count means Ollama's log format changed.
`claude-ollama doctor` runs `watcher.py --check-rules` on the server log and
fails when no rule matches it any more. Inside the session,
`shared/hooks/incident-note.py` (UserPromptSubmit, Ollama profiles only) reads
`CLAUDE_OLLAMA_INCIDENTS_FILE` and adds one line of context when new incidents
appeared since your last prompt, such as
`last incident: evicted at 14:02 (the model was unloaded and reloaded); since the session started: aborted 1, evicted 1`.

Each launch also starts `bin/messages-proxy` between `claude` and Ollama
(`CLAUDE_OLLAMA_PROXY=0` turns it off): it forwards every request unchanged and
appends one line per `/v1/messages` request to
`$CLAUDE_CONSOLE_STATE_DIR/proxy/requests.jsonl` (default
`~/.local/share/claude-custom/console`, where the console's Proxy tab reads it)
naming the first section of the prompt (`system`, `tools` or `message:N`) that
differs from the previous request, the byte offset inside it and up to 200
characters from there, so a prompt-cache miss can be traced to what changed. It
never logs the rest of the body.

With `CLAUDE_OLLAMA_PROXY_STABILIZE=1` the proxy also stabilises the prefix:
when two requests in a row differ inside the system prompt by one short span (at
most 400 bytes once widened to whole lines) it learns those lines as volatile,
and a date-only or time-only line, or one starting with `Today's date`,
`Current date` or `The current time`, counts from the start. Every volatile line
is then moved to the end of the system text on each request, so the bytes before
it stay identical and Ollama's cache keeps them; nothing is dropped, tools are
never rewritten and messages are never touched. Each log row then lists the
moved lines (digits masked) as `stabilized` and their `moved_bytes`. To check
the gain before switching it on, record a session with
`CLAUDE_OLLAMA_PROXY_RECORD=1`, then run `claude-ollama prefix-ab [size]`: it
replays the recorded prompts verbatim and stabilised, one pass after the other
with the model unloaded in between, and prints a two-column hit-rate table with
`stabilize: worth it (+N points mean hit rate)` or `stabilize: no gain`.

#### Server

`/server` shows the `local.ollama` LaunchAgent's `OLLAMA_*` values next to the
recommended ones from `ollama/server.env`, and marks a value that differs. Eight
tuning variables are editable (`OLLAMA_KEEP_ALIVE`, `OLLAMA_MAX_LOADED_MODELS`,
`OLLAMA_NUM_PARALLEL`, `OLLAMA_MAX_QUEUE`, `OLLAMA_CONTEXT_LENGTH`,
`OLLAMA_FLASH_ATTENTION`, `OLLAMA_DEBUG`, `OLLAMA_KV_CACHE_TYPE`); each input
checks its value as you type, and Save stays disabled until every change is
valid. Save and reload runs `ollama-agent -set` for the changed values, and
Apply recommended runs `ollama-agent -apply`. Both stream inline, then the page
waits up to 30 s for Ollama to answer again. A running Ollama app or a loaded
brew service blocks both buttons. `OLLAMA_HOST`, `OLLAMA_ORIGINS` and
`OLLAMA_MODELS` stay read-only here: a wrong `OLLAMA_ORIGINS` lets web pages
call the local model, a wrong `OLLAMA_HOST` exposes it, and a wrong
`OLLAMA_MODELS` points at another folder. Change them with
`claude-custom agent`.

#### Speed check

`/speed-check` starts `claude-ollama speed-check` (it pulls up to four sizes and
takes a long time; it needs AC power and about 45 GB free) and lists every past
verdict in `~/bench-results`, newest first, with a button that copies the paste
block. A failed run is listed with a link to its run page, which shows the
`speed-check stopped` line. Files that do not parse are skipped.

#### Benchmarks

`/benchmarks` runs the six local measurements from fixed choices: messages-bench
(TTFT, prefill, decode and tool calls, with the thinking mode and prefix length
offered in the form), the prompt-cache probe, the review eval scorecard, the
task eval (`claude-ollama task-eval`, seconds to a green test) and the prefix
A/B (`claude-ollama prefix-ab`, which needs recorded traffic from
`CLAUDE_OLLAMA_PROXY_RECORD=1`), each for a configured size, plus bench-off runs
of one server and model. Each card notes that it uses the model now, so stop
other sessions first for clean numbers. The bench-off page embeds
`$BENCH_RESULTS/bench-off.html` (default `~/bench-results`) in a sandbox that
allows scripts only, and shows the install, download and run commands for the
terminal when no report exists yet. The console never runs
`backend-bench-off install`, `download` or `all`. History lists the last 20
bench runs. The telemetry card shows `tool-telemetry-report`; it stays off until
`CLAUDE_TOOL_TELEMETRY` is set, for sessions and for `claude-ollama ui`. The
Settings page's Tool budget card (`claude-ollama tool-budget` in the terminal)
joins the proxy log's per-request schema bytes with the telemetry's calls,
suggests the tools nothing called over the last 14 days, and applies that
suggestion to an Ollama profile after a confirm, so an unused schema stops
costing prefill on every cache miss.

#### Testing the console

`make smoke-console` (or `bin/console-smoke --port 8790`) starts the console on
a temp state dir and checks every page, the token gate and the same-origin rule,
then prints `all passed`. It starts no run and no model.
`bin/console-smoke --keep` leaves the console running and prints its link for a
look in the browser; the `kill` line it prints stops it. `make test` runs only
the script's stub test, because the real check needs a built console.

#### Models

`/models` lists every configured size with its model, base and a status
(installed, missing or mismatch against the pin), then each installed model with
its class, size on disk and whether Ollama has it loaded. It refreshes every 5
seconds and shows an Ollama-not-running banner when the server does not answer.
Prepare starts `claude-ollama prepare SIZE` as a run and shows its progress bar;
a missing size can take many gigabytes to download. The "Embedding model" card
shows the `semantic_search` model's name from `--print-config` and whether
Ollama has it; its "Set up" button runs `claude-ollama prepare-embedding` the
same way. Remove unused models opens a panel that lists exactly the third-party
and orphan models it would remove, with their total size, and starts
`ollama-models prune --yes --only NAME...` only after you press Remove these.
The page only previews: the script re-checks each name when it removes it, so a
model that stopped being prunable is skipped. The Models page shows each model
as pinned or mismatch; `model-upgrade` and `pin` are terminal commands, so the
page never changes a pin.
