# ollama-agent

A terminal editor for the launchd agent that runs `ollama serve` with your
`OLLAMA_*` variables. launchd never reads shell rc files such as `~/.zshenv`, so
a server started by `brew services` or the Ollama app ignores variables exported
there. This agent sets them in the plist instead. Built with
[Bubble Tea](https://charm.land/libs/), Bubbles and Lip Gloss.

## Run

```sh
claude-custom agent           # or: ollama-agent
ollama-agent -file PATH       # edit another plist (default ~/Library/LaunchAgents/local.ollama.plist)
ollama-agent -ollama PATH     # binary the agent runs (default: ollama on PATH)
ollama-agent -apply          # write server.env into the agent and reload it, no menu
ollama-agent -set NAME=VALUE # write one variable into the agent and reload it, no menu (repeatable)
ollama-agent -json           # print the agent's variables as JSON and exit
cd go && go run ./cmd/ollama-agent -server-env ../ollama/server.env
```

`claude-custom install` builds the binary, and `bin/ollama-agent` rebuilds it
only when a Go source file is newer than the binary. The launcher passes
`-server-env ollama/server.env`.

`-apply` sets every `server.env` value in the plist (other variables stay), runs
`brew services stop ollama` when the Homebrew service is loaded, and reloads the
agent. It refuses while the Ollama app runs. `claude-ollama` calls it before a
launch when the running server lacks a `server.env` value.

`-set NAME=VALUE` does the same write and reload for just the named variables
and nothing else in `server.env`. The name must be a built-in variable, and the
value can't contain a newline or NUL and is at most 256 bytes; anything else
exits 1 with `unknown variable` or the reason. `-set` can be repeated, and it
can't be combined with `-apply` (exit 2) or `-json`.

`-json` prints a snapshot to stdout and exits without writing anything. It has
the plist path, whether the plist exists, every variable (name, summary, current
value, whether it is set in the plist, and the `server.env` value) and the
conflicts shown at the top of the menu (an empty list when there are none). Use
it to read the state from a script or another tool.

## What it shows

Every variable in the built-in list of `OLLAMA_*` server settings, then any
other variable found in the plist or `server.env`, sorted. Each row shows the
value (or `unset`) and a one-line summary. When a value differs from
`server.env`, the row says what `server.env` has. `*` marks unsaved rows.

With no plist yet, values start from `server.env` and the agent counts as
unsaved. A plist that isn't valid XML is an error and nothing opens.

Warnings at the top name anything else serving on the same port: the Homebrew
service (`homebrew.mxcl.ollama` loaded) or the Ollama menu-bar app. Stop them
first, or the agent's server can't bind `11434`.

## Keys

| Key          | Action                                           |
| ------------ | ------------------------------------------------ |
| `↑/k` `↓/j`  | move                                             |
| `enter`/`e`  | edit the value (`enter` keeps it, `esc` cancels) |
| `x`          | unset                                            |
| `r`          | set to the `server.env` value (unset if none)    |
| `w`/`ctrl+s` | save the plist                                   |
| `a`          | save, then reload the agent                      |
| `q`/`esc`    | quit (asks once when there are unsaved changes)  |

Saving rewrites the whole plist atomically with mode 0644: label `local.ollama`,
`ollama serve`, the variables sorted, `RunAtLoad`, `KeepAlive` and the log at
`~/Library/Logs/ollama.log`. Reload runs
`launchctl bootout gui/<uid>/local.ollama`, waits for it to go, then
`launchctl bootstrap gui/<uid> <plist>`; `kickstart -k` would keep the old
environment. A failed reload shows launchctl's output.

## Test

```sh
cd go && go test ./internal/agent/...
```

`internal/agent/launchd` renders and reads the plist and builds the launchctl
command, `internal/agent/variables` holds the variable list and parses
`server.env` and `-set` assignments, `internal/agent/snapshot` builds the
`-json` report, and `internal/agent/ui` is the Bubble Tea model. Tests never
call launchctl.
