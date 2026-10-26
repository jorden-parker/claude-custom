# claude-tools

A terminal UI for Claude Code's built-in tools. Set each tool to allow, ask or
deny, and switch off the ones you don't need so they stop taking up context.
Built with [Bubble Tea](https://charm.land/libs/), Bubbles and Lip Gloss.

## Run

```sh
claude-tools                  # edits ~/.claude/settings.json (same as claude-tools user)
claude-tools project          # ./.claude/settings.json in the current directory
claude-tools local            # ./.claude/settings.local.json
claude-tools path/to.json     # any settings file (same as -settings path/to.json)
claude-custom tools [...]     # same as claude-tools [...]
```

`claude-custom install` links `bin/claude-tools` into `~/.local/bin`. It is
built by `claude-custom install` and rebuilt on launch only when a Go source
file is newer than the binary. It runs in the directory you launched from. If
you built `~/.local/bin/claude-tools` by hand before, delete it and re-run
`claude-custom install`; the installer won't overwrite a file it doesn't manage.

For development: `cd go && go run ./cmd/claude-tools`. Requires Go 1.26 or
later. Tests: `cd go && go test ./...`.

Changes take effect in Claude Code from the next request; no restart needed.

## Scripted use: `-json` and `-set`

`-json` prints the file's state for every tool in the cached list as JSON, then
exits. Each row has `name`, `description`, `promptsByDefault`, `permission`
(`default|allow|ask|deny`) and `disabled`. It needs the cached list, so open the
TUI and sync once first. Without it, the command exits 1 with
`no tool catalog yet; open claude-tools once and sync`.

`-set NAME=PERM[,off]` sets one bare tool rule and saves the file, using the same
rules as the TUI. `PERM` is `default`, `allow`, `ask` or `deny`. `,off` is valid
only with allow or ask, and keeps a deny rule beside it, like the TUI's disable.
The flag repeats. Every assignment is checked before anything is written. An
unknown tool or permission exits 1 and leaves the file unchanged. A save prints
`saved <path>`.

```sh
claude-tools -settings path/to.json -set WebFetch=deny -set Read=ask,off
claude-tools -json user
```

Put the flags before the scope argument: `claude-tools -set WebFetch=deny user`.
The flag parser stops at the first positional argument, so `claude-tools user
-set ...` is a usage error (exit 2). `-json` with `-set` is also a usage error.

## Keybinds

| Key             | Action                                          |
| --------------- | ----------------------------------------------- |
| `↑`/`k` `↓`/`j` | Move                                            |
| `g` / `G`       | Top / bottom (also `home` / `end`)              |
| `a`             | Allow (never prompts)                           |
| `p`             | Ask (always prompts)                            |
| `d`             | Deny                                            |
| `r`             | Default: remove the TUI's rules for the tool    |
| `space`/`tab`   | Cycle default → allow → ask → deny              |
| `x`             | Disable / enable (take the tool out of context) |
| `w`/`ctrl+s`    | Save                                            |
| `u`             | Sync the tool list from the docs                |
| `f`             | Switch settings file                            |
| `?`             | Show every key                                  |
| `q`/`ctrl+c`    | Quit (asks again if there are unsaved changes)  |

In the file list, `↑`/`↓` move, `enter` opens the file and `esc` cancels.

`default (asks)` and `default (auto)` show what Claude Code does with no rule,
taken from the docs' "Permission required" column.

## Switching settings files

Press `f` to list the settings files and open another one without restarting.
The title line shows which one is active. The list holds Claude Code's scope
locations, plus the file you passed (`FILE` or `-settings`) if it is none of
them:

| Label   | Path                               |
| ------- | ---------------------------------- |
| custom  | the file you passed (listed first) |
| user    | `~/.claude/settings.json`          |
| project | `./.claude/settings.json`          |
| local   | `./.claude/settings.local.json`    |

- `project` and `local` are relative to the directory you launch from.
- A file that doesn't exist yet is marked `(new)`. You can open it, and the
  first save creates it.
- A file that isn't valid JSON can't be opened. The current file stays active
  and the error is shown.
- With unsaved changes, `enter` asks first. Press `enter` again to drop them, or
  `esc` then `w` to save.

## Where the tool list comes from

Source: <https://code.claude.com/docs/en/tools-reference.md>, the Markdown
version of the official
[Tools reference](https://code.claude.com/docs/en/tools-reference).

Why this source:

- It is Anthropic's own list of the exact names that permission rules accept.
- It covers every built-in tool, including ones the current machine, plan or
  model doesn't load, so the list doesn't change from one machine to the next.
- It marks retired tools in place (for example `TaskOutput`: "Removed in
  v2.1.277"), so they can be filtered out.

Alternatives considered:

- **The CLI's `init` message**
  (`claude -p --output-format stream-json --verbose`). Accurate for one session,
  but it costs an API call and lists only the tools loaded right now. It omits
  tools you've already denied, and ones absent on this platform (e.g.
  `Glob`/`Grep` on macOS).
- **The settings JSON schema** (schemastore). It does not list tool names.

## How syncing works

1. On first launch there is no cached list, so the TUI fetches the docs page.
   Press `u` to sync again at any time.
2. It parses only the table headed
   `| Tool | Description | Permission required |`.
3. It drops rows whose description starts with "Removed" or contains
   "deprecated".
4. The parsed list replaces the cached one in full, so stale tools disappear.
   The status line names what was added and dropped.
5. The list is cached at `~/Library/Caches/claude-tools/tools.json` on macOS
   (`$XDG_CACHE_HOME/claude-tools/` on Linux).

If the fetch or parse fails, the cached list stays and the error is shown. No
tool names are hardcoded.

## How settings are written

Everything goes into `permissions` in the chosen settings file:

| TUI state           | Rules written                           |
| ------------------- | --------------------------------------- |
| default             | none                                    |
| allow               | `"Tool"` in `allow`                     |
| ask                 | `"Tool"` in `ask`                       |
| deny                | `"Tool"` in `deny`                      |
| allow/ask, disabled | `"Tool"` in `deny` and in `allow`/`ask` |

### Disable vs deny

Claude Code has one way to take a built-in tool out of context from a settings
file: a deny rule with the bare tool name. The docs say it "removes the tool
from Claude's context entirely, so Claude never sees it". Scoped rules such as
`Bash(rm *)`, and all allow and ask rules, leave the tool visible. (The
`--tools` CLI flag also works, but only for one launch.)

So a whole-tool deny is a disable. There is no setting that denies a tool while
keeping it visible. The TUI keeps the two apart this way:

- **Permission** (`a`/`p`/`d`/`r`) is the rule you want.
- **Disable** (`x`) takes the tool out of context but keeps its allow or ask
  rule. Deny rules are checked first, so the kept rule has no effect until you
  re-enable. Press `x` again to re-enable with the same permission.
- Disabling a tool with no rule is just deny. `x` on a denied tool re-enables it
  with no rule.

The CONTEXT column shows `off` for any tool Claude can't see.

### What is preserved

- Every key outside `permissions.allow`, `ask` and `deny` is untouched.
- Key order is untouched. The file is re-indented with two spaces.
- Scoped rules (`Bash(git log *)`, `Read(./.env)`), MCP rules and rules for
  tools outside the current list are untouched.
- On save, the file is re-read first. Rules Claude Code added while the TUI was
  open (e.g. "don't ask again") are kept.
- Saves follow symlinks and keep the file mode. They are atomic (temp file plus
  rename). The previous version goes to `<file>.bak`.

The TUI shows and edits one settings file at a time. Rules in other scopes
(project, local, managed, `--settings`) still apply: a deny anywhere beats an
allow here.
