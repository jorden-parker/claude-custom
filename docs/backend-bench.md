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

The owner runs this, not an agent. Every server loads the same weights so the
comparison is fair: Hugging Face repo
`peculiar-ragdoll/Tiel-Coder-35B-A3B-MLX-oQ4e-MTP` (then, if time allows, a 27B
dense MLX repo).

Run one server at a time, and keep anything else heavy closed during a
measurement. Run each bench twice and keep the second run.

- Ollama:

  ```sh
  claude-ollama doctor 35b-tiel-mlx
  bin/messages-bench --model tiel-coder-35b-mlx-cc
  ```

- oMLX (first candidate):

  ```sh
  brew tap jundot/omlx && brew install jundot/omlx/omlx
  hf download peculiar-ragdoll/Tiel-Coder-35B-A3B-MLX-oQ4e-MTP --local-dir <model-dir>/tiel-coder-35b-omlx-cc
  omlx serve --headless --model-dir <model-dir>
  curl -s <url>/v1/models
  bin/messages-bench --base-url <url> --model <model-id-from-v1-models>
  ```

- vllm-mlx (fallback, only if oMLX fails):

  ```sh
  uv tool install 'vllm-mlx==0.4.1'
  vllm-mlx serve <path-to-weights> --host 127.0.0.1 --port 8000 --continuous-batching
  bin/messages-bench --base-url http://127.0.0.1:8000 --model <model-id>
  ```

  Enable its Qwen tool parser and Qwen3 reasoning parser; the flag names are in
  `vllm-mlx serve --help`.

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
- The MLX repo used for the side model (a Qwen3 4B 4-bit MLX repo), downloaded
  into `<model-dir>/qwen3-4b-cc`: TODO
- Does `/v1/messages/count_tokens` exist? (yes/no): TODO
