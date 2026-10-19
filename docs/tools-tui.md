# Tools TUI

`go/cmd/claude-tools/` is a terminal UI for Claude Code's built-in tools. It
sets each tool to allow, ask or deny, and disables the ones you don't need so
they stop taking up context. Press `f` inside it to switch between the user,
project and local settings files.

```sh
claude-tools              # edits ~/.claude/settings.json
claude-tools project      # ./.claude/settings.json in the current directory
claude-tools local        # ./.claude/settings.local.json
claude-tools path/to.json # any settings file
```

`claude-tools` is built by `claude-custom install` and rebuilt on launch only
when a Go source file is newer than the binary, so it is current after
`git pull`. Requires Go 1.26 or later. Keys, sync and write rules:
[`go/cmd/claude-tools/README.md`](../go/cmd/claude-tools/README.md).

## One entry point

`claude-custom` also runs both launchers: `claude-custom ollama [...]` is
`claude-ollama [...]`, and `claude-custom tools [...]` is `claude-tools [...]`.
