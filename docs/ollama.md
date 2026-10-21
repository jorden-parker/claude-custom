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

`claude-custom install` creates the `-cc` models from `ollama/Modelfile.<size>`
once the base models are pulled. `claude-ollama` also does this itself for
either size: when the `-cc` model is missing, it pulls the base model and
creates the `-cc` model before starting `claude`. A failed pull stops the
launch.

The Haiku slot and all subagents run on a small side model, `qwen3:4b` from
`ollama/side.Modelfile`, created as `qwen3-4b-cc`. Set it up once from the
picker's "Set up side model" row. When it is missing, `claude-ollama` says so
and sends subagents and the Haiku slot to the main model for that session; pass
`--require-side-model` to exit instead. The profiles name it by ID in
`CLAUDE_CODE_SUBAGENT_MODEL` and map the full Claude Haiku IDs to it in
`modelOverrides`. They map no Claude ID to the main model: Claude Code names the
model after the ID that maps to it, so the banner would say Sonnet. Forcing
every subagent onto it needs Claude Code v2.1.257 or later.

The side model's context is 32k (`num_ctx` in `ollama/side.Modelfile`), smaller
than any size's. A subagent loads it next to the main model, and two 96k KV
caches plus the 27b's weights froze a 48 GB Mac. A subagent prompt over 32k is
cut by Ollama, since Claude Code still assumes the main model's context.
`bin/check-config` fails if the side model's context is larger than a size's.

Plain `claude` stays on the personal setup. The profile only exists for that
launch.

### Model picker

`go/cmd/model-picker/` is the terminal menu `claude-ollama` opens to choose a
size. Each `settings.<size>.json` in `ollama/` with a matching
`Modelfile.<size>` is one entry, showing the size, its `-cc` model and its base
model. When `ollama/side.Modelfile` exists, a last row "Set up side model" runs
`ollama pull` and `ollama create` for it and stays in the menu.

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
`OLLAMA_MAX_LOADED_MODELS=3` (the shipped value) keeps the main, side and
embedding models loaded: the launcher exports `CODE_SEARCH_EMBED=1` so
`semantic_search` loads and uses `qwen3-embedding:0.6b` (about 2.2 GB), and
warms it before starting the indexer. At 2 the main and side models fill both
slots, the embedding model is evicted and searches rank by words only. The
Homebrew service (`brew services start ollama`) uses these paths; add any
`server.env` value it lacks with `claude-custom agent`:

| What        | Homebrew value                                      |
| ----------- | --------------------------------------------------- |
| Binary      | `/opt/homebrew/opt/ollama/bin/ollama`               |
| Command     | `ollama serve`                                      |
| Working dir | `/opt/homebrew/var`                                 |
| Log         | `/opt/homebrew/var/log/ollama.log`                  |
| Service     | `~/Library/LaunchAgents/homebrew.mxcl.ollama.plist` |

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
launcher exits with an error. It reports each model (main, side, embedding),
whether `num_ctx` in the Modelfile matches `CLAUDE_CODE_MAX_CONTEXT_TOKENS`,
whether each hook named in `ollama/settings.<size>.json` exists and is
executable under `shared/hooks/`, whether Ollama answers at `OLLAMA_HOST`, and
whether the running server has every variable from `ollama/server.env`. A
missing side model is a warning; anything else missing exits 1. The server-env
check is how to confirm `server.env` is applied. The server's environment is
read with `pgrep`/`ps` (or `/proc` on Linux).

`claude-ollama --print-config [size]` prints the resolved values (model, base
model, side model, embedding model, context sizes, settings path, tools) and the
exact `claude` command, without launching.

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
ok   side model qwen3-4b-cc
ok   embedding model qwen3-embedding:0.6b
ok   num_ctx 65536 matches CLAUDE_CODE_MAX_CONTEXT_TOKENS
ok   hook bash-output-guard.py present
ok   ollama reachable at http://localhost:11434
ok   server env OLLAMA_FLASH_ATTENTION=1
```

To compare Ollama with other servers, see [backend-bench](backend-bench.md).

### Reviewing a pull request locally

`claude-ollama review [size] PR [--post] [--json]` reviews a GitHub pull request
with the size's model, without Claude Code. `bin/pr-review-local` fetches the PR
with `gh` and `git` (no checkout in the user's tree), skips binaries, lockfiles
and vendored paths, runs Fallow on changed TypeScript
(`audit --base <merge-base>`, introduced findings only) in a temporary worktree
of the PR head that it removes afterwards, and sends one `/v1/messages` request
per changed file: the PR description, the file's diff with 20 lines of context,
the whole file when it is under 400 lines, comments reviewers already left, and
a checklist. The model answers with a JSON array of findings; a reply that is
not JSON is retried once and then the file is listed as skipped. The verdict is
a fixed rule (any blocking finding → REQUEST CHANGES; any other finding →
APPROVE WITH COMMENTS; else APPROVE); the model only writes the one-sentence
summary. The report has the same sections as the `pr-review` agent (see
[install](install.md)): Blocking, Non-blocking, Nits, Praise, Fallow and Not
checked, which always says that files were reviewed one at a time. Nothing is
posted unless `--post` is given, and then only as a comment review. Expect a 27b
to take tens of seconds per file. While it runs, stderr names each stage
(fetch, files to review, each file before its request, retries, Fallow, summary,
CI, post), echoes the model's reply as it streams, and prints
`waiting for the first token, Ns` every 10 seconds (`--heartbeat-seconds`) until
the first token arrives. stdout holds only the report. A failed request names
the server's error message (for example a model that does not fit in memory),
and a failed summary is reported on stderr as well as in the report.

`--range BASE..HEAD` reviews local commits instead of a PR, with the same
reviewer and report. It runs no `gh`, so there are no PR comments and no CI
(the report says `CI not checked (local range)`), and `--post` is refused.
`bin/pr-review-eval --model qwen3.8-9b-distill-cc` runs the fixture in
`eval/pr-review/` through `--range` and prints one line per planted bug
(`caught blocking`, `caught` or `missed`), then a score line: bugs caught and
caught as blocking, false blockers (blocking findings on no planted bug),
findings on the two clean files, unparsable replies and seconds. Run it twice
before trusting a one-point change.
