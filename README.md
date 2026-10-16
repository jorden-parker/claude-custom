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
`claude --settings other.json` drops the personal overlay for that session.

## Personal install

```sh
~/src/.claude-custom/bin/claude-custom install
```

This wires every shell it finds: zsh (`~/.zshrc`), bash (`~/.bashrc`,
`~/.bash_profile`), ksh (`~/.kshrc`) and fish
(`~/.config/fish/conf.d/claude-custom.fish`). Rc edits sit between
`# >>> claude-custom >>>` markers and put `~/.local/bin` on PATH. It also links
`claude-ollama`, `claude-tools`, `claude-custom` and the four hooks (see
[Enforced preferences](#enforced-preferences)) into `~/.claude/hooks/`, adds `@`
imports for `personal/CLAUDE.tokens.md` and `shared/preferences/PREFERENCES.md`
to `~/.claude/CLAUDE.md`, and rebuilds the Ollama models whose base model is
pulled. Re-running it is safe. `~/.claude/settings.json` is left as is: the
overlay loads on top of it via `--settings` on every interactive `claude`
launch. Scripts, IDE extensions, the desktop app and `claude-ollama` don't get
it. Run `command claude` to skip it once.

Per repo, when you don't need claude.ai connectors there:
`cp project/settings.local.json <repo>/.claude/settings.local.json`.

Revert: `claude-custom uninstall`.

## Enforced preferences

Coding preferences are checked by hooks that Claude Code runs itself, so they
apply the same way with Claude and with the local Ollama models. The personal
overlay and both Ollama profiles wire the same hooks:

| Hook                   | When                      | What it does                                                                                                                                                   |
| ---------------------- | ------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `bash-output-guard.py` | Before a Bash command     | Denies commands that would flood the context (unbounded `git log`, `cat` on a lockfile, recursive `ls`)                                                        |
| `bash-output-trim.py`  | After a Bash command      | Trims output over 150 lines to the first 30, error/fail lines from the middle (up to 40) and the last 60, clips lines over 400 chars, and says what was hidden |
| `edit-check.py`        | After an Edit or Write    | Runs the edited file's project-local formatter and linter (gofmt, go vet, prettier, eslint, ruff, shellcheck, `bash -n`) and rejects newly added comments      |
| `stop-verify.py`       | Before the model finishes | Runs Fallow (`audit` and `architecture`) in JS/TS projects and the project's `.claude/verify` script, if present; blocks at most once per turn                 |

A check only runs when the project has that tool installed. A failed check sends
its output back to the model. Rules no tool can check live in
`shared/preferences/PREFERENCES.md`, which every session loads through
`~/.claude/CLAUDE.md`.

To have your tests run before the model finishes, add an executable
`.claude/verify` script to a project. This repo's own one runs every test suite.

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

Plain `claude` stays on the personal setup. The profile only exists for that
launch.

### Model picker

`model-picker-tui/` is the terminal menu `claude-ollama` opens to choose a size.
Each `settings.<size>.json` in `ollama/` with a matching `Modelfile.<size>` is
one entry, showing the size, its `-cc` model and its base model.

```sh
claude-custom ollama                       # opens the picker, then launches the chosen size
cd model-picker-tui && go run . ../ollama  # the picker on its own; prints the chosen size
```

Keys: `↑/k`, `↓/j`, `enter` to launch, `esc`/`q`/`ctrl+c` to cancel. Cancelling
launches nothing. `claude-ollama` rebuilds the picker on each launch (instant
when nothing changed). Details: `model-picker-tui/README.md`.

### Ollama server settings

The profiles expect an Ollama server on `localhost:11434` with the settings in
`ollama/server.env`. Nothing in this repo applies them. The Homebrew service
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

## Tests

- Everything: `.claude/verify`
- Hooks: `shared/hooks/*.test.sh`
- Installer: `personal/install.test.sh`
- Tools TUI: `cd tools-tui && go test ./...`
- Model picker: `cd model-picker-tui && go test ./...`

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
