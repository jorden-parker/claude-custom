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
are stale. To add a size, add an entry to `sizes.json`, run
`bin/ollama-profiles`, and commit. The picker and `--help` pick up a new size
without any script change.

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
context. Use `semantic_search` for wide searches instead; `tool-nudge.py`
refuses text searches (`grep`, `rg`, `ag`, `ack`, `git grep`, `find -name`)
until it has been called in the turn, and allows them once it has, even if it
errored. The profiles map no Claude ID to the main model: Claude Code names the
model after the ID that maps to it, so the banner would say Haiku or Sonnet.

Claude Code asks for adaptive thinking at high effort. Ollama only understands
enabled or disabled, so it would reason at high effort on every turn. The
profiles set `CLAUDE_CODE_EXTRA_BODY` to `{"thinking":{"type":"disabled"}}`,
which Ollama reads first. To measure it, run
`bin/messages-bench --thinking claude-code|disabled`.

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
searches rank by words only. The Homebrew service (`brew services start ollama`)
uses these paths; add any `server.env` value it lacks with
`claude-custom agent`:

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
`num_ctx` in the Modelfile matches `CLAUDE_CODE_MAX_CONTEXT_TOKENS`, whether
each hook named in `ollama/settings.<size>.json` exists and is executable under
`shared/hooks/`, whether Ollama answers at `OLLAMA_HOST`, and whether the
running server has every variable from `ollama/server.env`. Anything missing
exits 1. The server-env check is how to confirm `server.env` is applied. The
server's environment is read with `pgrep`/`ps` (or `/proc` on Linux).

`claude-ollama --print-config [size]` prints the resolved values (model, base
model, embedding model, context sizes, settings path, tools) and the exact
`claude` command, without launching.

`claude-ollama logs [-n LINES]` follows the Ollama server log with `tail -F` (50
lines of history by default). It reads the log path from the `local.ollama`
LaunchAgent plist when one exists, else uses the Homebrew service log
(`$HOMEBREW_PREFIX/var/log/ollama.log`), else the Ollama app's
`~/.ollama/logs/server.log`, and exits 1 when none exists. A server started by
hand with `ollama serve` prints to its own terminal and has no file to follow.

Sample `doctor` output (all healthy):

```
ok   jq on PATH
ok   model qwen3.8-27b-cc
ok   embedding model qwen3-embedding:0.6b
ok   digest qwen3.8:27b-mlx matches its pin
ok   num_ctx 65536 matches CLAUDE_CODE_MAX_CONTEXT_TOKENS
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
it: writes go only to the project and a temp dir, the network reaches only
`github.com`, `registry.npmjs.org` and local ports, and sandboxed commands
cannot read SSH keys, cloud credentials, the keychain, `~/.claude`, `~/.qwen` or
the console state folder. `GH_TOKEN`, `GITHUB_TOKEN` and `SHORTCUT_API_TOKEN`
are unset for sandboxed commands. The `Bash` ask rule still prompts before each
sandboxed command, and `Bash(dangerouslyDisableSandbox:true)` prompts before a
retry outside the sandbox.

Four command families run outside the sandbox through `excludedCommands`:
`cmux`, `gh`, `short` and `git push`. Each still prompts. MCP servers and hooks
run outside the sandbox too, as they do in the personal overlay.

What this gives up, compared with the older session sandbox:

- The browser has no live proof of its localhost lock. `shared/mcp/page.js`
  still locks the REPL session to `localhost`, `127.0.0.1` and `[::1]` before
  every request.
- The GitHub read tools work for any repository the user's `gh` can read. Writes
  such as `gh pr comment` are plain Bash commands behind the `Bash` prompt.
- `short` runs as the user's own command after the `Bash` prompt.
- `git fetch`, `pull` and `push` use the user's own git credentials.
- Qwen Code runs with no sandbox at all.

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
`ollama/QWEN.local.md`). The session cannot write those files, `system.md`,
`.env`, `skills`, `agents`, `extensions`, `rules` or `commands` there, nor any
`.qwen` folder in the project. Qwen Code also reads the project's `.env`, which
a session can write, so the profile's `advanced.excludedEnvVars` keeps
`QWEN_SYSTEM_MD` (a replacement system prompt), the model and key variables and
`SEATBELT_PROFILE` out of it; `QWEN_SANDBOX`, `QWEN_HOME` and the approvals and
trust paths are excluded by Qwen Code itself. `--approval-mode auto-edit`
approves edits and asks before every shell command, as the Claude profiles do.
An outer `OPENAI_API_KEY`, `OPENAI_BASE_URL`, `OPENAI_MODEL`, `QWEN_MODEL` or
`QWEN_SANDBOX` never reaches the session.

Not yet wired for Qwen Code: the hooks (Qwen Code's hook contract matches Claude
Code's, but the hooks match Claude tool names), `doctor`, the picker and the
console. Qwen Code runs with no sandbox of its own, so its commands run as you.

### Dev servers and the browser

The `dev` MCP server gives the session eight tools: `dev_status` (which dev
servers answer, at which URL and pid), `dev_start` (runs a `dev` or `start`
script in the background and returns its real URL), `dev_logs` (the server's
output, optionally only errors with their stacks), `dev_errors` (Next.js 16+
`get_errors`, or the log's errors otherwise), `dev_stop` and `page_check` (opens
or reloads a page in the cmux browser and returns its browser errors, console
warnings and Next.js errors), `page_snapshot` (the open page's elements with
refs) and `page_act` (click, fill, type, press, select, check or scroll one ref,
then the errors it caused). `dev_start` and `dev_stop` ask before they run; the
others do not. Servers a session starts stop when it ends. The server reads
`.next/dev/lock` for its port and `/_next/mcp` on Next.js 16+; other frameworks
get log errors only. The tools keep the scheme the server prints, so a server
started with `--experimental-https` (or whose `.next/dev/lock` `appUrl` is
`https://`) is probed and opened over `https://localhost:PORT`; the probe
accepts the local self-signed certificate, and candidates are still `localhost`
only. The page tools run `cmux browser repl` themselves with
`shared/mcp/page.js`, which locks the REPL session to `localhost`, `127.0.0.1`
and `[::1]` before each request: navigations, new tabs, `fetch`, subresources
and websockets. They need a cmux terminal (`CMUX_SOCKET_PATH` set and `cmux` on
`PATH`); `CLAUDE_OLLAMA_CMUX=0` turns them off. WebRTC (STUN/TURN) and DNS
prefetch are outside WebKit's content rules and are not covered by the lock. In
claude-ollama sessions the Bash guard denies `pnpm dev` and similar starts, and
only there.

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
(loopback only). Its home page links to each section; the reviews list is at
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
effect at the next launch; its saves also appear in `/history`. `/history` lists
every settings and LaunchAgent change, with a diff and a Restore button;
recording is on by default and `CLAUDE_CUSTOM_HISTORY=off` turns it off. While
it runs, the command writes the page URL to `.web-url` in the log directory and
removes that file when it exits. The console token lives in
`$CLAUDE_CONSOLE_STATE_DIR/tokens/<port>` (default
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

`/health` reads the same checks as `claude-ollama doctor` for the size you pick:
a checklist that fills in row by row, with a summary such as "19 ok · 2 warn · 4
fail", and the last ten doctor runs for that size, linked to `/runs`. Its
settings card shows `claude-ollama --print-config` for the size, with the
`command` value and a copy button. Both only read; "Run checks" starts a doctor
run as `/runs` does.

`/logs` follows the Ollama server log live. The path comes from
`claude-ollama logs --path` (LaunchAgent plist, else the Homebrew log, else
`~/.ollama/logs/server.log`). Lines are coloured by level (error red, warn
amber, debug muted), can be filtered by substring, and can be paused and resumed
(while paused, new lines are counted). The view keeps the last 5000 lines. It
starts from the last 64 KiB of the file and restarts from the top when the file
shrinks. The page only reads the log and never takes a path from the request.

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

`/benchmarks` runs the four local measurements from fixed choices:
messages-bench (TTFT, prefill, decode and tool calls, with the thinking mode and
prefix length offered in the form), the prompt-cache probe, and the review eval
scorecard, each for a configured size, plus bench-off runs of one server and
model. Each card notes that it uses the model now, so stop other sessions first
for clean numbers. The bench-off page embeds `$BENCH_RESULTS/bench-off.html`
(default `~/bench-results`) in a sandbox that allows scripts only, and shows the
install, download and run commands for the terminal when no report exists yet.
The console never runs `backend-bench-off install`, `download` or `all`. History
lists the last 20 bench runs. The telemetry card shows `tool-telemetry-report`;
it stays off until `CLAUDE_TOOL_TELEMETRY` is set, for sessions and for
`claude-ollama ui`.

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
model that stopped being prunable is skipped. Pinning stays in the terminal.
