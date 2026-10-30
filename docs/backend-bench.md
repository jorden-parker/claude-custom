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
- `--thinking omit|claude-code|disabled` picks the thinking fields sent: the
  `think` column counts thinking characters, and `text s` is the TTFT of the
  first text token. The bench-off keeps the default `omit`.

The numbers include HTTP and SSE overhead on purpose. Run it against the server
Claude Code will really use:

```sh
bin/messages-bench --base-url http://localhost:11434 --model qwen3.6-35b-cc
```

Use `--prefix-tokens 20000 60000` (the default) to match a coding agent's system
prompt plus history, `--tool-trials 0` to skip the tool check, and `--json` for
machine-readable output.

## Bench-off on the work laptop

The owner runs this, not an agent. Three commands, from the repo root:

```sh
bin/backend-bench-off install    # brew install oMLX, uv tool install vllm-mlx 0.4.1
bin/backend-bench-off download   # about 78 GB into ~/bench-models
bin/backend-bench-off all        # every model on six server runs, MTP off and on
```

`all` opens `~/bench-results/bench-off.html` straight away and fills it in as
the bench runs: the page reloads itself every 5 seconds, and every measurement
appears as soon as it finishes. Each model gets one table with six columns side
by side (Ollama, oMLX and vllm-mlx, each with MTP off and on), the best value in
each row highlighted, a PASS/FAIL verdict per candidate and, for a run that
failed, the error and the end of its log. The headline counts finished runs,
then says which server to switch to (for example "Switch to oMLX" or "Switch to
vllm-mlx with MTP"), "Stay on Ollama" or, when Ollama itself failed, "No Ollama
baseline". The whole bench takes two to three hours.

Before `all`, plug in the laptop, turn off Low Power Mode, quit any
`claude-ollama` session, start Ollama (`brew services start ollama`), stop the
oMLX Homebrew service (`brew services stop omlx`) and close anything heavy.
`all` unloads every model Ollama has loaded before each run. It starts from an
empty `~/bench-results`, so copy the page out first if you want to keep an
earlier one. It needs `hf`, `jq` and `uv` on `PATH`. If a run fails, `all`
carries on with the rest and exits 1 at the end. Logs for each run are in
`~/bench-results/logs/`.

Other commands: `bin/backend-bench-off run SERVER MODEL` reruns one cell,
`bin/backend-bench-off SERVER` (`ollama`, `ollama-mtp`, `omlx`, `omlx-mtp`,
`vllm-mlx`, `vllm-mlx-mtp`) benches one server on every model, and
`bin/backend-bench-off report` rebuilds the page. `--help` lists the environment
variables: `BENCH_MODELS`, `BENCH_RESULTS`, `BENCH_COOLDOWN` (60 s),
`BENCH_OMLX_PORT` (8100), `BENCH_VLLM_PORT` (8200), `BENCH_SERVER_TIMEOUT` and
`VLLM_MLX_EXTRA_ARGS`.

The console's Benchmarks page (`claude-ollama ui`, then `/benchmarks`) can run
one cell (`bench-off-run`) and rebuild the report (`bench-off-report`), and
embeds the report in a frame that allows scripts only. It can't run `install`,
`download` or `all`: those stay in the terminal, as above. The same page shows
the last 20 bench runs and the tool telemetry report, see `docs/ollama.md` under
Console.

## Models

Each model has two sets of weights in `~/bench-models`. The MTP-off columns run
the stock weights, quantized the standard mlx-lm way (4-bit affine, group 64).
The MTP-on columns run the same base model from oMLX's author, quantized with
oMLX's `oQ4e` quantizer, which keeps the MTP draft head that the stock weights
drop.

| Directory         | Hugging Face repo                    | Size    | Runs in                              |
| ----------------- | ------------------------------------ | ------- | ------------------------------------ |
| `qwen3.6-35b`     | `mlx-community/Qwen3.6-35B-A3B-4bit` | 20.4 GB | 35B-A3B MoE, MTP-off columns         |
| `qwen3.6-35b-mtp` | `Jundot/Qwen3.6-35B-A3B-oQ4e-mtp`    | 21.6 GB | 35B-A3B MoE, MTP-on columns          |
| `qwen3.8-27b`     | `mlx-community/Qwen3.8-27B-4bit`     | 16.1 GB | 27B dense, MTP-off columns           |
| `qwen3.8-27b-mtp` | `Jundot/Qwen3.8-27B-oQ4e-mtp`        | 17.0 GB | 27B dense, MTP-on columns            |
| `qwen3-4b-cc`     | `mlx-community/Qwen3-4B-4bit`        | 2.3 GB  | side model; downloaded, not measured |

- Earlier versions of this bench used
  `peculiar-ragdoll/Tiel-Coder-35B-A3B-MLX-oQ4e-MTP` for every column. Tiel is a
  fine-tune with its own chat template, and its model card says only oMLX runs
  it correctly, so it favoured oMLX and likely broke the other servers. Delete
  `~/bench-models/tiel-coder-35b` and `~/bench-models/qwen3.8-27b-oq4e` to get
  about 39 GB back.
- Ollama serves each directory as `bench-<directory>`, imported with
  `ollama create` and a 64k `num_ctx`. oMLX and vllm-mlx serve it as
  `<directory>`.
- The side model is for the real Claude Code session in the decision rule.
  Subagents and the Haiku slot use it, and Claude Code sends both models to the
  same `ANTHROPIC_BASE_URL`, so the winning server must serve it too, under the
  name every profile uses: `qwen3-4b-cc`.
- The embedding model (`qwen3-embedding:0.6b`) is not benchmarked.
  `semantic_search` keeps calling Ollama's `/api/embed` whichever server runs
  the chat model.

## MTP

MTP (multi-token prediction) uses a model's built-in draft head to propose extra
tokens, which the main model checks in the same forward pass. It speeds up
decode and leaves TTFT alone. Each MTP run is set up differently:

- Ollama with MTP (`ollama-mtp`): the MTP weights imported as
  `bench-<model>-mtp` with `draft_num_predict 4`. Ollama exposes no acceptance
  count, so its MTP status reads "unverified".
- oMLX with MTP (`omlx-mtp`): `mtp_enabled` switched on for the model through
  oMLX's admin API for the run and off again afterwards. Its server log says
  whether the head is active. A checkpoint with no MTP tensors is refused with
  the reason.
- vllm-mlx with MTP (`vllm-mlx-mtp`): the same command plus `--enable-mtp`.
  vllm-mlx 0.4.1 loads the head only from `<model>/mtp/weights.safetensors`, so
  the run first writes that file with `bin/extract-mtp-weights` (roughly 0.3 to
  1 GB) and afterwards reads `/v1/status` for the acceptance counts.

On the page, "MTP active" says yes, no or unverified, with the server's reason.
An MTP run that reports MTP inactive fails. "Decode vs MTP off" gives the warm
decode ratio at the largest prefix against the same server without MTP, so ×1.25
means 25% faster. That ratio compares the `oQ4e` weights with the stock ones, so
treat it as a guide, not an exact speed-up.

## Keeping it fair

- Same prompts, same `temperature: 0`, same `max_tokens` (256 per measurement,
  2048 per tool trial) and the same 20k and 60k prefixes on every server.
- Like for like: an MTP-off candidate is judged against Ollama on the same stock
  weights, and an MTP-on candidate against Ollama with MTP on the same `oQ4e`
  weights. A candidate whose baseline is missing gets no verdict.
- Model by model: each model runs on all six server runs back to back, so the
  runs being compared happen minutes apart, not hours. A 60-second cool-down
  before every run starts each one at a similar temperature.
- One server and one model at a time. Before each run the script unloads every
  model Ollama holds and refuses to start if something already answers on the
  candidate's port. Afterwards it stops the server it started and turns oMLX's
  MTP setting back off.
- Each run begins with a short warm-up request that loads the model, so load
  time never counts. Every measured cold prompt then starts with a marker no
  earlier request used, so no prompt cache (oMLX keeps one on disk) can make it
  warm.
- Each run records its power source, Low Power Mode and the memory in use before
  it starts. The page flags any run that was on battery or in Low Power Mode.
  Peak memory is the whole machine's (active, wired and compressed pages from
  `vm_stat`), so close other apps.
- Known difference: Ollama keeps its own server settings (`ollama/server.env`:
  flash attention, q8_0 KV cache) and chat-template handling. The other servers
  use their defaults: fp16 KV cache and the template shipped with the weights.

## How each server runs

- Ollama: the running service at `$OLLAMA_HOST` (default `localhost:11434`).
- oMLX: `omlx serve --headless --model-dir ~/bench-models --api-key local-bench`
  with `OMLX_PORT=8100`, so it doesn't collide with a Homebrew service on 8000.
- vllm-mlx: one process per run,
  `vllm-mlx serve ~/bench-models/<directory> --port 8200 --served-model-name <directory> --continuous-batching --use-paged-cache --enable-auto-tool-choice --tool-call-parser qwen --reasoning-parser qwen3`.

## Decision rule

The page applies it. A candidate passes when all of these hold at the largest
prefix (60k), against its baseline:

- warm TTFT is at least 30% lower;
- warm decode t/s is at least 90% of the baseline's;
- every tool call parses (5/5);
- for an MTP run, MTP is not reported inactive.

The headline picks the first candidate, in the order oMLX, oMLX with MTP,
vllm-mlx, vllm-mlx with MTP, that passes on every model it could be judged on,
else "Stay on Ollama". Before switching, confirm with a real Claude Code session
of about 20 tool-using turns on the winner, with no malformed tool calls.

## Ollama MLX vs Unsloth GGUF

The `27b-gguf` and `35b-gguf` sizes run the same models as the MLX sizes, from
Unsloth's Q4_K_XL GGUF files. Compare them on the work laptop with one command,
plugged in and with no other `claude-ollama` session open:

```sh
git pull && claude-ollama speed-check
```

It stops with a one-line fix when Ollama is down, the laptop is on battery or in
Low Power Mode, another session runs, or a GGUF import lacks 45 GB of disk, and
it is safe to rerun: imported models and an interrupted download are kept. In
order, it runs `claude-ollama prepare` for the four sizes, checks each GGUF
model's `ollama show --modelfile` for `RENDERER` and `PARSER`, runs the plan 066
thinking check (`bin/messages-bench --prefix-tokens 2000 --tool-trials 3` with
`--thinking claude-code`, then `disabled`, on both MLX models), benches each
pair back to back with `--thinking disabled --tool-trials 5`, and runs
`bin/ollama-cache-probe SIZE --json` on all four sizes. It saves everything to
`~/bench-results/speed-check-YYYYmmdd-HHMM.json` and prints a verdict, a `Next:`
line and a block to paste back to Claude.

A GGUF size is better for its model when, at the 60k prefix, its warm TTFT is
lower than the MLX size's, its warm decode t/s is at least 90% of MLX's, its
tool calls are 5/5, and its cache-probe verdict says the cache is reused. The
owner may make a GGUF size the default in a separate change. If none is better,
keep the sizes as options or remove them. The `ollama show --modelfile` lines
must show `RENDERER` and `PARSER`; without them Ollama would use the file's own
template, and the size must not be used.

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
