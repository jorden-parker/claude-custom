# Task eval

## What it measures

The benches time tokens per second and cache reuse, and `pr-review-eval` scores
review verdicts. `bin/task-eval` measures what you feel: the seconds from a
prompt to a green test on a small coding task, counting the wrong tool calls and
guard denials along the way.

```sh
claude-ollama task-eval 27b                 # every task once, scorecard on stdout
claude-ollama task-eval 35b --runs 3 --json # three runs each, report saved
bin/task-eval --model qwen3.8-27b-cc-next   # a model that has no size yet
bin/task-eval --task shell-fix --task go-table
```

Each run copies a task's fixture to a temp folder, commits it, runs
`claude-ollama <size> -p "<prompt>"` there (no beacon, proxy, drafts or
incidents; telemetry to a temp file), then runs the task's test command. The
scorecard has one line per run (`task result seconds calls denials`), a `total:`
line (`N/M green, median seconds S, p90 P`, over the green runs) and a block to
paste into Claude. `--json` prints the same as JSON, with every run, the model
and the environment at the start (`power`: `ac` or `battery`, `cpu_speed_limit`
from `pmset -g therm`), and saves it to `~/bench-results/task-eval-<utc>.json`.
`bin/model-upgrade SIZE --eval` runs it on the candidate and compares with the
current model's newest saved report.

## Another backend, same harness

`--external URL MODEL [--external-token TOKEN]` runs every task against a server
you started yourself, such as the one
`bin/backend-bench-off serve-only SERVER MODEL` prints (`url`, `model_id`,
`auth_token`):

```sh
bin/task-eval 27b --external http://127.0.0.1:8090 mlx-community/Qwen3-27B-4bit --json
```

task-eval hands the launcher `CLAUDE_OLLAMA_EXTERNAL_URL`,
`CLAUDE_OLLAMA_EXTERNAL_MODEL` and, with a token,
`CLAUDE_OLLAMA_EXTERNAL_TOKEN`. With both of the first two set, `claude-ollama`
skips every Ollama step (model pull and create, digest checks, memory fit,
lease, ladder, warm-up, indexer), prints
`claude-ollama: external backend: MODEL at URL`, and launches `claude` with the
size's usual settings, hooks, system prompt, tools and MCP servers. Only the
backend changes: the launch settings get `ANTHROPIC_BASE_URL` (the messages
proxy's when it runs, which then forwards to the URL), `model`,
`availableModels` and every `ANTHROPIC_DEFAULT_*_MODEL` set to MODEL, and the
token as `ANTHROPIC_AUTH_TOKEN` (the profile's own token without one).
`semantic_search` ranks by words only, since the server has no embedding model.
Setting only one of the URL and the model exits 2. The JSON report gains
`"backend": {"url": URL, "model": MODEL}` and names MODEL as its `model`; the
token is never printed or saved. The token travels on task-eval's command line,
so on a shared machine export `CLAUDE_OLLAMA_EXTERNAL_TOKEN` instead and leave
`--external-token` off.

`--record DIR` turns the messages proxy on for every run
(`CLAUDE_OLLAMA_PROXY=1`, `CLAUDE_OLLAMA_PROXY_RECORD=1`) and saves each request
body to DIR (`CLAUDE_OLLAMA_PROXY_RECORD_DIR`) instead of
`~/.claude-ollama/proxy/record`, so a run leaves replay bodies for
`bin/prefix-ab --record DIR` and `messages-bench --replay`.

A `timeout` result means the launcher ran past the task's `timeout_seconds` and
was stopped; `red` means it finished but the test still fails.

## Adding a task

Make `eval/tasks/<name>/` with three parts:

- `task.json`: `prompt` (what the session is told, naming the test command),
  `test` (run with `sh -c` in the fixture copy), `timeout_seconds` and
  `language`.
- `fixture/`: a tiny self-contained project (under 30 files, no package
  downloads) whose test fails until the change is made. Keep the test itself
  stdlib-only: `python3 -m unittest`, `go test ./...`, a `.test.sh`.
- `solution.patch`: a `git diff` that makes the test pass, applied with
  `git apply` by the test script's stub launcher.

Check the task by hand, red then green:

```sh
work="$(mktemp -d)" && cp -R eval/tasks/<name>/fixture/. "$work" && cd "$work"
sh -c "$(jq -r .test /path/to/eval/tasks/<name>/task.json)"   # must fail
git init -q && git apply /path/to/eval/tasks/<name>/solution.patch
sh -c "$(jq -r .test /path/to/eval/tasks/<name>/task.json)"   # must pass
```

Then run `bin/task-eval.test.sh`: it lists the tasks it expects, checks each
`task.json` and fixture size, and runs every task once with a stub launcher that
does nothing (all red) and once with one that applies the patches (all green).
Add the new name to its `expected_tasks` line.
