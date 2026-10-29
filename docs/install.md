# Install and updating

## Prerequisites

| Tool                                        | Needed by                                                                                                                            | Without it                                                              |
| ------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------- |
| `bash`                                      | `bin/claude-custom`, `bin/claude-ollama`, `bin/claude-tools` and every hook (macOS `/bin/bash` 3.2 is enough)                        | nothing starts                                                          |
| `python3`                                   | every `.py` hook, `shared/mcp/code-search.py`, the Python tests                                                                      | hooks fail to start; no semantic search                                 |
| `jq`                                        | `bin/claude-custom`, `bin/claude-ollama` (`doctor` needs it), `personal/settings-path`, the `fallow-*.sh` hooks                      | the fallow hooks exit silently and allow everything; `doctor` won't run |
| `go` 1.26+                                  | `go/`: the model picker (`claude-ollama` with no size) and `claude-tools`                                                            | `claude-ollama <size>` still works; the menu and `claude-tools` don't   |
| `ollama`                                    | the work harness: `claude-ollama`, `bin/ollama-cache-probe`                                                                          | the work harness can't run a model                                      |
| `qwen`                                      | the Qwen Code harness: `claude-ollama qwen` (`brew install qwen-code`)                                                               | `claude-ollama qwen` exits 1 and says so; nothing else changes          |
| `node` (`npx`) and `pnpm`                   | Prettier in `bin/ollama-profiles`; `pnpm install` enables the husky and lint-staged git hooks; `npm ci` installs the session sandbox | `bin/ollama-profiles` fails; no git hooks; `claude-ollama` won't start  |
| `make` and `shellcheck`                     | `make test`, which CI and the Stop hook run                                                                                          | `make test` fails                                                       |
| optional: `ruff`, `gofmt` (ships with `go`) | `edit-check.py`                                                                                                                      | that check is skipped                                                   |
| optional: `fallow`                          | the fallow hooks and `stop-verify.py`                                                                                                | fetched with `npx --yes fallow` on first use                            |
| optional: `gitleaks`                        | the pre-commit secret check                                                                                                          | a grep-based secret check                                               |

On macOS: `brew install jq ollama go shellcheck node pnpm`. `make` and
`/bin/bash` come with macOS and the Xcode command line tools.

## Personal install

```sh
~/src/.claude-custom/bin/claude-custom install
```

This wires every shell it finds: zsh (`~/.zshrc`), bash (`~/.bashrc`,
`~/.bash_profile`), ksh (`~/.kshrc`) and fish
(`~/.config/fish/conf.d/claude-custom.fish`). Rc edits sit between
`# >>> claude-custom >>>` markers and put `~/.local/bin` on PATH. It also links
`claude-ollama`, `claude-tools`, `ollama-agent` and `claude-custom` into
`~/.local/bin`, links the `pr-review` agent (`shared/agents/pr-review.md`) into
`~/.claude/agents/`, removes hook links an older install left in
`~/.claude/hooks/` (the hooks, see [Enforced preferences](hooks.md), now run
straight from `shared/hooks/`), adds an `@` import for
`shared/preferences/PREFERENCES.md` to `~/.claude/CLAUDE.md` (and removes the
retired `personal/CLAUDE.tokens.md` import), rebuilds the Ollama models whose
base model is pulled, and installs the pinned `sandbox-runtime` that
`claude-ollama` sessions run in, plus a pinned Shortcut CLI (`short`, which the
session's Shortcut broker runs in place of yours on `PATH`), under
`~/.local/share/claude-custom/`. Re-running it is safe.
`~/.claude/settings.json` is left as is: the overlay loads on top of it via
`--settings` on every interactive `claude` launch. Scripts, IDE extensions, the
desktop app and `claude-ollama` don't get it. Run `command claude` to skip it
once.

Per repo, when you don't need claude.ai connectors there:
`cp project/settings.local.json <repo>/.claude/settings.local.json`.

Revert: `claude-custom uninstall`.

Review a pull request with the main model:
`claude --agent pr-review "Review PR 123"`. Inside a session,
`@agent-pr-review review PR 123` runs it as a subagent, which the overlay sends
to Haiku (`CLAUDE_CODE_SUBAGENT_MODEL_FORCE`), so expect a lighter review that
way. The agent never posts to GitHub unless the request says to, and then only
as a comment review. A `~/.claude/agents/` directory that did not exist when a
session started needs a restart to be seen.

## Another machine / updating

Clone anywhere and install once:

```sh
git clone <remote> ~/src/.claude-custom
~/src/.claude-custom/bin/claude-custom install
```

After that, `claude-custom update` pulls (fast-forward only) and re-runs
install. Most changes are live after a plain `git pull`, because every link and
rc block points into the repo. `update` also picks up new links and rebuilds
changed Ollama models. In a cmux terminal it ends with
`claude-ollama browser-check` and exits 1 when the session browser is not locked
to localhost; elsewhere it prints a reminder to run it from cmux.
