# ollama-agent

A terminal editor for the `local.llama-server` launchd agent, which runs
Homebrew's `llama-server` in router mode for every `claude-ollama` size. The
name stays `ollama-agent`, though the server is llama.cpp now. Built with
[Bubble Tea](https://charm.land/libs/), Bubbles and Lip Gloss.

The agent runs:

```sh
llama-server --models-preset ~/.claude-ollama/presets/models.ini --models-max N \
  --host 127.0.0.1 --port 11435 --log-file ~/.claude-ollama/logs/llama-server.log --metrics
```

with `RunAtLoad`, `KeepAlive`, and launchd's own output in
`~/.claude-ollama/logs/llama-server.stdout.log`.

## Settings

The editable settings are the `[*]` keys of `ollama/server.ini` (the flags every
preset shares, named like the long flags without the dashes) plus `models-max`
from its `[router]` section. Your changes go to
`~/.claude-ollama/presets/server.local.ini`, which holds only the keys that
differ from `server.ini` (`[*]` keys, then `[router]` with `models-max`).
`bin/ollama-profiles --user-presets` lays its `[*]` keys over the shared section
of the user preset file; `models-max` goes on the agent's command line.

## Run

```sh
claude-custom agent            # or: ollama-agent
ollama-agent -file PATH        # edit another plist (default $LLAMA_SERVER_PLIST, else ~/Library/LaunchAgents/local.llama-server.plist)
ollama-agent -llama-server P   # binary the agent runs (default $LLAMA_SERVER_BIN, else llama-server on PATH)
ollama-agent -apply            # write the agent from the settings and reload it, no menu
ollama-agent -set KEY=VALUE    # change one setting, render the presets and reload, no menu (repeatable)
ollama-agent -json             # print the settings as JSON and exit
cd go && go run ./cmd/ollama-agent -server-ini ../ollama/server.ini -render ../bin/ollama-profiles
```

`bin/ollama-agent` passes `-server-ini ollama/server.ini` and
`-render bin/ollama-profiles`; `-overrides` and `-presets` default to the two
files under `~/.claude-ollama/presets/`. `claude-custom install` builds the
binary, and `bin/ollama-agent` rebuilds it only when a Go source file is newer
than the binary.

`-apply` writes `server.local.ini` (only when it changed), runs
`bin/ollama-profiles --user-presets --out <presets>`, writes the plist when it
differs, runs `brew services stop llama.cpp` when that Homebrew service is
loaded, and reloads the agent. It reloads even when the plist is unchanged, so a
changed preset file is read again. `claude-ollama` calls it before a launch when
`--user-presets` printed `changed`, and `claude-custom install` calls it too.
Without a `llama-server` it exits 1 naming `brew install llama.cpp`.

`-set KEY=VALUE` changes just the named settings, then does what `-apply` does.
The key must be a built-in setting; the value can't be empty or contain a
newline, NUL or bracket, and is at most 256 bytes; anything else exits 1 with
`unknown setting` or the reason. A value equal to `server.ini`'s drops the
override. `-set` can be repeated, and it can't be combined with `-apply`
(exit 2) or `-json`.

`-json` prints a snapshot to stdout and exits without writing anything. Its keys
are stable, since the console's Server page reads them:

| key                       | meaning                                                        |
| ------------------------- | -------------------------------------------------------------- |
| `path`                    | the plist path                                                 |
| `exists`                  | whether the plist exists                                       |
| `overrides`               | the `server.local.ini` path                                    |
| `variables[].name`        | the preset key (`cache-type-k`) or `models-max`                |
| `variables[].summary`     | one line about it                                              |
| `variables[].current`     | the effective value: yours, else `server.ini`'s (`""` if none) |
| `variables[].set`         | whether `server.local.ini` overrides it                        |
| `variables[].recommended` | the `server.ini` value                                         |
| `conflicts`               | the warnings at the top of the menu (`[]` when none)           |

## What it shows

Every built-in setting, then any other key found in `server.ini` or your
overrides, sorted. Each row shows the effective value (or `unset`) and a
one-line summary. When a value differs from `server.ini`, the row says what
`server.ini` has. `*` marks unsaved rows. With no plist yet the agent counts as
unsaved. A `server.local.ini` that can't be parsed is an error and nothing
opens.

Each save records the old and new `server.local.ini` and plist in the change
history before it replaces them, so the console's History page can show the diff
and restore it.

A warning at the top names the Homebrew `llama.cpp` service
(`homebrew.mxcl.llama.cpp`) when it is loaded; `-apply` stops it.

## Keys

| Key          | Action                                           |
| ------------ | ------------------------------------------------ |
| `↑/k` `↓/j`  | move                                             |
| `enter`/`e`  | edit the value (`enter` keeps it, `esc` cancels) |
| `r`          | set to the `server.ini` value (unset if none)    |
| `w`/`ctrl+s` | save the settings, presets and plist             |
| `a`          | save, then reload the agent                      |
| `q`/`esc`    | quit (asks once when there are unsaved changes)  |

Reload runs `launchctl bootout gui/<uid>/local.llama-server`, waits for it to
go, then `launchctl bootstrap gui/<uid> <plist>`. A failed reload shows
launchctl's output.

## Test

```sh
cd go && go test ./internal/agent/...
```

`internal/agent/launchd` renders and reads the plist and builds the launchctl
command, `internal/agent/variables` holds the settings list, parses the INI
files and `-set` assignments and writes `server.local.ini`,
`internal/agent/apply` is the `-apply` and `-set` flow,
`internal/agent/snapshot` builds the `-json` report, and `internal/agent/ui` is
the Bubble Tea model. Tests never call launchctl.
