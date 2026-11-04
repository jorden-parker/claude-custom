# Backend bench

## One command

```sh
claude-custom bench-best            # both models
claude-custom bench-best --quick    # the 35b only
claude-custom bench-best --fresh    # rerun finals cells already measured
```

`bin/bench-best` refuses on battery, in Low Power Mode, while a claude-ollama
session runs or without `jq`. It records replay bodies with `bin/task-eval` when
`BENCH_REPLAY_DIR` has none, runs `backend-bench-off all` (`--quick` sets
`BENCH_ONLY_MODELS=qwen3.6-35b`), then the finals: for each model, Ollama and
each finalist in `plan.json` are served one at a time with
`backend-bench-off serve-only` and timed with
`task-eval SIZE --external URL MODEL --runs 1 --json`, task by task (the token
goes through `CLAUDE_OLLAMA_EXTERNAL_TOKEN`, never argv). A challenger over 1.5x
the baseline's seconds after two tasks is recorded as `lost`; one whose median
is within 15% of the baseline's gets three runs per task, and so does the
baseline. Finals are saved after each cell to `$BENCH_RESULTS/finals.json` (and
`bench-best/finals.json`, which `all` never clears), so a rerun skips cells
already measured. It ends by rendering the page, writing
`$BENCH_RESULTS/best-backend.json` (the finals plus the report's `--headline`)
and printing one line: the headline, then each model's green count and median
per cell.

## What it measures

`bin/messages-bench` drives any server that speaks Anthropic's `/v1/messages`
streaming endpoint, the same one Claude Code uses, and reports:

- cold and warm time to first token (TTFT) at each prefix size. The cold request
  is a new prefix; the warm request resends the same prefix with a different
  question, so a working prefix cache shows up as a lower warm TTFT.
- prefill rate (input tokens per second of TTFT) and decode rate (output tokens
  per second after the first token), with `max_tokens` 256 per measurement.
- whether tool calls come back as parseable `tool_use` blocks (`max_tokens` 2048
  per trial).
- `thinking_leak` per run: true when the reply carried a thinking block or text
  containing `<think>`, since thinking tokens inflate decode time.
- `--thinking omit|claude-code|disabled` picks the thinking fields sent: the
  `think` column counts thinking characters, and `text s` is the TTFT of the
  first text token. The bench-off keeps the default `omit`.

Every request body (replayed ones too) carries Qwen's instruct sampling,
`temperature 0.7`, `top_p 0.8`, `top_k 20`; `--temperature`, `--top-p` and
`--top-k` override it.

The numbers include HTTP and SSE overhead on purpose. Run it against the server
Claude Code will really use:

```sh
bin/messages-bench --base-url http://localhost:11434 --model qwen3.6-35b-cc
```

Use `--prefix-tokens 20000 60000` (the default) to match a coding agent's system
prompt plus history, `--tool-trials 0` to skip the tool check, and `--json` (or
`--jsonl`, one line per run) for machine-readable output.
`bin/prefix-ab --verbatim-only` replays recorded bodies once, without the
stabilized pass, as the screen stage does.

## Bench-off on the work laptop

The owner runs this, not an agent. Three commands, from the repo root:

```sh
bin/backend-bench-off install    # every server at its pinned version, under ~/bench-tools
bin/backend-bench-off download   # every set of weights in parallel, about 300 GB, into ~/bench-models
bin/backend-bench-off all        # staged run of 21 cells: gate, screen, cut, deep
```

`install` pins every server: `brew install llama.cpp`, the `jundot/omlx` formula
(it exits 1 at the end when the installed oMLX is not 0.7.3),
`uv tool install --force` of `vllm-mlx==0.6.0` (with `mlx-lm>=0.31.3,<0.32.0`),
`mtplx==2.12.2`, `rapid-mlx==1.0.1` and `mlx-optiq==0.8.0` (Python 3.12),
vllm-metal 0.33.0 from its two pinned release wheels (vLLM's `v0.33.0rc3`
`vllm-0.33.0+cpu` wheel and `vllm_metal-0.33.0`) in its own venv
`~/bench-tools/vllm-metal-0.33.0`, llama.cpp cloned at tag `v0.8.0`
(`BENCH_LLAMA_CPP_TAG`) and built with `GGML_METAL=ON` in Release into
`~/bench-tools/llama.cpp-v0.8.0`, and the mistral.rs `v0.9.5` Metal release
tarball unpacked into `~/bench-tools/mistralrs-v0.9.5` (downloaded with `curl`,
never an install script). A tool already in place is left alone. LM Studio is a
GUI app, so `install` only prints how to get it when `lms` is missing.

`download` lists every missing set of weights on Hugging Face at its pinned
revision, adds up what is still to fetch and stops with
`download needs N GB but only M GB is free` when the disk is short. Then it
downloads all of them at once (each one's `hf` output goes to
`~/bench-models/.download-logs/<name>.log`), checks every file's size against
the listing and marks the folder verified. A second `download` skips what is
verified.

`all` opens `~/bench-results/bench-off.html` straight away and fills it in as
the bench runs: the page reloads itself every 5 seconds, and every measurement
appears as soon as it finishes. The stages are in "Staged run" below. Each unit
is `~/bench-results/<server>--<model>--<stage>.jsonl`; `plan.json` lists the
servers, the models, `stages` and, once the screen is over, `finalists`.

Before `all`, plug in the laptop, turn off Low Power Mode, quit any
`claude-ollama` session, start Ollama (`brew services start ollama`), stop the
oMLX Homebrew service (`brew services stop omlx`) and close anything heavy.
`all` unloads every model Ollama has loaded before each cell. It moves the last
run's units to `~/bench-results/previous/` and reuses those whose server
version, weights revision, bench version and stage are unchanged (status
`cached`), so copy the page out first if you want to keep an earlier one. It
needs `hf`, `jq` and `uv` on `PATH`. A cell that fails (a missing server or
weights, a crash while measuring) is recorded and `all` carries on, then exits 1
at the end naming it; a `gate-failed` or `lost` cell is a result, not a failure.
Logs for each unit are in `~/bench-results/logs/`.

Other commands: `bin/backend-bench-off run SERVER MODEL [screen|deep]` reruns
one cell (deep by default, never reused), `bin/backend-bench-off SERVER` benches
one server on both models (deep), and `bin/backend-bench-off report` rebuilds
the page. `bin/backend-bench-off serve-only SERVER MODEL` starts one cell's
server with exactly its bench flags, passes the gate, prints one JSON line
`{"url","model_id","auth_token"}` and stays up until SIGTERM or SIGINT, then
cleans up like a finished cell; it exits 3 with nothing on stdout when the gate
fails. Its logs go to `~/bench-results/serve-only/`, outside the page. `--help`
lists the environment variables: `BENCH_MODELS`, `BENCH_RESULTS`, `BENCH_TOOLS`,
`BENCH_GATE_SECONDS` (120), `BENCH_THERMAL_POLL` (10 s), `BENCH_THERMAL_MAX`
(900 s), `BENCH_LLAMA_CPP_TAG`, one port per server (`BENCH_OMLX_PORT` 8100,
`BENCH_VLLM_PORT` 8200, `BENCH_LLAMA_PORT` 8300, `BENCH_VLLM_METAL_PORT` 8400,
`BENCH_LMSTUDIO_PORT` 8500, `BENCH_MTPLX_PORT` 8600, `BENCH_RAPID_PORT` 8700,
`BENCH_OPTIQ_PORT` 8800, `BENCH_MISTRALRS_PORT` 8900), `VLLM_MLX_EXTRA_ARGS` and
`LLAMA_SERVER_EXTRA_ARGS` (for example `--cache-reuse 256`).

Every measured cell also replays recorded bodies from `BENCH_REPLAY_DIR`
(default `~/.claude-ollama/proxy/record`, filled by a session launched with
`CLAUDE_OLLAMA_PROXY_RECORD=1`; `BENCH_REPLAY_DIR=` turns it off) through
`bin/prefix-ab`, clearing the cache first (`/api/chat` keep-alive 0 on Ollama,
`/slots/0?action=erase` on llama-server, nothing elsewhere): 10 bodies with
`--verbatim-only` in the screen, `BENCH_REPLAY_LIMIT` (30) with both passes in
the deep stage. The page's "Replay cache hit %" row shows the verbatim mean. It
is shown, not judged by the decision rule.

The console's Benchmarks page (`claude-ollama ui`, then `/benchmarks`) can run
one cell (`bench-off-run`) and rebuild the report (`bench-off-report`), and
embeds the report in a frame that allows scripts only. Its server list
(`web/console/src/lib/bench-choices.ts`) must equal the script's `servers=`
line; `bench-choices.test.ts` checks it. It can't run `install`, `download` or
`all`: those stay in the terminal, as above. The same page shows the last 20
bench runs and the tool telemetry report, see `docs/ollama.md` under Console.

## Models

Every folder lives in `~/bench-models` (Rapid-MLX's in the Hugging Face cache,
since it serves its own registry aliases). A pinned revision is downloaded at
that revision; an unpinned one records the revision it got (from `hf`'s download
metadata) in the cell's `weights_revision`.

| Directory              | Hugging Face repo, revision                                                                                         | Runs in                                                      |
| ---------------------- | ------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------ |
| `qwen3.6-35b`          | `mlx-community/Qwen3.6-35B-A3B-4bit` @ `38740b8`                                                                    | `ollama`, `vllm-metal`, `lmstudio-mlx`                       |
| `qwen3.8-27b`          | `mlx-community/Qwen3.8-27B-4bit` (unpinned)                                                                         | the same                                                     |
| `qwen3.6-35b-mtp`      | `Jundot/Qwen3.6-35B-A3B-oQ4e-mtp` (unpinned)                                                                        | `ollama-mtp`, `omlx`, `omlx-mtp`, `vllm-mlx`, `vllm-mlx-mtp` |
| `qwen3.8-27b-mtp`      | `Jundot/Qwen3.8-27B-oQ4e-mtp` (unpinned)                                                                            | the same                                                     |
| `qwen3.6-35b-gguf`     | `unsloth/Qwen3.6-35B-A3B-GGUF` `UD-Q4_K_XL` @ `a483e9e`                                                             | `llama-server*` but `-mtp`, `mistralrs`                      |
| `qwen3.6-35b-gguf-mtp` | `unsloth/Qwen3.6-35B-A3B-MTP-GGUF` `UD-Q4_K_XL` @ `5bc3e23`                                                         | `llama-server-mtp`                                           |
| `qwen3.8-27b-gguf`     | `unsloth/Qwen3.8-27B-GGUF` `UD-Q4_K_XL` plus `MTP/mtp-Qwen3.8-27B-Q4_0.gguf` @ `4ca7207`                            | every `llama-server*`, `mistralrs`                           |
| `qwen3.6-35b-mtplx`    | `Youssofal/Qwen3.6-35B-A3B-MTPLX-Optimized-Speed` @ `9546051`                                                       | `mtplx`, `mtplx-nomtp`                                       |
| `qwen3.8-27b-mtplx`    | `Youssofal/Qwen3.8-27B-MTPLX-Optimized-Speed` @ `1d5087d`                                                           | the same                                                     |
| `qwen3.6-35b-optiq`    | `mlx-community/Qwen3.6-35B-A3B-OptiQ-4bit` @ `53b24f3`                                                              | `optiq`, `optiq-mtp`, `optiq-ngram`                          |
| `qwen3.8-27b-optiq`    | `mlx-community/Qwen3.8-27B-OptiQ-4bit` @ `a95c290`                                                                  | the same                                                     |
| `qwen3.6-35b-rapid`    | HF cache: `mlx-community/Qwen3.6-35B-A3B-4bit` @ `38740b8` and its drafter `mlx-community/Qwen3.6-35B-A3B-MTP-4bit` | `rapid-mlx`, `rapid-mlx-nomtp` (alias `qwen3.6-35b-4bit`)    |
| `qwen3.8-27b-rapid`    | HF cache: `rapid-mlx/Qwen3.8-27B-4bit-MTP-MLX` @ `aa985c2`                                                          | the same (alias `qwen3.8-27b-4bit`)                          |
| `qwen3-4b-cc`          | `mlx-community/Qwen3-4B-4bit`                                                                                       | side model; downloaded, not measured                         |

- Each cell's meta row records `weights_bytes` (the folder's size on disk, or
  the Hugging Face cache folders for Rapid-MLX) next to `weights_revision`.
- Ollama serves each directory as `bench-<directory>`, imported with
  `ollama create`, a 64k `num_ctx` and the sampling defaults; an import without
  `presence_penalty` is redone. The other servers serve it as `<directory>`,
  except `optiq` (`<repo>:no-think`) and `mistralrs` (`default`).
- The side model is for the real Claude Code session in the decision rule.
  Subagents and the Haiku slot use it, and Claude Code sends both models to the
  same `ANTHROPIC_BASE_URL`, so the winning server must serve it too, under the
  name every profile uses: `qwen3-4b-cc`.
- The embedding model (`qwen3-embedding:0.6b`) is not benchmarked.

## MTP

MTP (multi-token prediction) uses a model's built-in draft head to propose extra
tokens, which the main model checks in the same forward pass. It speeds up
decode and leaves TTFT alone. Every MTP pair runs the same weights with
speculation off and on. Each cell reads its status where the server exposes it:

- `ollama-mtp`: `draft_num_predict 4`. Ollama exposes no acceptance count, so
  its status reads "unverified".
- `omlx-mtp`: `mtp_enabled true` and `mtp_fixed_depth 3` through oMLX's admin
  API; the server log says whether the head is active.
- `vllm-mlx-mtp`: `--enable-mtp --mtp-num-draft-tokens 3`, after
  `bin/extract-mtp-weights` writes `<model>/mtp/weights.safetensors`;
  `/v1/status` gives the acceptance counts.
- `llama-server-mtp` (and `llama-server-ngram`): the acceptance line in the
  server log.
- `mtplx`: `/health` `mtp_enabled` and `depth`.
- `rapid-mlx`, `optiq-mtp`, `optiq-ngram`: unverified, no acceptance count the
  bench can read.

On the page, "MTP active" says yes, no or unverified, with the server's reason.
"Decode vs MTP off" gives the warm decode ratio at the largest prefix against
the same server without MTP.

## Fair settings

Every server runs at its own best settings, with the same model quality, the
same sampling and the same limits, so a difference in the table is the server's.
The sources behind each value are in the research notes under
`~/.claude-ollama/research/research_notes/Fair backend benchmark settings/`.

Common to every cell:

- Sampling: Qwen's instruct values for both models, `temperature 0.7`,
  `top_p 0.8`, `top_k 20` in every request body, and `min_p 0`,
  `presence_penalty 1.5`, `repetition_penalty 1.0` as server defaults where the
  server has a setting for them (the Anthropic body carries only the first
  three).
- Thinking off, through each server's own switch (below). A reply that still
  carries thinking (a thinking block or `<think>` text) is flagged on the page,
  since thinking tokens would inflate decode time.
- Context 65536 tokens, one sequence at a time, `max_tokens` 256 per measurement
  and 2048 per tool trial.
- In-memory prefix caches on, about 8 GB where the server sizes them. Disk
  caches that survive a restart are off or start empty in a temp dir, so a cold
  prompt is really cold.
- Weights of comparable size: the page shows each cell's weights size, and a
  candidate whose weights are under 90% of the baseline's gets no verdict, so a
  smaller quant can't win by being smaller.
- An MTP pair (off and on) runs the same weights, so the ratio between them is
  MTP's alone.
- Each server is pinned to one version, and the cell records it.

| Cell                                | Weights                          | Server and settings                                                                                                                                                                                                                                                                                                                                                                                                       |
| ----------------------------------- | -------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `ollama` (baseline)                 | stock MLX 4-bit                  | the running Ollama with `ollama/server.env`, as the harness uses it; the import sets `num_ctx 65536`, `min_p 0`, `presence_penalty 1.5`, `repeat_penalty 1.0`                                                                                                                                                                                                                                                             |
| `ollama-mtp`                        | `oQ4e-mtp`                       | as above, `draft_num_predict 4` (MTP status unverified)                                                                                                                                                                                                                                                                                                                                                                   |
| `omlx`, `omlx-mtp`                  | `oQ4e-mtp`                       | oMLX 0.7.3, `--port 8100 --base-path <fresh temp dir> --max-concurrent-requests 1 --hot-cache-max-size 6GB`; per model `max_context_window 65536`, `enable_thinking false`, `turboquant_kv_enabled false`, `mtp_enabled` off or on with `mtp_fixed_depth 3`                                                                                                                                                               |
| `vllm-mlx`, `vllm-mlx-mtp`          | `oQ4e-mtp`                       | vllm-mlx 0.6.0, `--continuous-batching --use-paged-cache --max-num-seqs 1 --cache-memory-mb 8192 --enable-auto-tool-choice --tool-call-parser qwen3_xml --reasoning-parser qwen3 --default-chat-template-kwargs {"enable_thinking":false} --max-request-tokens 65536`; MTP adds `--enable-mtp --mtp-num-draft-tokens 3`                                                                                                   |
| `vllm-metal`                        | stock MLX 4-bit                  | vllm-metal 0.33.0 from pinned release wheels in its own venv, `--max-model-len 65536 --max-num-seqs 1 --gpu-memory-utilization 0.85 --language-model-only --enable-auto-tool-choice --tool-call-parser qwen3_coder --reasoning-parser qwen3 --default-chat-template-kwargs {"enable_thinking":false} --override-generation-config {"min_p":0,"presence_penalty":1.5,"repetition_penalty":1.0}`; no MTP (Gemma only there) |
| `llama-server`                      | Unsloth `UD-Q4_K_XL` GGUF        | Homebrew llama.cpp, `-c 65536 -ngl 99 -fa on -b 2048 -ub 2048 -ctk f16 -ctv f16 -np 1 --jinja -rea off --cache-ram 8192 --ctx-checkpoints 128 --checkpoint-min-step 128 --cache-reuse 0 --min-p 0 --presence-penalty 1.5 --repeat-penalty 1.0 --metrics`                                                                                                                                                                  |
| `llama-server-q8kv`                 | same                             | as `llama-server` with `-ctk q8_0 -ctv q8_0`                                                                                                                                                                                                                                                                                                                                                                              |
| `llama-server-mtp`                  | Unsloth MTP GGUF                 | as `llama-server`, `--spec-type draft-mtp --spec-draft-n-max 2` (the 27B's separate head as `--spec-draft-model`)                                                                                                                                                                                                                                                                                                         |
| `llama-server-ngram`                | `UD-Q4_K_XL` GGUF                | as `llama-server`, `--spec-type ngram-mod` with the default match, min and max                                                                                                                                                                                                                                                                                                                                            |
| `llama-server-src`                  | `UD-Q4_K_XL` GGUF                | llama.cpp built from tag `v0.8.0` (`GGML_METAL=ON`, `GGML_METAL_EMBED_LIBRARY=ON`, Release), same flags as `llama-server`                                                                                                                                                                                                                                                                                                 |
| `lmstudio-mlx`                      | stock MLX 4-bit                  | LM Studio headless (`lms daemon up`, `lms server start --port 8500`, `lms load <dir> --context-length 65536 --gpu max --identifier <dir>`); `lms ps` is recorded as a `settings` row, flash attention and KV type are not set; afterwards `lms unload --all` and `lms server stop`                                                                                                                                        |
| `mtplx`, `mtplx-nomtp`              | MTPLX `Optimized-Speed`          | MTPLX 2.12.2, `--model <dir> --model-id <dir> --no-auth --context-window 65536 --reasoning off --scheduler-mode serial --ssd-session-cache off --no-stats-footer --temperature 0.7 --top-p 0.8 --top-k 20`; the baseline adds `--no-mtp`                                                                                                                                                                                  |
| `rapid-mlx`, `rapid-mlx-nomtp`      | the registry alias's pinned repo | Rapid-MLX 1.0.1, `serve qwen3.x-NNb-4bit --served-model-name <dir> --context-length 65536 --enable-auto-tool-choice --tool-call-parser qwen3_coder_xml --reasoning-parser qwen3 --hybrid-cache-entries 4 --max-num-seqs 1 --disable-disk-caches`; the baseline adds `--no-spec-decode`; the gate checks the answering model id, since it answers any `claude-*` name                                                      |
| `optiq`, `optiq-mtp`, `optiq-ngram` | `OptiQ-4bit`                     | mlx-optiq 0.8.0, `--max-concurrent 1 --prompt-cache-bytes 8000000000`, model id `<repo>:no-think`, no `--max-context` (it truncates instead of refusing); `--mtp` or `--ngram-draft 16`                                                                                                                                                                                                                                   |
| `mistralrs`                         | `UD-Q4_K_XL` GGUF                | mistral.rs v0.9.5 (Metal), `serve -m <dir> -f <gguf> --host 127.0.0.1 -p 8900 --max-model-len 65536 --max-seqs 1 --paged-attn on`, model id `default`; no MTP (not available for GGUF)                                                                                                                                                                                                                                    |

Every server binds 127.0.0.1 on its own port. Thinking is also off in the gate's
request (`thinking: {type: "disabled"}`). Sampling defaults are set only where a
flag is documented: Ollama, vllm-metal, llama.cpp and MTPLX (temperature, top_p
and top_k only); oMLX, vllm-mlx, LM Studio, Rapid-MLX, OptiQ and mistral.rs rely
on the request body.

Known differences, kept on purpose: the baseline runs Ollama exactly as the
harness does (q8_0 KV cache), and `llama-server-q8kv` gives the like-for-like
comparison. MTPLX and OptiQ run their own quantizations, which mix in 8-bit
layers; the size guard above keeps them comparable.

## Staged run

A full run of every cell on both models at both prefixes would take more than 12
hours, so `all` runs in stages and stops spending time on a cell once it has
lost:

1. Gate (at most `BENCH_GATE_SECONDS`, 120, from the server's start; an Ollama
   import or the vllm-mlx MTP head extraction comes before it): wait for
   `/v1/models` (Ollama: `/api/version`), apply the per-model settings (oMLX
   PUT, `lms load`), check the cell's id is served, send one short
   `/v1/messages` request and check the model that answered (the requested id,
   that id without its `:no-think` suffix, or a name containing the weights
   folder or repo), then one
   `messages-bench --prefix-tokens 1000 --tool-trials 1` call whose tool call
   must parse. The unit gets a `{"type": "gate", "status", "reason", "seconds"}`
   row; a failure ends it with status `gate-failed` and the reason (exit 3), and
   it is measured no further.
2. Screen: every cell on the 35B only, the 20k prefix, 3 tool trials and 10
   replayed requests (`prefix-ab --verbatim-only`). A cell whose cold prefill at
   20k is more than 1.5 times slower than `ollama`'s gets status `lost` with the
   reason. Without a baseline result nothing is cut.
3. Deep: the three screened cells with the lowest warm TTFT at 20k (ties keep
   the server order) and `ollama`, on both models, at 20k and 60k, with 5 tool
   trials. `plan.json` gains `finalists`.

Between cells the run waits only while `pmset -g therm` reports a
`CPU_Speed_Limit` below 100, polling every `BENCH_THERMAL_POLL` seconds and
giving up after `BENCH_THERMAL_MAX`. Each meta row carries a `cache_key`
(server, model, stage, server version, weights and their revision, bench
version, stage parameters); `all` reuses a previous unit with the same key that
ended `done`, `cached` or `lost`, copying its rows and ending it `cached`, so
adding one server reruns only that server. A cell whose server is no longer
installed is never reused. All weights download in parallel before the first
cell, after a check that the disk has room.

## Decision rule

The page applies it. Every cell is judged against `ollama` on the same model and
stage; the thresholds are named constants in `bin/backend-bench-report`.

Screening sends a cell to the finals when all of these hold:

- every tool call parses;
- its replay cache hit % is at most 5 points below the baseline's (when both
  have replay data);
- at the largest prefix both measured, warm TTFT is at least 20% lower, or warm
  decode is at least 20% higher with warm TTFT no worse;
- no reply leaked thinking;
- for an MTP cell, MTP is not reported inactive.

A cell whose weights are under 90% of the baseline's (`weights_bytes`) gets "no
verdict: smaller weights" instead. A `gate-failed`, `lost` or `failed` cell
fails; a `cached` one is judged like a finished one. Until the finals exist the
headline names the finalists (cells that pass in every table they ran in), or
says "Stay on Ollama".

The finals (`~/bench-results/finals.json`, written by `bin/bench-best`) hold
`{"models": {"<model>": {"<cell>": {"green", "runs", "median_seconds", "timeouts"}}}, "baseline": "ollama"}`,
and the page shows them as a Finals table. A challenger wins a model when it has
the most green runs, its median seconds to green is at least 15% lower than the
baseline's, and it has no timeouts the baseline lacks. The headline is "Switch
to <cell>" when a cell wins every model it ran on, per-model wording ("Switch
qwen3.6-35b to omlx; stay on Ollama for qwen3.8-27b") when it wins only some,
else "Stay on Ollama".

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
