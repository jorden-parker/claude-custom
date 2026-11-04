# Install and updating

## Prerequisites

| Tool                                                  | Needed by                                                                                                       | Without it                                                                         |
| ----------------------------------------------------- | --------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------- |
| `bash`                                                | `bin/claude-custom`, `bin/claude-ollama`, `bin/claude-tools` and every hook (macOS `/bin/bash` 3.2 is enough)   | nothing starts                                                                     |
| `python3`                                             | every `.py` hook, `shared/mcp/code-search.py`, the Python tests                                                 | hooks fail to start; no semantic search                                            |
| `jq`                                                  | `bin/claude-custom`, `bin/claude-ollama` (`doctor` needs it), `personal/settings-path`, the `fallow-*.sh` hooks | the fallow hooks exit silently and allow everything; `doctor` won't run            |
| `go` 1.26+                                            | `go/`: the model picker (`claude-ollama` with no size) and `claude-tools`                                       | `claude-ollama <size>` still works; the menu and `claude-tools` don't              |
| `llama-server` build 9200+ (`brew install llama.cpp`) | the work harness: `claude-ollama`, `bin/ollama-cache-probe`                                                     | the work harness can't run a model; `claude-custom install` skips the server setup |
| `qwen`                                                | the Qwen Code harness: `claude-ollama qwen` (`brew install qwen-code`)                                          | `claude-ollama qwen` exits 1 and says so; nothing else changes                     |
| `node` (`npx`) and `pnpm`                             | Prettier in `bin/ollama-profiles`; `pnpm install` enables the husky and lint-staged git hooks                   | `bin/ollama-profiles` fails; no git hooks                                          |
| `make` and `shellcheck`                               | `make test`, which CI and the Stop hook run                                                                     | `make test` fails                                                                  |
| optional: `ruff`, `gofmt` (ships with `go`)           | `edit-check.py`                                                                                                 | that check is skipped                                                              |
| optional: `fallow`                                    | the fallow hooks and `stop-verify.py`                                                                           | fetched with `npx --yes fallow` on first use                                       |
| optional: `gitleaks`                                  | the pre-commit secret check                                                                                     | a grep-based secret check                                                          |

On macOS: `brew install jq llama.cpp go shellcheck node pnpm`. `make` and
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
retired `personal/CLAUDE.tokens.md` import), sets up llama-server (below), and
removes the `sandbox-runtime` and Shortcut CLI folders that older versions
installed under `~/.local/share/claude-custom/`. Re-running it is safe.
`~/.claude/settings.json` is left as is: the overlay loads on top of it via
`--settings` on every interactive `claude` launch. Scripts, IDE extensions, the
desktop app and `claude-ollama` don't get it. Run `command claude` to skip it
once.

Per repo, when you don't need claude.ai connectors there:
`cp project/settings.local.json <repo>/.claude/settings.local.json`.

Revert: `claude-custom uninstall`. It also boots out the `local.llama-server`
LaunchAgent and deletes its plist; the weights in `~/.claude-ollama/weights/`
stay until you remove them.

## llama-server

On macOS, `claude-custom install` sets up the work harness's model server:

- An old `local.ollama` LaunchAgent that is still loaded is booted out, with one
  hint to remove the old models by hand (`ollama rm NAME` for each, then
  `brew uninstall ollama`). Install never runs `ollama` itself.
- Without `llama-server` on PATH it prints
  `run: brew install llama.cpp, then claude-custom install` and skips the rest.
  A build below 9200 gets a `brew upgrade llama.cpp` warning.
- It writes `~/.claude-ollama/presets/models.ini`
  (`bin/ollama-profiles --user-presets`) and runs `ollama-agent -apply`, which
  writes `~/Library/LaunchAgents/local.llama-server.plist`, stops the
  `brew services` `llama.cpp` service if it is loaded, and reloads the agent.
  The server listens on `http://127.0.0.1:11435` (`LLAMA_SERVER_URL` overrides
  the URL the tools use).

Install downloads no weights. `claude-ollama prepare 27b` (or any size) fetches
the size's pinned GGUF into `~/.claude-ollama/weights/` and checks its sha256,
`claude-ollama prepare-embedding` does the same for the `semantic_search` model,
and a launch fetches whatever is missing. Server settings live in
`ollama/server.ini`; change one on this machine with
`ollama-agent -set KEY=VALUE`, which writes
`~/.claude-ollama/presets/server.local.ini` and reloads the server.

`claude-ollama doctor` checks the server, its presets, the weights and the GPU
wired limit. When `iogpu.wired_limit_mb` is below model plus KV it warns and
names the `sudo sysctl iogpu.wired_limit_mb=<N>` to run; that setting does not
survive a reboot.

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
rc block points into the repo. `update` also picks up new links, rewrites the
llama-server presets and reapplies its LaunchAgent. The session browser is a
plain cmux browser surface in the `claude-ollama` browser profile; `page_check`
opens only localhost URLs.

## Is the other machine running the same thing?

Every `claude-ollama` launch and every `claude-custom update` writes a beacon
(`bin/sync-fingerprint`: commit, dirty tree, model weights, server settings,
hook and sandbox hashes, Claude Code version) to
`~/.local/share/claude-custom/console/beacon/<host>.json`, and
`claude-ollama doctor` says how old it is and whether its commit is HEAD. To
compare two machines, run `claude-custom sync-check --write` on one, copy
`~/.config/claude-custom/beacon.json` to the other, and run
`claude-custom sync-check` there (or `sync-check --against FILE`): it lists each
section that differs, exits 1 when they do, 0 when they match and 2 without a
beacon. Nothing is sent anywhere by itself.
