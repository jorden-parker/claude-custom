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

## Console page

The console (`claude-ollama ui`) serves the same editor at `/tools`, for the
user settings file only. It lists every tool in the catalog with a permission
selector (default, allow, ask, deny) and a "Keep out of context" switch on allow
and ask. Changed rows are highlighted, and a bar shows the count with Save and
Discard. Save runs `claude-tools -set ... user` as a console run and reloads the
table when it ends. The page says that changes apply to new Claude Code
sessions.

The console reads the catalog cache written by the TUI and never fetches the
docs. With no cache it shows the error and how to fix it: open `claude-tools`
once and sync. For a browser check that must not touch the real file, set
`CONSOLE_TOOLS_SETTINGS=/path/to/settings.json` before starting the console; the
page then reads and writes that file instead of the user file.

Scoped rules (anything with parentheses) are never changed, on the page or in
the TUI. Project and local files are not offered on the page.

`claude-tools` is built by `claude-custom install` and rebuilt on launch only
when a Go source file is newer than the binary, so it is current after
`git pull`. Requires Go 1.26 or later. Keys, sync and write rules:
[`go/cmd/claude-tools/README.md`](../go/cmd/claude-tools/README.md).

## One entry point

`claude-custom` also runs both launchers: `claude-custom ollama [...]` is
`claude-ollama [...]`, and `claude-custom tools [...]` is `claude-tools [...]`.
