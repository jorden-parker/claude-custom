# Backend bench

## What it measures

`bin/messages-bench` drives any server that speaks Anthropic's `/v1/messages`
streaming endpoint, the same one Claude Code uses, and reports:

- cold and warm time to first token (TTFT) at each prefix size. The cold request
  is a new prefix; the warm request resends the same prefix with a different
  question, so a working prefix cache shows up as a lower warm TTFT.
- prefill rate (input tokens per second of TTFT) and decode rate (output tokens
  per second after the first token).
- whether tool calls come back as parseable `tool_use` blocks.

The numbers include HTTP and SSE overhead on purpose. Run it against the server
Claude Code will really use:

```sh
bin/messages-bench --base-url http://localhost:11434 --model tiel-coder-35b-mlx-cc
```

Use `--prefix-tokens 20000 60000` (the default) to match a coding agent's system
prompt plus history, `--tool-trials 0` to skip the tool check, and `--json` for
machine-readable output.

## Bench-off on the work laptop

The owner runs this, not an agent. Three commands, from the repo root:

```sh
bin/backend-bench-off install    # brew install oMLX, uv tool install vllm-mlx 0.4.1
bin/backend-bench-off download   # about 40 GB into ~/bench-models
bin/backend-bench-off all        # Ollama, oMLX, vllm-mlx, then the report
```

`all` ends by writing `~/bench-results/bench-off.html` and opening it. The page
has one table per model with the servers side by side, the best value in each
row highlighted, a PASS/FAIL verdict per candidate against Ollama, and a
headline: "Switch to oMLX", "Switch to vllm-mlx" or "Stay on Ollama".

Before `all`, start Ollama (`brew services start ollama`), stop the oMLX
Homebrew service if it runs (`brew services stop omlx`), and close anything
heavy. The bench needs `hf`, `jq` and `uv` on `PATH`. A full run takes about an
hour. If one server fails, `all` still benches the others, writes the report and
names the failure. Server logs are in `~/bench-results/logs/`.

Each step also runs on its own: `bin/backend-bench-off ollama`, `omlx`,
`vllm-mlx`, then `report` to rebuild the page from whatever results exist.
`--help` lists the environment variables: `BENCH_MODELS`, `BENCH_RESULTS`,
`BENCH_OMLX_PORT` (8100), `BENCH_VLLM_PORT` (8200) and `VLLM_MLX_EXTRA_ARGS`.
For example, `VLLM_MLX_EXTRA_ARGS=--enable-mtp bin/backend-bench-off vllm-mlx`
tries the 35B's MTP heads.

## Models

Every server loads the same Hugging Face MLX weights from `~/bench-models`, so
the comparison measures the server, not the quantization.

| Model ID         | Hugging Face repo                                  | Size    | Role                                |
| ---------------- | -------------------------------------------------- | ------- | ----------------------------------- |
| `tiel-coder-35b` | `peculiar-ragdoll/Tiel-Coder-35B-A3B-MLX-oQ4e-MTP` | 21.6 GB | 35B-A3B MoE; decides the switch     |
| `qwen3.8-27b`    | `mlx-community/Qwen3.8-27B-4bit`                   | 16.1 GB | 27B dense; the slow case            |
| `qwen3-4b-cc`    | `mlx-community/Qwen3-4B-4bit`                      | 2.3 GB  | side model; downloaded, not benched |

- Each server names a model after its directory: Ollama as `bench-<id>`
  (imported with `ollama create` and a 64k `num_ctx`), oMLX and vllm-mlx as
  `<id>`.
- The side model is for the real Claude Code session in the decision rule.
  Subagents and the Haiku slot use it, and Claude Code sends both models to the
  same `ANTHROPIC_BASE_URL`, so the winning server must serve it too under the
  name every profile uses, `qwen3-4b-cc`.
- The embedding model (`qwen3-embedding:0.6b`) is not benchmarked.
  `semantic_search` keeps calling Ollama's `/api/embed` whichever server runs
  the chat model.
- Only one server runs at a time, and Ollama unloads each model after its run.
  On 48 GB the 35B plus a 64k KV cache fits; two main models would not.

## How each server runs

- Ollama: the running service at `$OLLAMA_HOST` (default `localhost:11434`).
- oMLX: `omlx serve --headless --model-dir ~/bench-models --api-key local-bench`
  with `OMLX_PORT=8100`, so it doesn't collide with a Homebrew service on 8000.
  It serves both models from one process.
- vllm-mlx: one process per model,
  `vllm-mlx serve ~/bench-models/<id> --port 8200 --served-model-name <id> --continuous-batching --use-paged-cache --enable-auto-tool-choice --tool-call-parser qwen --reasoning-parser qwen3`.

For each model, `messages-bench` runs twice: a warm-up that loads the model and
a measured run. Peak memory is the highest system memory in use (active, wired
and compressed pages from `vm_stat`) during the two runs. It covers the whole
machine, so close other apps.

## Decision rule

The report applies it. A candidate passes when all three hold at the largest
prefix (60k):

- warm TTFT is at least 30% lower than Ollama's;
- warm decode t/s is at least 90% of Ollama's;
- every tool call parses (5/5).

The headline picks oMLX if it passes on every model, else vllm-mlx, else "Stay
on Ollama". Before switching, confirm with a real Claude Code session of about
20 tool-using turns on the winner, with no malformed tool calls.

## oMLX facts (fill in when oMLX wins)

- Server URL and port the Homebrew service listens on: TODO
- Whether an API key is required, and which env var or config sets it (record
  the location, never a real key value): TODO
- Is the `/v1/models` ID exactly the subdirectory name under `--model-dir`?
  (yes/no): TODO
- The `--model-dir` path: TODO
- Is a newly added model directory picked up without `omlx restart`? (yes/no):
  TODO
- The side model `mlx-community/Qwen3-4B-4bit` in `<model-dir>/qwen3-4b-cc`
  answers as `qwen3-4b-cc` and returns tool calls (yes/no): TODO
- Does `/v1/messages/count_tokens` exist? (yes/no): TODO
