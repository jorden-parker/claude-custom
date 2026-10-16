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
`claude-ollama`, `claude-tools`, `claude-custom` and the Bash output hook, adds
the `@` import to `~/.claude/CLAUDE.md`, and rebuilds the Ollama models whose
base model is pulled. Re-running it is safe. `~/.claude/settings.json` is left
as is: the overlay loads on top of it via `--settings` on every interactive
`claude` launch. Scripts, IDE extensions, the desktop app and `claude-ollama`
don't get it. Run `command claude` to skip it once.

Per repo, when you don't need claude.ai connectors there:
`cp project/settings.local.json <repo>/.claude/settings.local.json`.

Revert: `claude-custom uninstall`.

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

- Hook: `shared/hooks/bash-output-guard.test.sh`
- Installer: `personal/install.test.sh`
- Tools TUI: `cd tools-tui && go test ./...`

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
