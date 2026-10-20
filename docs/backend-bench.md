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

## Models

Every server loads the same Hugging Face MLX weights, so the comparison measures
the server, not the quantization. All are 4-bit MLX repos.

| Role                       | Hugging Face repo                                  | Size on disk | Ollama name                             | oMLX directory / ID      |
| -------------------------- | -------------------------------------------------- | ------------ | --------------------------------------- | ------------------------ |
| Main, MoE (bench 1st)      | `peculiar-ragdoll/Tiel-Coder-35B-A3B-MLX-oQ4e-MTP` | about 22 GB  | `tiel-coder-35b-mlx-cc`                 | `tiel-coder-35b-omlx-cc` |
| Main, dense (bench 2nd)    | `mlx-community/Qwen3.8-27B-4bit`                   | about 16 GB  | `bench-qwen3.8-27b`                     | `bench-qwen3.8-27b`      |
| Side model (session check) | `mlx-community/Qwen3-4B-4bit`                      | about 2.3 GB | `qwen3-4b-cc` (Ollama's own `qwen3:4b`) | `qwen3-4b-cc`            |

- The 35B-A3B MoE is the one that decides the switch. It is already an Ollama
  size (`35b-tiel-mlx`), and its MTP heads may let vllm-mlx's `--enable-mtp`
  speed up decode. Bench it first.
- The 27B dense model is the slow case: every token reads all 27B weights. It is
  the same base as the `27b` size (`qwen3.8:27b-mlx`), but Ollama's tag is not
  byte-identical to the Hugging Face repo, so import the repo into Ollama for
  the bench (below).
- The side model only matters for the real Claude Code session in the decision
  rule. Subagents and the Haiku slot use it, and Claude Code sends both models
  to the same `ANTHROPIC_BASE_URL`, so the candidate server must serve it too.
  `qwen3-4b-cc` is the name every profile uses; keep it. Skip it for the
  `messages-bench` runs.
- The embedding model (`qwen3-embedding:0.6b`) is not benchmarked.
  `semantic_search` keeps calling Ollama's `/api/embed` whichever server runs
  the chat model.

Download each repo once and point every server at the same copy:

```sh
export BENCH_MODELS=~/bench-models
hf download peculiar-ragdoll/Tiel-Coder-35B-A3B-MLX-oQ4e-MTP --local-dir "$BENCH_MODELS/tiel-coder-35b-omlx-cc"
hf download mlx-community/Qwen3.8-27B-4bit --local-dir "$BENCH_MODELS/bench-qwen3.8-27b"
hf download mlx-community/Qwen3-4B-4bit --local-dir "$BENCH_MODELS/qwen3-4b-cc"
```

The directory names are the oMLX model IDs, so `$BENCH_MODELS` doubles as oMLX's
`--model-dir`. On 48 GB, load one main model at a time: the 35B (about 22 GB)
plus a 64k KV cache and the side model fits, but two main models do not.

## Bench-off on the work laptop

The owner runs this, not an agent. Use the models above.

Run one server at a time, and keep anything else heavy closed during a
measurement. Run each bench twice and keep the second run.

- Ollama:

  ```sh
  claude-ollama doctor 35b-tiel-mlx
  bin/messages-bench --model tiel-coder-35b-mlx-cc

  printf 'FROM %s\nPARAMETER num_ctx 65536\n' "$BENCH_MODELS/bench-qwen3.8-27b" > /tmp/Modelfile.bench-27b
  ollama create bench-qwen3.8-27b -f /tmp/Modelfile.bench-27b
  bin/messages-bench --model bench-qwen3.8-27b
  ```

- oMLX (first candidate):

  ```sh
  brew tap jundot/omlx && brew install jundot/omlx/omlx
  omlx serve --headless --model-dir "$BENCH_MODELS"
  curl -s <url>/v1/models
  bin/messages-bench --base-url <url> --model tiel-coder-35b-omlx-cc
  bin/messages-bench --base-url <url> --model bench-qwen3.8-27b
  ```

  If `/v1/models` lists different IDs, use those and record it under "oMLX
  facts".

- vllm-mlx (fallback, only if oMLX fails). It serves one model per process:

  ```sh
  uv tool install 'vllm-mlx==0.4.1'
  vllm-mlx serve "$BENCH_MODELS/tiel-coder-35b-omlx-cc" --host 127.0.0.1 --port 8000 --continuous-batching --enable-mtp
  curl -s http://127.0.0.1:8000/v1/models
  bin/messages-bench --base-url http://127.0.0.1:8000 --model <id-from-v1-models>
  ```

  Then stop it and repeat with `"$BENCH_MODELS/bench-qwen3.8-27b"`, without
  `--enable-mtp`. Enable its Qwen tool parser and Qwen3 reasoning parser; the
  flag names are in `vllm-mlx serve --help`.

## Results

| Server + version | Model | Prefix | Cold TTFT | Warm TTFT | Prefill t/s | Decode t/s | Tool calls | Peak memory | Date |
| ---------------- | ----- | ------ | --------- | --------- | ----------- | ---------- | ---------- | ----------- | ---- |
|                  |       |        |           |           |             |            |            |             |      |

Peak memory comes from Activity Monitor.

## Decision rule

Switch only if a candidate meets all four:

- warm TTFT at a 60k prefix is at least 30% lower than Ollama's;
- decode t/s is no more than 10% below Ollama's;
- tool calls parse 5/5;
- a real Claude Code session of about 20 tool-using turns shows no malformed
  tool calls.

Try oMLX first. Try vllm-mlx only if oMLX fails. If neither passes, stay on
Ollama and record that here.

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
