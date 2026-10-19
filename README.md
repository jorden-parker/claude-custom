# Claude Code token overlays

Additive overlays. Nothing here replaces a base file; each layer is merged by
Claude Code or applied per launch.

## Layer order (higher number wins for scalars; lists such as `permissions.*` and `hooks.*` concatenate; `env` merges per key)

1. `~/.claude/settings.json` (user, never edited by this repo)
2. `<repo>/.claude/settings.json` (project, untouched)
3. `<repo>/.claude/settings.local.json` (local) ← `project/settings.local.json`
4. `--settings` (CLI layer, one file only): `personal/settings.tokens.json` via
   the `claude` shell function, or `ollama/settings.<size>.json` via
   `claude-ollama`
5. Managed policy (untouched, always wins)

`--settings` is a single slot. Passing it twice keeps only the last file, so
`claude --settings other.json` drops the personal overlay for that session. The
overlay denies tools you never use by bare name, so their schemas stay out of
the context; to get one back, delete its name from the deny list or run
`claude-tools <path>` and press `x`.

## Personal install

```sh
~/src/.claude-custom/bin/claude-custom install
```

This wires every shell it finds: zsh (`~/.zshrc`), bash (`~/.bashrc`,
`~/.bash_profile`), ksh (`~/.kshrc`) and fish
(`~/.config/fish/conf.d/claude-custom.fish`). Rc edits sit between
`# >>> claude-custom >>>` markers and put `~/.local/bin` on PATH. It also links
`claude-ollama`, `claude-tools` and `claude-custom` into `~/.local/bin`, removes
hook links an older install left in `~/.claude/hooks/` (the hooks, see
[Enforced preferences](#enforced-preferences), now run straight from
`shared/hooks/`), adds an `@` import for `shared/preferences/PREFERENCES.md` to
`~/.claude/CLAUDE.md` (and removes the retired `personal/CLAUDE.tokens.md`
import), and rebuilds the Ollama models whose base model is pulled. Re-running
it is safe. `~/.claude/settings.json` is left as is: the overlay loads on top of
it via `--settings` on every interactive `claude` launch. Scripts, IDE
extensions, the desktop app and `claude-ollama` don't get it. Run
`command claude` to skip it once.

Per repo, when you don't need claude.ai connectors there:
`cp project/settings.local.json <repo>/.claude/settings.local.json`.

Revert: `claude-custom uninstall`.

## Enforced preferences

Coding preferences are checked by hooks that Claude Code runs itself, so they
apply the same way with Claude and with the local Ollama models. The personal
overlay and both Ollama profiles wire the same hooks:

| Hook                      | When                                                       | What it does                                                                                                                                                                                                                                                    |
| ------------------------- | ---------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `bash-output-guard.py`    | Before a Bash command                                      | Denies commands that would flood the context (unbounded `git log`, `cat` on a lockfile, recursive `ls`)                                                                                                                                                         |
| `bash-output-trim.py`     | After a Bash command                                       | Trims output over 150 lines to the first 30, error/fail and test-summary lines from the middle (up to 40) and the last 60, clips lines over 400 chars, and says what was hidden                                                                                 |
| `read-range-guard.py`     | Before a Read                                              | Denies reading a file over 300 lines unless the call asks for a range of 300 lines or fewer, and says to find the lines first                                                                                                                                   |
| `edit-check.py`           | After an Edit or Write                                     | Runs the edited file's project-local formatter and linter (gofmt, go vet, prettier, eslint, ruff, shellcheck, `bash -n`) and rejects newly added comments; names the tool that failed and skips tools for file content that already passed                      |
| `stop-verify.py`          | Before the model finishes                                  | Runs Fallow (`audit` and `architecture`) in JS/TS projects and the project's `.claude/verify` script, if present, otherwise `make test`, `go test ./...` or `pnpm test` when the repo declares one (`.claude/no-verify` opts out); blocks at most once per turn |
| `fallow-command-guard.sh` | Before a Bash command                                      | In JS/TS projects: denies `fallow` without `--format json`, `fallow fix --yes` before a `--dry-run` in the same session, and `git commit`/`git push` while `fallow audit` fails                                                                                 |
| `fallow-mark-preview.sh`  | After a Bash command                                       | Records that `fallow fix --dry-run` ran in this session, which unlocks `fallow fix --yes`                                                                                                                                                                       |
| `fallow-after-edit.sh`    | After an Edit or Write                                     | Adds Fallow's findings for the edited JS/TS file as context                                                                                                                                                                                                     |
| `tool-nudge.py`           | After Bash, Read, Agent, `semantic_search`; on each prompt | Ollama profiles only. Counts text searches (`grep`, `rg`, `find`, `git grep`) and Reads per turn; after the 2nd search adds a reminder to use `semantic_search`, after the 6th read/search a reminder to delegate to `Agent`. Never denies                      |

Every settings file runs them as `"$CLAUDE_CUSTOM_HOME"/shared/hooks/<name>`.
The `claude` shell function and `claude-ollama` set that variable for the
`claude` process, so no symlinks are needed. A check only runs when the project
has that tool installed. A failed check sends its output back to the model.
Rules no tool can check live in `shared/preferences/PREFERENCES.md`, which every
session loads through `~/.claude/CLAUDE.md`.

To have your tests run before the model finishes, add an executable
`.claude/verify` script to a project. This repo's own one runs every test suite.
Without one, the hook runs `make test` (if the Makefile has a `test` target),
else `go test ./...` (if `go.mod` exists), else `pnpm test` (if `package.json`
has a `test` script). An empty `.claude/no-verify` file turns the fallback off.

## Work harness (Ollama)

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
opens a picker ([model-picker-tui](model-picker-tui/README.md)) and drops the
unknown word. Without a terminal (scripts, pipes) it uses 27b instead. The
picker needs Go 1.26+; passing a size never does.

Sizes come from the files in `ollama/`: a size is configured when both
`settings.<size>.json` and `Modelfile.<size>` exist. The picker and `--help`
pick up a new size without any script change.

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

Plain `claude` stays on the personal setup. The profile only exists for that
launch.

### Model picker

`model-picker-tui/` is the terminal menu `claude-ollama` opens to choose a size.
Each `settings.<size>.json` in `ollama/` with a matching `Modelfile.<size>` is
one entry, showing the size, its `-cc` model and its base model. When
`ollama/side.Modelfile` exists, a last row "Set up side model" runs
`ollama pull` and `ollama create` for it and stays in the menu.

```sh
claude-custom ollama                       # opens the picker, then launches the chosen size
cd model-picker-tui && go run . ../ollama  # the picker on its own; prints the chosen size
```

Keys: `↑/k`, `↓/j`, `enter` to launch, `esc`/`q`/`ctrl+c` to cancel. Cancelling
launches nothing. `claude-ollama` rebuilds the picker on each launch (instant
when nothing changed). Details: `model-picker-tui/README.md`.

### Ollama server settings

The profiles expect an Ollama server on `localhost:11434` with the settings in
`ollama/server.env`. Nothing in this repo applies them. The launcher also sends
a warm-up request with `keep_alive` 30m (`CLAUDE_OLLAMA_KEEP_ALIVE` overrides)
so the first prompt doesn't wait for the model to load. The Homebrew service
(`brew services start ollama`) sets the same values, and uses these paths:

| What        | Homebrew value                                      |
| ----------- | --------------------------------------------------- |
| Binary      | `/opt/homebrew/opt/ollama/bin/ollama`               |
| Command     | `ollama serve`                                      |
| Working dir | `/opt/homebrew/var`                                 |
| Log         | `/opt/homebrew/var/log/ollama.log`                  |
| Service     | `~/Library/LaunchAgents/homebrew.mxcl.ollama.plist` |

Without Homebrew, start the server with the same settings:
`env $(cat ollama/server.env) ollama serve`.

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

## Tools TUI

`tools-tui/` is a terminal UI for Claude Code's built-in tools. It sets each
tool to allow, ask or deny, and disables the ones you don't need so they stop
taking up context. Press `f` inside it to switch between the user, project and
local settings files.

```sh
claude-tools              # edits ~/.claude/settings.json
claude-tools project      # ./.claude/settings.json in the current directory
claude-tools local        # ./.claude/settings.local.json
claude-tools path/to.json # any settings file
```

`claude-tools` rebuilds the TUI from the repo on each launch (instant when
nothing changed), so it is current after `git pull`. Requires Go 1.26 or later.
Keys, sync and write rules: `tools-tui/README.md`.

## One entry point

`claude-custom` also runs both launchers: `claude-custom ollama [...]` is
`claude-ollama [...]`, and `claude-custom tools [...]` is `claude-tools [...]`.

## Prompt-cache probe

`bin/ollama-cache-probe` measures how much prefill the local Ollama server skips
through its prompt cache. It sends seven fixed scenarios (cold, same prefix,
growing chat, early and late edits, eviction, side model) and prints one row
each. It changes no settings.

```sh
bin/ollama-cache-probe 27b                   # or 35b, or any model name
bin/ollama-cache-probe 27b --prefix-tokens 8000 --json
```

Hit % comes from uncached token counts. If the server reports full counts
instead, the probe warns and scores by prefill time per token. The late edit
sits at 80% of the prefix, about 16k tokens at the default 20000.

While it runs, it prints each step on stderr
(`[n/7] <scenario>: <what it is doing>`) and how long it took; the cold step
unloads and reloads the model, so it is the slowest. If the model is already
loaded, it notes that requests queue behind any other session using it. After
the table it prints one plain verdict line each for the cache, growing chat,
eviction and side model. A failed eviction suggests `OLLAMA_NUM_PARALLEL=2`; a
cache that isn't reused suggests a GGUF build.

## Semantic code search

`claude-ollama` starts `shared/mcp/code-search.py`, a stdlib-only MCP server
with one tool, `semantic_search`. It embeds the repo with `qwen3-embedding:0.6b`
(pulled on launch if missing) and returns `file:start-end` ranges with a score
and a one-line preview, so the model reads only those lines. `claude-ollama`
drops Grep and Glob (`--tools Bash,Read,Edit,Write,Agent`, plus bare deny
rules), and the working rules tell the model to always search first; exact names
go through `git grep -n`.

- Files: `git ls-files` plus untracked, non-ignored files. Lockfiles, minified
  files, images, binaries and files over 200 KB are skipped.
- Chunks: 40-line windows every 30 lines, vectors cut to 256 dimensions.
- Index: `.git/code-search/index.json`. Each search re-embeds only files whose
  content changed, so the first search in a repo is slow (about a minute for
  this one) and later ones take well under a second.
- `CODE_SEARCH_OLLAMA_URL` and `CODE_SEARCH_MODEL` override the server and
  model. `claude-ollama` and the model picker follow `CODE_SEARCH_MODEL` too.
- If the pull on launch fails, run `claude-ollama` and pick "Set up embedding
  model" in the menu.
- `ollama/CLAUDE.<size>.md` tells the model when to search (questions about what
  code does), when to use `git grep -n` (exact names), and to fall back to
  `git grep` and point you at that menu row when the search errors.

## Tests

- Everything: `make test` (or `.claude/verify`, which the Stop hook runs)
- One suite: `make test-hooks`, `make test-install`, `make test-launcher`,
  `make check-config`, `make test-probe`, `make test-search`, `make test-go`
- Installer: `personal/install.test.sh`; launcher: `bin/claude-ollama.test.sh`;
  config invariants: `bin/check-config`
- Lint: `make shellcheck`, `make check-json`

## Another machine / updating

Clone anywhere and install once:

```sh
git clone <remote> ~/src/.claude-custom
~/src/.claude-custom/bin/claude-custom install
```

After that, `claude-custom update` pulls (fast-forward only) and re-runs
install. Most changes are live after a plain `git pull`, because every link and
rc block points into the repo. `update` also picks up new links and rebuilds
changed Ollama models.
