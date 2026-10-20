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
cd go && go run ./cmd/ollama-agent -server-env ../ollama/server.env
```

`claude-custom install` builds the binary, and `bin/ollama-agent` rebuilds it
only when a Go source file is newer than the binary. The launcher passes
`-server-env ollama/server.env`.

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
`server.env`, and `internal/agent/ui` is the Bubble Tea model. Tests never call
launchctl.
