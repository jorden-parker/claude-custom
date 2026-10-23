# Enforced preferences

Coding preferences are checked by hooks that Claude Code runs itself, so they
apply the same way with Claude and with the local Ollama models. The personal
overlay and both Ollama profiles wire the same core hooks (from
`shared/settings/hooks.json`); the Ollama profiles add `tool-nudge.py`:

| Hook                      | When                                              | What it does                                                                                                                                                                                                                                                                                                                                                                                                                    |
| ------------------------- | ------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `bash-output-guard.py`    | Before a Bash command                             | Denies commands that would flood the context (unbounded `git log`, `cat` on a lockfile, recursive `ls`) unless piped to `head`, `tail`, `wc`, `grep` or `sed -n`; separators inside quotes don't split the command                                                                                                                                                                                                              |
| `bash-output-trim.py`     | After a Bash command                              | Trims output over 150 lines to the first 30, error/fail and test-summary lines from the middle (up to 40) and the last 60, clips lines over 400 chars, and says what was hidden                                                                                                                                                                                                                                                 |
| `read-range-guard.py`     | Before a Read                                     | Denies reading a file over 300 lines unless the call asks for a range of 300 lines or fewer, and says to find the lines first                                                                                                                                                                                                                                                                                                   |
| `edit-check.py`           | After an Edit or Write                            | Runs the project's prettier and eslint from `node_modules/.bin`, and gofmt, go vet, ruff, shellcheck and `bash -n` from PATH when installed; rejects newly added comments, including trailing ones such as `# noqa` or `// eslint-disable-line`; names the tool that failed and skips tools for file content that already passed                                                                                                |
| `stop-verify.py`          | Before the model finishes                         | Only when the agent edited files in the project this session (it records them after each Edit/Write/MultiEdit): runs `fallow audit` on each edited JS/TS file and the project's `.claude/verify` script with the edited files as arguments, if present, otherwise `make test`, `go test ./...` or `pnpm test` when the repo declares one (`.claude/no-verify` opts out); a pass clears the record; blocks at most once per turn |
| `fallow-command-guard.sh` | Before a Bash command                             | Denies `fallow` without `--format json` and `fallow fix --yes` before a `--dry-run` in the same session (any repo); in JS/TS projects also denies `git commit`/`git push` while `fallow audit` fails                                                                                                                                                                                                                            |
| `fallow-mark-preview.sh`  | After a Bash command                              | Records that `fallow fix --dry-run` ran in this session, which unlocks `fallow fix --yes`                                                                                                                                                                                                                                                                                                                                       |
| `fallow-after-edit.sh`    | After an Edit or Write                            | Adds Fallow's findings for the edited JS/TS file as context                                                                                                                                                                                                                                                                                                                                                                     |
| `tool-nudge.py`           | Before Bash and `semantic_search`; on each prompt | Ollama profiles only. Denies every Bash command that runs a text search (`grep`, `rg`, `ag`, `ack`, `git grep`, `find` by name or path; a search after a pipe is a filter and passes) until `mcp__code-search__semantic_search` has been called in the turn, even if that call errored                                                                                                                                          |
| `tool-telemetry.py`       | After any tool                                    | Only when `CLAUDE_TOOL_TELEMETRY=<file>` is set: appends one JSON line per call with the time, session, tool name, response bytes, line count and whether trimming would apply. It never logs tool input or output; otherwise it does nothing                                                                                                                                                                                   |

Every settings file runs them as `"$CLAUDE_CUSTOM_HOME"/shared/hooks/<name>`.
The `claude` shell function and `claude-ollama` set that variable for the
`claude` process, so no symlinks are needed. A check only runs when the project
has that tool installed. A failed check sends its output back to the model.
Rules no tool can check live in `shared/preferences/PREFERENCES.md`, which every
session loads through `~/.claude/CLAUDE.md`.

To measure what tool calls return, start a session with the log set, then
summarise it: `env CLAUDE_TOOL_TELEMETRY="$HOME/tool.log" claude-ollama 27b`,
then `bin/tool-telemetry-report "$HOME/tool.log"`. The report lists calls,
bytes, median, max and over-limit counts per tool, then the five largest calls.

To have your tests run before the model finishes, add an executable
`.claude/verify` script to a project. This repo's own one runs every test suite.
Without one, the hook runs `make test` (if the Makefile has a `test` target),
else `go test ./...` (if `go.mod` exists), else `pnpm test` (if `package.json`
has a `test` script). An empty `.claude/no-verify` file turns the fallback off.

## Tests

- Everything: `make test` (or `.claude/verify` with no arguments; the Stop hook
  passes it the edited files so it runs only their tests)
- One suite: `make test-hooks`, `make test-install`, `make test-launcher`,
  `make check-config`, `make check-profiles`, `make test-profiles`,
  `make test-probe`, `make test-search`, `make test-go`
- Installer: `personal/install.test.sh`; launcher: `bin/claude-ollama.test.sh`;
  config invariants: `bin/check-config`
- Lint: `make shellcheck`, `make check-json`
