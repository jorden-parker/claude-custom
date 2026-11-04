# Work harness (llama-server)

`claude-ollama` runs `claude` against Homebrew's llama.cpp `llama-server` in
router mode, one process that loads and unloads the sizes' presets on demand.
The names keep the old Ollama wording (`claude-ollama`, `~/.claude-ollama`,
every `CLAUDE_OLLAMA_*` variable, the `ollama/` folder, `ollama-lease`,
`ollama-models`, `ollama-agent`, the `ollama-<size>` profiles and the `-cc`
preset ids), though no Ollama server is involved.

Each size has its own pinned GGUF, preset id and profile file:

| Size  | Model                 | Weights (Hugging Face)                                            | Context | Preset id          |
| ----- | --------------------- | ----------------------------------------------------------------- | ------- | ------------------ |
| `27b` | Qwen 3.8 27B, dense   | `unsloth/Qwen3.8-27B-GGUF`, `Qwen3.8-27B-UD-Q4_K_XL.gguf`         | 64k     | `qwen3.8-27b-cc`   |
| `35b` | Qwen 3.6 35B-A3B, MoE | `unsloth/Qwen3.6-35B-A3B-GGUF`, `Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf` | 96k     | `qwen3.6-35b-cc`   |
| `3b`  | Granite 4.2 3B        | `ibm-granite/granite-4.2-3b-GGUF`, `granite-4.2-3b-Q4_K_M.gguf`   | 32k     | `granite4.2-3b-cc` |

Set up once, then launch (27b is the default size):

```sh
brew install llama.cpp        # llama-server, build 9200 or later
claude-custom install         # writes the presets and the local.llama-server LaunchAgent
claude-ollama prepare 27b     # downloads the pinned GGUF; optional, a launch does it too
claude-ollama 27b [args...]   # or plain claude-ollama
```

Any size:

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

Sizes are declared in `ollama/sizes.json`: each entry names its Hugging Face
repo, the pinned revision and the file (`gguf`), the preset id (`model`), the
context, `output_tokens` and the sampling `parameters`. `bin/ollama-profiles`
renders `settings.<size>.json` from `ollama/profile-template.json` and the
llama-server presets `ollama/models.ini` from the same entries; the rendered
files are committed, and `bin/ollama-profiles --check` fails when they are
stale. Each size's `output_tokens` caps one reply: it becomes the preset's
`n-predict` and the profile's `CLAUDE_CODE_MAX_OUTPUT_TOKENS` (decode is the
slow path on a laptop, every output token sweeping the active weights), and
`bin/check-config` fails when the two disagree with `sizes.json`. To add a size,
add an entry to `sizes.json` (with its sha256 in `ollama/model-digests.json`,
see [Trusted weights](#trusted-weights)), run `bin/ollama-profiles`, and commit.
The picker and `--help` pick up a new size without any script change.

The weights live in `~/.claude-ollama/weights/<file>`, never in the repo. Before
every launch `claude-ollama` downloads a missing or mismatched file from Hugging
Face at the pinned revision, checks it, and exits 1 when that fails.
`claude-ollama prepare [size]` does only that and exits;
`claude-ollama prepare-embedding` does the same for the `semantic_search`
embedding GGUF (`ollama/embedding.json`). `claude-custom install` downloads no
weights. `claude-ollama thinking-check` checks that each `@think` preset of the
27b and 35b thinks and the plain preset does not, and prints PASS or FAIL.

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

Thinking is off by default: each size's plain preset sets `reasoning = off`, and
the profiles also set `CLAUDE_CODE_EXTRA_BODY` to
`{"thinking":{"type":"disabled"}}`. To measure the difference, run
`bin/messages-bench --thinking claude-code|disabled`. To turn thinking on for
one size, set `"thinking": true` in its profile (the Model thinking switch on
the console's `/profiles/ollama-<size>` page, Sandbox & model tab): the session
then runs on the `<model>@think` preset, which sets `reasoning = on`, and the
launch drops that variable from the derived settings, so Claude Code's own
adaptive request reaches llama-server and the model reasons before every reply.
A profile with both `thinking` and `context` is refused. With thinking on, Qwen
3.8 (the 27b) also reads an effort level from the request through its chat
template (`low`, `medium`, `xhigh`); Claude Code's default `high` is not one of
them, so the model falls back to `xhigh`. The "Thinking effort when thinking is
on" select on the same profile page sets `CLAUDE_CODE_EFFORT_LEVEL` for the
launch, which outranks `/effort` and every settings file. Qwen 3.6 (the 35b) has
on/off only and ignores the level. Thinking tokens count against
`CLAUDE_CODE_MAX_OUTPUT_TOKENS`, and `thinking-check` measures the presets
themselves, since it never reads a profile. The profiles also set every
telemetry, error-report, survey, feedback-draft, update-check and
marketplace-install switch off (`DISABLE_TELEMETRY`, `DO_NOT_TRACK`,
`DISABLE_ERROR_REPORTING`, `DISABLE_AUTOUPDATER`, `DISABLE_BUG_COMMAND`,
`CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY`, `CLAUDE_CODE_SEND_FEEDBACK=0`,
`CLAUDE_CODE_DISABLE_OFFICIAL_MARKETPLACE_AUTOINSTALL`,
`CLAUDE_CODE_ENABLE_TELEMETRY=0`, `feedbackDrafts: off`,
`feedbackSurveyRate: 0`) beside `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC`, and
`bin/check-config` checks them.

Plain `claude` stays on the personal setup. The profile only exists for that
launch.

### Model picker

`go/cmd/model-picker/` is the terminal menu `claude-ollama` opens to choose a
size. Each `settings.<size>.json` in `ollama/` whose size is a key of
`sizes.json` is one entry, showing the size, its preset id and its `base` from
`sizes.json`. A last row "Set up embedding model" runs
`claude-ollama prepare-embedding` and stays in the menu.

```sh
claude-custom ollama                       # opens the picker, then launches the chosen size
cd go && go run ./cmd/model-picker ../ollama  # the picker on its own; prints the chosen size
```

Keys: `↑/k`, `↓/j`, `enter` to launch, `esc`/`q`/`ctrl+c` to cancel. Cancelling
launches nothing. The picker is built by `claude-custom install` and rebuilt on
launch only when a Go source file is newer than the binary. Details:
[`go/cmd/model-picker/README.md`](../go/cmd/model-picker/README.md).

### llama-server settings

The profiles expect one `llama-server` in router mode at `LLAMA_SERVER_URL`
(default `http://127.0.0.1:11435`), run by the LaunchAgent `local.llama-server`
(`~/Library/LaunchAgents/local.llama-server.plist`, with `RunAtLoad` and
`KeepAlive`):

```sh
llama-server --models-preset ~/.claude-ollama/presets/models.ini --models-max N \
  --host 127.0.0.1 --port 11435 --log-file ~/.claude-ollama/logs/llama-server.log --metrics
```

launchd's own output goes to `~/.claude-ollama/logs/llama-server.stdout.log`.
`claude-custom agent -apply` (`ollama-agent -apply`) writes and reloads that
agent; `claude-custom install` runs it, and stops a loaded `brew services`
`llama.cpp` first. `LLAMA_SERVER_BIN` names another binary for the agent to run
(default `llama-server` on `PATH`).

Every preset is a section of a preset file. `ollama/models.ini`, rendered from
`sizes.json`, has per size a `[<model>]` section (`reasoning = off`), a
`[<model>@think]` one (`reasoning = on`) and a `[<model>@<ctx>]` one at the
degrade ladder's lower context, plus the embedding preset
`[qwen3-embedding-0.6b]` with `alias = qwen3-embedding:0.6b`. The server reads
the user file `~/.claude-ollama/presets/models.ini` (0600), which
`bin/ollama-profiles --user-presets` writes: `models.ini` with the weights
folder filled in, plus `[<model>@<ctx>]` sections for a profile override's
`context` and a `[<model>@profile]` section when a profile sets `output_tokens`
or `parameters`. Before each launch `claude-ollama` renders that file and, when
it changed, runs `ollama-agent -apply`; it then waits for the server, exits 1
when `/models` lacks the session's preset id, and asks the router to load the
preset in the background so the first prompt doesn't wait for it.

The flags every preset shares are the `[*]` section of `ollama/server.ini`: all
layers on the GPU, flash attention, `q8_0` K and V caches, `parallel = 1` (one
request slot, so one KV cache), the prompt cache and checkpoint settings,
`sleep-idle-seconds = -1` (the router never unloads an idle model, so no
keep-alive request is needed) and `jinja = true` (the GGUF's chat template,
which tool calls and the thinking switch need). Its `[router]` section sets
`models-max = 2`, which goes on the agent's command line and keeps the main and
embedding presets loaded together: the launcher exports `CODE_SEARCH_EMBED=1`
and loads the embedding preset beside the session's, so `semantic_search` adds a
vector ranking through `/v1/embeddings`. At 1 the embedding preset would push
the main one out, so searches rank by words only.

Change a setting with `claude-custom agent` (the menu) or
`ollama-agent -set KEY=VALUE` (repeatable): the change goes to
`~/.claude-ollama/presets/server.local.ini`, which holds only the keys that
differ from `server.ini`, then the user presets are rendered again and the agent
reloads. Never edit the plist or the user presets by hand; the next `-apply`
rewrites them. Details:
[`go/cmd/ollama-agent/README.md`](../go/cmd/ollama-agent/README.md).

On a Mac that ran the old Ollama harness, `claude-custom install` boots out the
`local.ollama` LaunchAgent and prints how to remove the old Ollama models by
hand; it never runs `ollama` itself.

### Checking the setup

`claude-ollama doctor [size]` checks the environment without downloading or
launching anything (the checks live in `bin/claude-ollama-doctor`, which the
launcher runs with the resolved size). It needs `jq` on PATH
(`brew install jq`); without it the launcher exits with an error. It fails when
llama-server does not answer at `LLAMA_SERVER_URL`, when the size's preset or
the embedding preset is not in its `/models`, when the size's weights are
missing or fail their pin, when `ctx-size` in the preset does not cover
`CLAUDE_CODE_MAX_CONTEXT_TOKENS` (the `ok` line names the token count where
Claude Code will compact), or when a hook named in `ollama/settings.<size>.json`
is missing or not executable under `shared/hooks/`. It warns on a server build
below 9200 (`brew upgrade llama.cpp`), missing embedding weights, stale user
presets (`claude-custom agent -apply`), a GPU wired limit
(`iogpu.wired_limit_mb`) below the model plus its KV cache, naming the
`sudo sysctl` line that raises it, and a memory fit that is short. Anything that
fails exits 1.

`claude-ollama --print-config [size]` prints the resolved values (model, preset,
server URL and build, weights path, `models-max`, user presets file, embedding
model, context sizes, settings path, tools) and the exact `claude` command,
without launching.

`claude-ollama logs [-n LINES]` follows `~/.claude-ollama/logs/llama-server.log`
(the LaunchAgent's `--log-file`) with `tail -F` (50 lines of history by
default), and exits 1 when no log exists yet. `claude-ollama logs --path` prints
the path instead.

When something goes wrong on a machine you are not sitting at (the work laptop,
say), do not describe the symptoms: run `claude-ollama rescue` there and paste
the file it names. It writes one redacted markdown report under
`~/.claude-ollama/rescue/` with the `doctor` and `--print-config` output, the
sync fingerprint, llama-server's build and its presets with their status, the
lease holders and rung, the last incidents, the proxy's prefix hit rate and top
diverging sections, the launcher and server log tails, the newest handoff note
and free memory, and prints a five-line summary. Tokens become `<redacted>` and
your home folder becomes `~`, so the file is safe to paste; anything it cannot
read shows as `unavailable: <why>` rather than stopping the report. `--since 30`
narrows the proxy window, `--out FILE` picks the file. To capture the real
prompts for a later `messages-bench --replay`, `ollama-cache-probe --replay` or
`claude-ollama prefix-ab`, launch with `CLAUDE_OLLAMA_PROXY_RECORD=1` once; the
report then names the record folder and how many requests it holds.

Sample `doctor` output (all healthy, first lines):

```
ok   jq on PATH
ok   llama-server build 9200 on 127.0.0.1:11435
ok   preset qwen3.8-27b-cc listed
ok   preset qwen3-embedding:0.6b listed
ok   weights Qwen3.8-27B-UD-Q4_K_XL.gguf (sha256 matches)
ok   embedding weights Qwen3-Embedding-0.6B-Q8_0.gguf (sha256 matches)
ok   user presets current
ok   num_ctx 65536 matches CLAUDE_CODE_MAX_CONTEXT_TOKENS 65536; Claude Code compacts at 44344 tokens
ok   hook bash-output-guard.py present
```

### Trusted weights

Every GGUF the harness runs comes from Hugging Face at a pinned commit: a size's
`gguf` in `ollama/sizes.json` (and the embedding model's in
`ollama/embedding.json`) names an `unsloth/`, `ibm-granite/` or `Qwen/` `*-GGUF`
repo, a 40-hex revision and a file, and `ollama/model-digests.json` holds that
file's LFS sha256 under `<repo>/<file>`; `bin/check-config` checks both. A
download goes to `<file>.part` in the weights folder (resumed when it was cut
off) and is kept only when its sha256 equals the pin and `bin/gguf-inspect`
passes its header; `doctor` prints `ok   weights FILE (sha256 matches)` or names
the missing or mismatched file. llama-server runs with `jinja = true`, so the
file's own chat template is used. Changing a pin means repeating a review: run
`bin/gguf-inspect` on the new file's header (`--template-out PATH` saves its
chat template) and diff that template against the one you reviewed. No preset
loads a vision projector, so these sizes have no vision.

### The command sandbox

Bash runs in Claude Code's own sandbox. Each `ollama/settings.<size>.json` sets
it: writes go to the project, a temp dir and `~/.cache/claude-sandbox`; the
network reaches loopback addresses (dev servers, and so llama-server's API on
11435), `github.com`, `registry.npmjs.org`, `proxy.golang.org`,
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

Seven command families run outside the sandbox through `excludedCommands`:
`cmux`, `gh`, `short`, `git push`, `git commit`, `claude-custom ctx7` (the
`/find-docs` CLI, which then uses your own network, proxy and certificates, and
runs the ctx7 CLI that claude-custom install put in `~/.cache/claude-custom`
from the lockfile in `shared/ctx7`, which the sandbox cannot write; a session
never runs npm) and `pnpm` (inside the sandbox it cannot hardlink from your
store, so it picks another one and asks to wipe every `node_modules` linked from
yours, a prompt no tool answers; `git commit` is out for the same reason, since
lefthook and husky hooks run pnpm). All but `ctx7` still prompt.
`shared/sandbox-env` moves every package cache but pnpm's content store into the
sandbox cache folder, so pnpm outside the sandbox keeps linking from the store
your `node_modules` already uses. An exclusion applies only when every segment
of the command line matches, so a piped `claude-custom ctx7 ... | head` runs
inside the sandbox; `shared/hooks/dev-server-guard.py` therefore denies a `pnpm`
that shares its line with `cd &&`, a pipe or `;` and asks for
`pnpm -C DIR SCRIPT`, and denies `pnpm exec`, `dlx`, `x` and `create`, which
would run any package unsandboxed (`npx` inside the sandbox covers those). MCP
servers and hooks run outside the sandbox too, as they do in the personal
overlay.

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
- Loopback is open on every port, so a session can call llama-server's API (load
  or unload presets); it cannot write the weights folder, and `claude-ollama`
  checks the weights against their pins before each launch.
- Hooks run the project's own tools (`node_modules/.bin`, the `npx fallow`
  fallback) outside the sandbox, and the session can write the project, so a
  binary planted there runs as you. That comes with running project tooling from
  hooks; the sandbox cache folder keeps it from spreading to `~/.npm`,
  `~/Library/pnpm` or `~/go`.
- Qwen Code's Seatbelt profile cannot name hosts: outbound TCP is loopback plus
  ports 443 and 80 anywhere.

`bin/ollama-models` manages the GGUF files in `~/.claude-ollama/weights`
(`CLAUDE_OLLAMA_WEIGHTS_DIR` overrides the folder):

- `list` marks each file `pinned`, `mismatch` (its sha256 differs from the pin),
  `candidate` (a `.next` file from `model-upgrade`), `orphan` (no size or the
  embedding model names it) or `partial` (a `.part` download).
- `prune` lists the `orphan` and `partial` files, asks, then removes them
  (`--yes` skips the question).
- `outdated [SIZE...]` compares each size's (and `embedding`'s) pinned revision
  with the Hugging Face repo's `main` and prints `current`, `behind` or
  `unknown`. Each `behind` line is followed by an indented `fix:` line with the
  command to run: `bin/model-upgrade SIZE`, or
  `bin/ollama-models pin embedding`. A count line ends the listing when one is
  behind, and the exit status is 1.
- `pin SIZE [--revision REV]` writes the repo's `main` revision (or `REV`) into
  `ollama/sizes.json` (or `ollama/embedding.json`) and its LFS sha256 into
  `ollama/model-digests.json`, then runs `bin/ollama-profiles`.

To move a size to a newer upstream revision, run `bin/ollama-models outdated` to
see which pins are behind, then `bin/model-upgrade SIZE` while llama-server
runs. It downloads the newest `main` file to `<file>.next` in the weights
folder, adds a `[<model>@next]` preset to the user presets and restarts the
server, runs the thinking check and the cache probe on that preset (and the
review and task evals with `--eval`), saves
`~/bench-results/upgrade-SIZE-*.json` and restores the presets. On a pass it
replaces the weights with the candidate, runs
`ollama-models pin SIZE --revision REV` and prints the `git add` line: review
the diff and commit. On a fail it removes the candidate (`--keep` keeps it).

To compare llama-server with other servers (Ollama, oMLX, vllm-mlx), see
[backend-bench](backend-bench.md).

### Qwen Code

`claude-ollama qwen [size] [qwen args...]` (or `claude-custom qwen ...`) runs
Qwen Code (`brew install qwen-code`) instead of Claude Code on the size's plain
preset: same weights, presets and warm-up, same `semantic_search`, `repo` and
`dev` MCP servers. `claude-ollama qwen --print-config [size]` prints the
command. The point is a comparison: Qwen Code keeps its own system prompt and
tool schemas, which are written for Qwen models.

Qwen Code reads `~/.claude-ollama/qwen` as its home (`QWEN_HOME`), never your
`~/.qwen`, which the policy also hides from both harnesses. Each launch rewrites
`settings.json` there from `ollama/qwen-settings.template.json` (the preset id,
llama-server's OpenAI endpoint, `LLAMA_SERVER_URL` plus `/v1` (default
`http://127.0.0.1:11435/v1`), with the placeholder key
`LLAMA_SERVER_API_KEY=llama-server`, the preset's `ctx-size` as
`contextWindowSize`, `reasoning_effort: none` in `extra_body`, 30-minute
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
settings template and llama-server, and warns while no hooks are wired. The Qwen
staging, `qwen doctor` and `qwen --print-config` live in
`bin/claude-ollama-qwen`; the launcher runs its usual pre-launch steps first.
Qwen Code runs as a whole inside macOS Seatbelt (`tools.sandbox: "sandbox-exec"`
in the template and `QWEN_SANDBOX=sandbox-exec` from the launcher; `SANDBOX` is
never exported, since Qwen Code turns its sandbox off when it is set). The
profile is `ollama/qwen-sandbox.sb`; Qwen Code looks a custom profile up only at
`.qwen/sandbox-macos-<name>.sb` under the current folder, so each launch copies
it to `.qwen/sandbox-macos-claude-ollama.sb` in the project and lists that path
in `.git/info/exclude`. Inside: the project, the temp dir, `QWEN_HOME` and
`~/.cache/claude-sandbox` (the launcher runs `qwen` through `shared/sandbox-env`
too) are writable, `~/.ssh`, `~/.aws`, `~/.config/gh`, `~/.config/context7`,
`~/.npmrc`, the keychain, `~/.claude`, `~/.qwen` and the console state are
unreadable, and outbound TCP reaches loopback (llama-server, dev servers) plus
ports 443 and 80 anywhere. `GH_TOKEN`, `GITHUB_TOKEN` and `SHORTCUT_API_TOKEN`
are unset for the launch. `gh` and `git push` fail inside (no keychain, no SSH):
run them from your own terminal. Without `sandbox-exec` (Linux), the launcher
says so and Qwen Code runs as you. `claude-ollama qwen --print-config` and
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
replaces listing `node_modules`; Read and Bash are never gated there. Servers a
session starts stop when it ends. The server reads `.next/dev/lock` for its port
and `/_next/mcp` on Next.js 16+; other frameworks get log errors only. The tools
keep the scheme the server prints, so a server started with
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
  "parameters": { "temperature": 0.6 },
  "mcp": { "dev": false },
  "env": { "CLAUDE_OLLAMA_TELEMETRY": "1" }
}
```

`tools` takes `default|allow|ask|deny|off` per tool: `allow` and `ask` add the
tool to `--tools` and the settings, `off` and `deny` remove it, `default` leaves
it. `Agent` cannot be enabled for an `ollama-<size>` profile (there is no side
model). A `context` override runs the session on the `<model>@<ctx>` preset, and
`output_tokens` (1024 to 16384, the console's "Output tokens per reply" field)
or `parameters` on `<model>@profile`; `bin/ollama-profiles --user-presets` adds
those sections to the user presets at launch, and `doctor` checks the same
values. `thinking: true` runs the session on `<model>@think` (off by default,
see above). `env` takes only the harness switches, each `0` or `1` unless noted.
The table comes from `shared/profile-env.json`, the one catalogue of these
switches: add or change a switch there and run `bin/ollama-profiles`, which
rewrites this table and the console's copy.

<!-- profile-env:start -->

| Key                             | Default | Meaning                                                              |
| ------------------------------- | ------- | -------------------------------------------------------------------- |
| `CLAUDE_OLLAMA_PROXY`           | 1       | Observe prompt drift through the messages proxy                      |
| `CLAUDE_OLLAMA_PROXY_STABILIZE` | 0       | Move volatile prompt lines after the stable prefix                   |
| `CLAUDE_OLLAMA_RULE_CARDS`      | 1       | Deliver rule cards just in time                                      |
| `CLAUDE_CODE_EFFORT_LEVEL`      | xhigh   | Thinking effort when thinking is on (`low`, `medium`, `xhigh`)       |
| `CLAUDE_OLLAMA_RELAUNCH`        | 1       | Hand off before the context fills                                    |
| `CLAUDE_OLLAMA_HANDOFF_PCT`     | 70      | Hand off at (% of context), 30 to 85                                 |
| `CLAUDE_OLLAMA_NO_INDEX`        | 0       | Skip the code search index                                           |
| `CLAUDE_CUSTOM_FRICTION`        | 1       | Reset a looping guard after three identical denials                  |
| `CLAUDE_OLLAMA_LADDER`          | 1       | Degrade rung by rung on incident evidence                            |
| `CLAUDE_OLLAMA_TEST_AFTER_EDIT` | suggest | After each edit: suggest the test, or run it (`0`, `suggest`, `run`) |
| `CLAUDE_OLLAMA_EDIT_NUDGE`      | 1       | Nudge wasteful edits                                                 |
| `CLAUDE_OLLAMA_LEASE`           | 1       | Hold a residency lease                                               |
| `CLAUDE_OLLAMA_FIT`             | 1       | Check memory fit before launch                                       |
| `CLAUDE_OLLAMA_TELEMETRY`       | 0       | Session telemetry                                                    |
| `CLAUDE_OLLAMA_INCIDENTS`       | 1       | Record llama-server incidents                                        |
| `CLAUDE_OLLAMA_PROXY_RECORD`    | 0       | Record every request body for replay benches                         |
| `CLAUDE_OLLAMA_BEACON`          | 1       | Write a machine beacon at launch                                     |
| `CLAUDE_OLLAMA_OPEN_DRAFTS`     | 1       | Open drafts in the browser                                           |
| `CLAUDE_OLLAMA_CMUX`            | 1       | cmux browser tools                                                   |

<!-- profile-env:end -->

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
help sentence, grouped under Prompt and context, Guards, Model residency,
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
`claude-ollama thinking-check` (it benches the 27b and 35b presets, so it can be
slow). Config check runs `bin/check-config`. Outdated models runs
`bin/ollama-models outdated`. Qwen doctor runs `claude-ollama qwen doctor` for
the size you pick.

The run page shows doctor, Qwen doctor and outdated-model runs as the same
checklist instead of raw output. A `fix:` line under a failed check appears as
the command plus, when the console can run it, a button: "Upgrade SIZE" starts
`bin/model-upgrade SIZE` (the `model-upgrade` command; on a pass it changes
`ollama/sizes.json` and `ollama/model-digests.json`, so review and commit the
diff) and "Apply recommended settings" runs `ollama-agent -apply`
(`server-apply`) for a `claude-custom agent -apply` fix. Each button opens the
new run.

`/logs` follows the llama-server log live on its Server tab, beside the
Launcher, Incidents and Proxy tabs. The path comes from
`claude-ollama logs --path` (`~/.claude-ollama/logs/llama-server.log`). Lines
are coloured by level (error red, warn amber, debug muted), can be filtered by
substring, and can be paused and resumed (while paused, new lines are counted).
The view keeps the last 5000 lines. It starts from the last 64 KiB of the file
and restarts from the top when the file shrinks. The page only reads the log and
never takes a path from the request.

The Incidents tab explains a cancelled request or a slow turn in a long session.
Each launch starts `ollama/incidents/watcher.py` beside the draft opener
(`CLAUDE_OLLAMA_INCIDENTS=0` turns it off): it follows the llama-server log from
its end and the session's transcripts under `~/.claude-ollama/projects`, and
appends one JSON line per incident to
`$CLAUDE_CONSOLE_STATE_DIR/incidents/<launch>.jsonl`, with the newest line in
`<launch>.jsonl.latest` and the file's path in `incidents/current`. Causes:
`aborted` (`http client error: Canceled`: Claude Code dropped an in-flight
request), `evicted` (the router stopped or evicted a model instance, or spawned
a new one), `truncated` (`exceeds the available context size`: the prompt
exceeded the preset's `ctx-size`), `reprefilled` (a
`prompt eval time = ... / N tokens` line of 1000 tokens or more within 300
tokens of `n_ctx` or of the previous request's `total time ... / N tokens`, or
`forcing full prompt re-processing`: the prompt cache was lost and the whole
prompt ran again), `compacted` (a `compact_boundary` entry in the transcript,
with its `preTokens`) and `unknown` (a line naming the session's preset or an
`instance` that fits no rule); the launcher adds `relaunched` (a handoff
relaunch) and `recovered` (a rung promoted back up), and the degrade ladder adds
`degraded` (a rung fired). Every writer goes through
`ollama/incidents/incident_log.py`, which owns the record (`ts`, `cause`,
`detail` cut at 200 characters, `tokens`, `rule`, plus `preceded_by` on
`reprefilled` only) and refuses a cause missing from
`ollama/incidents/causes.json`, the cause list with each cause's log level;
`bin/ollama-profiles` copies that file to
`web/console/src/lib/incident-causes.generated.json` for the console, and
`make check-profiles` fails when the copy is stale. Each line names the rule
that matched it (such as `reprefilled/prompt-eval`) and a `reprefilled` line
says what the log showed last before it (`after embed`, `after load`,
`after unload`), so a reprefill that follows an embedding request stands out.
The tab shows a count per cause above the lines and a classifier-health pill
(`saw N lines, M unmatched`) from the health row the watcher writes every
minute; a growing unmatched count means llama-server's log format changed.
`claude-ollama doctor` runs `watcher.py --check-rules` on the server log and
fails when no rule matches it any more. Inside the session,
`shared/hooks/incident-note.py` (UserPromptSubmit, `ollama-<size>` profiles
only) reads `CLAUDE_OLLAMA_INCIDENTS_FILE` and adds one line of context when new
incidents appeared since your last prompt, such as
`last incident: evicted at 14:02 (the model was unloaded and reloaded); since the session started: aborted 1, evicted 1`.

Each launch also starts `bin/messages-proxy` between `claude` and llama-server
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
it stay identical and llama-server's prompt cache keeps them; nothing is
dropped, tools are never rewritten and messages are never touched. Each log row
then lists the moved lines (digits masked) as `stabilized` and their
`moved_bytes`. To check the gain before switching it on, record a session with
`CLAUDE_OLLAMA_PROXY_RECORD=1`, then run `claude-ollama prefix-ab [size]`: it
replays the recorded prompts verbatim and stabilised, one pass after the other
with the preset unloaded and reloaded in between, and prints a two-column
hit-rate table with `stabilize: worth it (+N points mean hit rate)` or
`stabilize: no gain`.

#### Server

`/server` shows whether llama-server answers at `LLAMA_SERVER_URL` (`up`,
`loading` or `down`, with its build) and the settings of the
`local.llama-server` LaunchAgent from `ollama-agent -json`: each `[*]` key of
`ollama/server.ini` and `models-max`, with its current and recommended value,
marked when the two differ. Thirteen settings are editable (`models-max`,
`ctx-checkpoints`, `checkpoint-min-step`, `cache-ram`, `cache-type-k`,
`cache-type-v`, `flash-attn`, `parallel`, `batch-size`, `ubatch-size`,
`cache-reuse`, `prio`, `sleep-idle-seconds`); each input checks its value as you
type, and Save stays disabled until every change is valid. Any other key says to
edit `ollama/server.ini`. Save and reload runs `ollama-agent -set` for the
changed values (they land in `~/.claude-ollama/presets/server.local.ini`), and
Apply recommended runs `ollama-agent -apply`. Both stream inline, then the page
waits up to 30 s for llama-server to answer again. The Residency card shows the
lease holders, the session's rung and the last memory fit, with a "Promote back
up" button for a session on a degraded rung.

#### Speed check

`/speed-check` starts `claude-ollama speed-check` (it downloads the 27b and 35b
weights when they are missing and takes a long time; it needs AC power, and
about 45 GB free when it has to download) and lists every past verdict in
`~/bench-results`, newest first, with a button that copies the paste block. A
failed run is listed with a link to its run page, which shows the
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
`CLAUDE_OLLAMA_TELEMETRY=1` is set, for sessions and for `claude-ollama ui`. The
Settings page's Tool budget card (`claude-ollama tool-budget` in the terminal)
joins the proxy log's per-request schema bytes with the telemetry's calls,
suggests the tools nothing called over the last 14 days, and applies that
suggestion to an `ollama-<size>` profile after a confirm, so an unused schema
stops costing prefill on every cache miss.

#### Testing the console

`make smoke-console` (or `bin/console-smoke --port 8790`) starts the console on
a temp state dir and checks every page, the token gate and the same-origin rule,
then prints `all passed`. It starts no run and no model.
`bin/console-smoke --keep` leaves the console running and prints its link for a
look in the browser; the `kill` line it prints stops it. `make test` runs only
the script's stub test, because the real check needs a built console.

#### Models

`/models` talks to llama-server at `LLAMA_SERVER_URL` and refreshes every 5
seconds; when the server does not answer it shows a banner naming the URL. The
Sizes table lists every configured size with its preset id, weights file and a
state (installed, missing or mismatch against the pin); Prepare starts
`claude-ollama prepare SIZE` as a run and shows its progress, and a mismatch
says to run `claude-ollama doctor`. A missing size can take many gigabytes to
download. The "Embedding model" card shows the `semantic_search` model and its
file; its "Set up" button runs `claude-ollama prepare-embedding` the same way.
"On the server" lists the router's presets from `/models` with their status and
memory, with a Load or Unload button each. "Weight files" lists the files in
`~/.claude-ollama/weights` with their state and size; Remove unused files opens
a panel that lists exactly the orphan and partial files it would remove and
starts `ollama-models prune --yes --only FILE...` only after you confirm. The
page only previews: the script re-checks each name when it removes it, so a file
that stopped being prunable is skipped. Outdated models and Upgrade SIZE run
from the Health page and `pin` from the terminal, so this page never changes a
pin.
