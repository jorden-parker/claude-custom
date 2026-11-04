# Deep Research: migrating the work harness from Ollama to llama.cpp

Researched 2026-11-03. Depth: thorough (WebSearch plus page reads; Firecrawl's
key was rejected). Scope: replace Ollama fully.

## Executive summary

llama.cpp's `llama-server` now covers everything the harness needs from Ollama:
it serves the Anthropic `/v1/messages` API that Claude Code talks to (since
January 2026), it runs several models in one server with load, unload, LRU
eviction and an idle sleep (router mode, since December 2025), it serves
embeddings, it supports MTP speculative decoding for Qwen 3.6/3.8, and it
exposes `/health`, `/metrics`, `/slots` and a JSONL log. So the migration is
practical. The harness's own seams (the messages proxy, the lease, the watcher,
`sizes.json` as the single source) carry over.

There are two large risks, and the plan starts by measuring both on the work
laptop before any harness code changes:

1. **Losing MLX.** Since Ollama 0.19 (March 2026) Ollama runs Apple Silicon
   models on MLX, and the default `27b` and `35b` sizes are MLX builds.
   llama.cpp runs GGUF on Metal only. Published numbers disagree: some show MLX
   decoding much faster (one reports 131.8 vs 72 tok/s for Qwen3.5-35B-A3B on an
   M4 Max), others show llama.cpp with flash attention catching up or winning on
   long-prompt prefill, and the gap narrowing at 27B and above. None of these
   are rigorous. A coding agent spends most of its time on prefill, so prefill
   and cache reuse matter more than decode.
2. **Prompt-cache reuse on hybrid Qwen models.** Qwen 3.5, 3.6 and 3.8 mix Gated
   DeltaNet (recurrent) layers with attention. Recurrent state cannot be reused
   as a prefix, so llama.cpp falls back on context checkpoints and, when none
   fits, logs "forcing full prompt re-processing" and prefills the whole prompt
   again. Claude Code reports of this are many (#20003, #23013, #24714). Some
   were fixed by `CLAUDE_CODE_ATTRIBUTION_HEADER=0`, which every profile here
   already sets. Others were closed without a fix. MTP (+40 to +140% decode) is
   a real upside on the 27B.

Recommendation: run Phase 0 (one command on the work laptop that benches
llama-server against the current Ollama MLX sizes with the existing
`messages-bench`, cache probe, `prefix-ab` and `task-eval`). Go ahead only if
llama-server passes the decision rule already in `docs/backend-bench.md` and
keeps the prefix hit rate. Then migrate in eight phases behind one backend
module, so each phase is small, tested and shippable.

## Key findings

1. **Anthropic API.** `POST /v1/messages` (streaming with Anthropic SSE events,
   `tool_use`/`tool_result`, images, the `thinking` parameter) and
   `POST /v1/messages/count_tokens`. It converts to the OpenAI path inside the
   server. Tool use needs `--jinja`, which is now the default. The README makes
   "no strong claims of compatibility". Sources:
   [HF blog](https://huggingface.co/blog/ggml-org/anthropic-messages-api-in-llamacpp),
   [PR #17570](https://github.com/ggml-org/llama.cpp/pull/17570),
   [server README](https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md).
2. **Router mode replaces Ollama's scheduler.** Start `llama-server` with no
   model. Models come from `--models-dir` or a `--models-preset` INI file
   (sections named by model id, keys are flags without dashes, `[*]` holds
   shared defaults; preset-only keys `load-on-startup`, `stop-timeout`). Each
   model runs in its own process. `--models-max N` (default 4) evicts LRU;
   `--models-memory-margin` evicts until a new model fits;
   `--no-models-autoload` makes loads explicit; `--sleep-idle-seconds` unloads
   idle models. `GET /models` lists `id`, `path`, `status` (`unloaded`,
   `loading`, `loaded`, `sleeping`, ...) and `memory`; `POST /models/load` and
   `/models/unload` take `{"model": id}`. There is no unload-all. Sources:
   [model management blog](https://huggingface.co/blog/ggml-org/model-management-in-llamacpp),
   [server README](https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md),
   [unload guide](https://glukhov.org/llm-hosting/llama-cpp/unload-llama-cpp-router-models/).
3. **Server tuning moves from env vars to flags.** `OLLAMA_FLASH_ATTENTION=1`
   becomes `-fa on`, `OLLAMA_KV_CACHE_TYPE=q8_0` becomes `-ctk q8_0 -ctv q8_0`,
   `OLLAMA_NUM_PARALLEL=1` becomes `-np 1`, `OLLAMA_MAX_LOADED_MODELS=2` becomes
   `--models-max 2`, `OLLAMA_KEEP_ALIVE` becomes `--sleep-idle-seconds`.
   `--host` defaults to `127.0.0.1`. `--metrics` enables Prometheus metrics.
   `--log-file` and `--log-jsonl` give a machine-readable log.
   ([server README](https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md))
4. **Prompt caching.** `cache_prompt` is on by default. `--cache-ram` (default
   8192 MiB) keeps old prompts in host RAM and swaps them back in by prefix
   similarity. `--ctx-checkpoints` (default 32) and `--checkpoint-min-step`
   (default 8192) control the checkpoints hybrid models depend on.
   `--cache-reuse N` (default 0) reuses chunks by KV shifting. A slot only
   reuses its own cache; sharing a prefix across slots is an unmerged proposal
   ([#30664](https://github.com/ggml-org/llama.cpp/discussions/30664)), which
   matters little with `-np 1`. Sources:
   [PR #16391](https://github.com/ggml-org/llama.cpp/pull/16391),
   [KV reuse tutorial](https://github.com/ggml-org/llama.cpp/discussions/13606).
5. **Hybrid-model cache misses are the main unknown.** #20003 (Qwen3.5 with
   Claude Code) was closed after the attribution header fix, with remaining
   checkpoint-erase bursts. #23013 (Qwen3.6-27B, 35 checkpoints checked, none
   usable) was closed as stale without a fix. Reported mitigations: keep
   `--cache-ram` on, raise `--ctx-checkpoints` (128) and lower
   `--checkpoint-min-step` (128). Sources:
   [#20003](https://github.com/ggml-org/llama.cpp/issues/20003),
   [#23013](https://github.com/ggml-org/llama.cpp/issues/23013),
   [Aleksandrov](https://mykolaaleksandrov.dev/posts/2026/06/claude-code-llamacpp-prompt-cache-fix/),
   [syoyo (Japanese)](https://zenn.dev/syoyo/articles/188508eb6ab389),
   [#22384](https://github.com/ggml-org/llama.cpp/issues/22384).
6. **MTP.** Merged in May 2026 (PR #22673; build 9200 or later):
   `--spec-type draft-mtp --spec-draft-n-max 2`. It needs an MTP GGUF
   (`ggml-org/Qwen3.6-27B-MTP-GGUF`, `-35B-A3B-MTP-GGUF`). On a 16 GB RTX 4080,
   27B decode went from 45 to 75 tok/s at the cost of about 25% prefill and half
   the usable context; on the 35B-A3B the gain was smaller. The "MTP changes
   output" report (#23302) was withdrawn because no fixed seed was used.
   Sources:
   [Glukhov benchmark](https://www.glukhov.org/llm-performance/benchmarks/comparing-qwen-3-6-mtp-vs-standard/),
   [#23302](https://github.com/ggml-org/llama.cpp/issues/23302),
   [mer.vin guide](https://mer.vin/2026/05/run-qwen-3-6-mtp-in-llama-cpp-faster-local-inference-with-built-in-speculative-decoding/).
7. **Model coverage.** `ggml-org/Qwen3.8-27B-GGUF` exists (vision-capable, so an
   `mmproj` file comes with it), and Unsloth ships the Qwen 3.6/3.8 GGUFs the
   `-gguf` sizes already pin. The `35b-coding` size is NVFP4, which is
   Ollama-only; it needs a GGUF replacement or has to go. The `3b`
   (`granite4.2:3b`) and the embedding model (`qwen3-embedding:0.6b`) need
   pinned GGUFs. Sources:
   [ggml-org/Qwen3.8-27B-GGUF](https://huggingface.co/ggml-org/Qwen3.8-27B-GGUF),
   [byteshape quants](https://huggingface.co/byteshape/Qwen3.8-27B-GGUF).
8. **Embeddings.** `--embeddings` with `--pooling` serves `POST /v1/embeddings`
   (OpenAI shape). The README flags embeddings as "use only with dedicated
   embedding models". I could not confirm that one router can serve a chat
   preset and an embedding preset side by side, though presets accept any flag,
   so `embeddings = true` per section is plausible.
9. **MLX vs llama.cpp speed is contested.** Ollama's own MLX numbers (M5 Max,
   Qwen3.5-35B-A3B: prefill 1154 to 1810 tok/s, decode about 2x) are a vendor
   benchmark. Independent posts disagree in both directions. Sources:
   [Kapetanovic](https://levelup.gitconnected.com/ollama-mlx-nearly-doubles-llm-speed-on-your-mac-58-to-112-tok-s-and-your-old-models-get-none-of-fd1a9ec531fb),
   [starmorph](https://blog.starmorph.com/blog/apple-silicon-llm-inference-optimization-guide),
   [arXiv runtime comparison via aitopics](https://aitopics.org/doc/arxivorg:43577C43),
   [bestllmfor M4 Max](https://bestllmfor.com/guide/mac-m4-max-llm-local-mlx/).

## Recommended settings on a Mac

The sources agree on a short list. Everything else in `--help` is either the
default already or has no effect on Apple Silicon (`--numa`, `--cpu-mask`,
`--split-mode`, `--no-kv-offload`).

| Setting                                   | Value for this harness                                                               | Why                                                                                                                                               |
| ----------------------------------------- | ------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| `n-gpu-layers`                            | `99` (all)                                                                           | the CPU path is far slower; recent builds default to auto-fit, so set it explicitly                                                               |
| `flash-attn`                              | `on`                                                                                 | faster long-context prefill, smaller attention memory, needed for a quantised KV cache                                                            |
| `batch-size` / `ubatch-size`              | `2048` / `2048` (try `1024` if memory is tight)                                      | the default is 512; bigger micro-batches speed up prefill on Metal, the main cost of an agent turn (one report: a 4K prompt went from 8 s to 3 s) |
| `cache-type-k` / `cache-type-v`           | `q8_0` / `q8_0`                                                                      | halves the KV cache with negligible loss; `q4_0` only when context does not fit                                                                   |
| `parallel`                                | `1`                                                                                  | one user; MTP speculative decoding wants one slot; with an explicit slot count, `ctx-size` is not split                                           |
| `ctx-size`                                | per size from `sizes.json` (never `0`)                                               | `0` means the model's maximum (262K for Qwen 3.6/3.8)                                                                                             |
| `jinja`                                   | on (the default)                                                                     | tool calls and the Qwen thinking switch need the template                                                                                         |
| `cache-ram`                               | keep on (default 8192 MiB; size it to spare RAM)                                     | `0` disables cross-request prompt caching, the main cause of full re-prefills                                                                     |
| `ctx-checkpoints` / `checkpoint-min-step` | `128` / `128`, measured in Phase 0 against the defaults `32` / `8192`                | hybrid Qwen models can only resume from a checkpoint                                                                                              |
| `cache-reuse`                             | `256`, measured in Phase 0                                                           | reuses shifted chunks after an edit in the middle of the prompt; it may not apply to the recurrent layers                                         |
| `threads`                                 | default, or `4` at most; never more than the P-cores                                 | the GPU does the work; extra threads on E-cores slow things down                                                                                  |
| `load-mode`                               | default (`mmap`); `mlock` only when model plus KV plus macOS fit in about 70% of RAM | `mlock` stops paging under pressure but makes the rest of the machine thrash when tight; `--no-mmap` only if a load hangs                         |
| `prio`                                    | `2`                                                                                  | small, measurable gain on long generations                                                                                                        |
| `spec-type`                               | `draft-mtp`, `spec-draft-n-max 2`, MTP GGUF only                                     | +40 to +140% decode on the 27B; costs prefill speed and memory, so it is a Phase 0 cell, not a default                                            |
| `sleep-idle-seconds`                      | `-1`                                                                                 | keep the model resident, as `OLLAMA_KEEP_ALIVE=30m` plus the heartbeat did                                                                        |
| `host`                                    | `127.0.0.1` (the default)                                                            | loopback only, like Ollama today                                                                                                                  |

macOS itself:

- **GPU wired memory limit.** Metal caps GPU allocations at about 75% of RAM
  (about 48 GB on a 64 GB Mac). `sudo sysctl iogpu.wired_limit_mb=N` raises it
  with no reboot; sources suggest leaving 8 to 16 GB for macOS (for example
  57344 on 64 GB). It resets on reboot; `/etc/sysctl.conf` or a LaunchDaemon
  makes it stick. This needs `sudo`, so the harness should only read it
  (`doctor` warns when the model plus KV exceeds it) and print the command,
  never set it.
- **Build from source at a pinned tag.** One M4 report measured a source build
  at 803 vs 622 tok/s prefill for a packaged build of the same release; hybrid
  Qwen support also moves fast, and every guide says to pin the commit and
  retest on bumps. So `claude-custom install` should build a pinned tag with
  `cmake -B build -DGGML_METAL=ON` (Metal is the default on macOS) into
  `~/.cache/claude-custom/llama.cpp`, the way it installs `ctx7`, and doctor
  should report the build.
- **KV memory for hybrid models.** Only the attention layers grow with context
  (one in four in Qwen 3.6/3.8): Qwen3.6-27B is about 64 KB per token at f16, a
  quarter of what `block_count` predicts. `ollama-lease fit` uses `block_count`
  today, so it overestimates the KV cache about four times and may push the
  ladder down for no reason. The fit has to count attention layers only (from
  the GGUF's full-attention interval).

Conflicting advice: one Reddit thread recommends `--cache-ram 0` and
`--ctx-checkpoints 1` on a unified-memory Mac to save RAM, while the cache
reports above say `--cache-ram 0` causes full re-prefills. Phase 0 measures both
on the work laptop.

Sources:
[seven flags on Apple Silicon](https://medium.com/@michael.hannecke/tuning-llama-cpp-on-apple-silicon-843f37a6c3dc)
(2026-04-29),
[tuning llama-server on Apple Silicon, Qwen3.6-27B on an M4 Max](https://medium.com/@michael.hannecke/tuning-llama-server-on-apple-silicon-9b3e778ab100)
(2026-05-07),
[wired limit note](https://github.com/ivanopcode/devnote-override-macos-metal-vram-cap),
[source vs packaged build on an M4](https://discourse.nixos.org/t/llama-cpp-on-apple-silicon-native-build-much-faster-than-nixpkgs/75309),
[M4 Max llama.cpp guide replacing Ollama](https://gist.github.com/adamteale/a41343fdaa5dea1e88931277d6d17908),
[Reddit, Qwen3.6-35B-A3B coding on a Mac](https://www.reddit.com/r/LocalLLaMA/comments/1sq94qx/is_anyone_getting_real_coding_work_done_with/)
(snippet only; the page would not load).

## What changes in this repo

From a read-only inventory of the tree:

| Ollama piece                                                            | Used by                                                                              | llama-server replacement                                                                                                                               |
| ----------------------------------------------------------------------- | ------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `GET /api/tags` (size, digest)                                          | `ollama-server.sh`, `ollama-lease`, `ollama-models`, `sync-fingerprint`, `models.ts` | `GET /models` for presence; file size from the weights file; digest is the pinned file sha256                                                          |
| `GET /api/ps` (resident)                                                | `ollama-lease`, cache probe, `code-search.py`, `rescue.py`, `models.ts`              | `GET /models` `status` and `memory`                                                                                                                    |
| `/api/generate` `keep_alive` (warm, heartbeat)                          | `claude-ollama` `warm_model`, `ollama-lease heartbeat`                               | `POST /models/load`; the heartbeat goes away with `--sleep-idle-seconds -1`                                                                            |
| `/api/chat` `keep_alive: 0` (unload)                                    | cache probe, `prefix-ab`, `mock-spike.mts`                                           | `POST /models/unload`; `mock-spike` moves to `/v1/chat/completions`                                                                                    |
| `/api/embed`                                                            | `code-search.py`, `warm_embedding_model`                                             | `POST /v1/embeddings` with the embedding preset's id                                                                                                   |
| `/api/version`                                                          | launcher, doctor, speed-check, `ollama-health.ts`                                    | `GET /health` (503 while loading), `GET /props` for the build                                                                                          |
| `ollama pull`, `create`, `show`, `rm`, `cp`                             | launcher, `claude-custom`, `model-upgrade`, `speed-check`, picker                    | pinned Hugging Face download plus sha256 (already in `import_gguf`), preset rendering instead of `create`                                              |
| `ollama show --verbose` (KV metadata)                                   | `ollama-lease fit`                                                                   | `bin/gguf-inspect` reads the same three keys from the file                                                                                             |
| `Modelfile.<size>` (`num_ctx`, sampling, `RENDERER`/`PARSER`)           | `ollama-profiles`, `size-profile.sh`, `profile-overlay`, `check-config`              | one rendered `ollama/models.ini` preset: `ctx-size`, `n-predict`, `temp`, `top-k`, `top-p`, `min-p`, `repeat-penalty`, `presence-penalty`, `spec-type` |
| `ollama/server.env` and `local.ollama` LaunchAgent, `go/internal/agent` | install, launcher, console Server page                                               | `local.llama-server` LaunchAgent running `llama-server --models-preset ... --port ...`; server flags live in the preset's `[*]` section                |
| registry manifest pins (`registry.ollama.ai`)                           | `ollama-models`, `model-digests.json`, `check-config`                                | file sha256 pins only; `outdated` compares the pinned Hugging Face revision with the repo's `main`                                                     |
| Ollama log (`time=` slog lines)                                         | `incidents/watcher.py`, `server_log_path`                                            | llama-server `--log-file` (JSONL); new rules, and "forcing full prompt re-processing" becomes a direct `reprefilled` rule                              |
| `CLAUDE_CODE_EXTRA_BODY` `thinking: disabled`                           | every profile, `profile-overlay`, `check-config`                                     | `/v1/messages` takes `thinking`; to be verified in Phase 0, with a preset `reasoning = off` as the fallback                                            |

Names (`claude-ollama`, `~/.claude-ollama`, 50 `CLAUDE_OLLAMA_*` variables) stay
as they are: renaming them is churn with no gain and can be its own change
later.

## Implementation plan

Each phase ends green (`make test`), on main, and usable. Tests come first in
each step (tdd-guard enforces it).

### Phase 0: measure on the work laptop (go/no-go)

One rerunnable command, nothing else changes.

- Done: `bin/backend-bench-off` has `llama-server` and `llama-server-mtp`
  (install with `brew install llama.cpp`; MTP needs build 9200 or later). Each
  run starts one `llama-server` on port 8300 on the pinned Unsloth `UD-Q4_K_XL`
  GGUF with the Mac settings above. MTP uses Unsloth's
  `Qwen3.6-35B-A3B-MTP-GGUF` for the 35B and the 27B's separate head
  `MTP/mtp-Qwen3.8-27B-Q4_0.gguf` as `--spec-draft-model`. Run it with
  `bin/backend-bench-off download`, then `bin/backend-bench-off all` (or
  `bin/backend-bench-off llama-server` for just the new columns).
- Done: `bin/prefix-ab` takes `--unload ollama|llama-slots|none` (llama-server
  clears slot 0 through `/slots/0?action=erase`) and `--auth-token`, and counts
  the cached tokens into the total prompt, since `input_tokens` leaves them out
  (the same fix is in `bin/ollama-cache-probe --replay`). Every
  `bin/backend-bench-off` run replays up to 30 recorded bodies through it, and
  the page shows a "Replay cache hit %" row per server.
- Deferred to Phase 4: `task-eval` drives the full launcher, which still needs
  Ollama.
- `bin/backend-bench-off all` is the one command; no wrapper.

Gate (from `docs/backend-bench.md`): at the 60k prefix, warm TTFT no worse than
Ollama MLX, decode at least 90% of it (or MTP decode above it), tool calls 5/5,
the page's Replay cache hit % within 5 points of Ollama's, and no "forcing full
prompt re-processing" lines in a 30-minute session. Record the numbers in
`docs/backend-bench.md`. If the gate fails, stop here and file the result; retry
on a newer llama.cpp build.

### Phase 1: one backend module

- New `bin/lib/model-server.sh` (sourced, bash 3.2) with the only functions the
  rest of the harness calls: `server_url`, `server_up`, `server_build`,
  `model_listed`, `model_loaded`, `model_resident_bytes`, `model_load`,
  `model_unload`, `embedding_url`, `server_log_path`, `server_setting KEY`.
  Python callers get the same in `shared/model_server.py` (stdlib).
- Tests: `bin/lib/model-server.test.sh` and `shared/model_server.test.sh`
  against one stub llama-server (`/health`, `/models`, `/models/load`,
  `/models/unload`, `/v1/embeddings`, `/props`), shared by later phases.
- Move callers of `ollama-server.sh` onto it in the same phase. This is the seam
  every later phase uses, so later diffs stay local.

### Phase 2: weights and presets from `sizes.json`

- `sizes.json`: every size gets a `gguf` block (`repo`, `revision`, `file`,
  optional `mmproj`, optional `mtp` file), and `renderer`/`parser` go away. The
  MLX sizes `27b` and `35b` become the GGUF builds (the `-gguf` sizes are
  dropped as duplicates). `35b-coding` gets a GGUF coding build or is removed.
  `3b` and the embedding model get pinned GGUFs.
- `bin/ollama-profiles` renders `ollama/models.ini` (one section per size, an
  embedding section with `embeddings = true` and `pooling = last`, `[*]` from a
  new `ollama/server.ini`) instead of `Modelfile.<size>`. `--check` covers it.
  `check-config` now asserts `ctx-size` equals `CLAUDE_CODE_MAX_CONTEXT_TOKENS`
  and `n-predict` equals the output tokens.
- Weights live in `~/.claude-ollama/weights/` (outside the repo), downloaded at
  the pinned revision and checked against the sha256 in `model-digests.json`,
  then `gguf-inspect`ed. `import_gguf` stops deleting the file.
- The ladder's lower context and a profile's `context` override become extra
  preset sections (`27b@49152`), rendered on demand into
  `~/.claude-ollama/presets/`, since a running model's context cannot change.

### Phase 3: the server as a LaunchAgent

- `go/internal/agent` manages `local.llama-server`: `ProgramArguments` is
  `llama-server --models-preset <rendered file> --port 11435 --log-file ... --metrics`,
  and the editable settings are the `[*]` keys of `ollama/server.ini`
  (`models-max`, `ctx-checkpoints`, `checkpoint-min-step`, `cache-ram`,
  `cache-type-k`/`-v`, `flash-attn`, `parallel`, `sleep-idle-seconds`). `-json`,
  `-set` and `-apply` keep their shapes so the console keeps working.
- `claude-custom install` writes and loads it, `uninstall` removes it, and
  `install` boots out `local.ollama` without touching the user's Ollama models
  (it prints how to remove them).
- Doctor: `ok   llama-server <build> on 127.0.0.1:11435`, a warn below build
  9200, and a fail when a size's preset is missing from `GET /models`.

### Phase 4: the launcher

- Pull and create become download and verify. `refresh_parameters` goes away
  (presets are rendered, not created).
- `warm_model` and `warm_embedding_model` become `model_load`. The lease
  heartbeat and the `heartbeat` ladder rung are removed, since
  `sleep-idle-seconds -1` never unloads an idle model.
- `ollama-lease fit` reads KV metadata through `gguf-inspect`, the KV bytes per
  element from `cache-type-k`, sizes from the files, and resident bytes from
  `GET /models` `memory`. `models_fit` compares against `models-max`.
- `ANTHROPIC_BASE_URL` points at the new port (the proxy still sits in front).
  `CLAUDE_CODE_ATTRIBUTION_HEADER=0` stays and `check-config` keeps asserting
  it.
- `code-search.py` calls `/v1/embeddings` and checks `GET /models` instead of
  `/api/ps`.

### Phase 5: incidents

- Record a real llama-server log from a work-laptop session, cut a fixture
  (`fixtures/server-log.txt`, never `*.log`), and rewrite `CAUSE_RULES` and
  `EVENT_PATTERNS` for it: `reprefilled/full-reprocess` on "forcing full prompt
  re-processing", `evicted/unload` on the router's unload lines,
  `evicted/runner-start` on a model process start, `truncated` on the
  context-overflow line, `expired` on sleep. `--check-rules` must pass the
  fixture and doctor's blind check keeps working.
- `why.py` keeps its verdicts; its `fix:` lines name `server.ini` keys
  (`ctx-checkpoints`, `models-max`) instead of `OLLAMA_*` variables.

### Phase 6: the other tools

- `bin/messages-proxy`: forward `/v1/messages`, `/v1/messages/count_tokens`,
  `/v1/models`, `/health`, `/models` (GET only); drop `/api/*`.
- `bin/ollama-models` becomes a weights manager: `list` (pinned, orphan files),
  `outdated` (pinned revision vs the repo's `main` via the Hugging Face API),
  `prune` (unpinned files), `pin` (writes the file sha256 and revision).
- `bin/model-upgrade`: the candidate is a new revision downloaded beside the
  current one with a `SIZE-next` preset section; promote swaps the pin.
- `bin/speed-check`, `bin/sync-fingerprint` (`server_env` becomes the `[*]`
  settings plus the build), `ollama/rescue.py`, `bin/mock-spike`,
  `bin/messages-bench` defaults, the picker's "Set up embedding model" row.

### Phase 7: the console

- Models page on `GET /models` and the weights manager; Server page edits
  `server.ini` keys through the agent; `/api/server/ping` uses `/health`; the
  residency card reads `memory` from `GET /models`. `console-smoke` covers every
  page.

### Phase 8: remove Ollama

- Delete `ollama/server.env`, the Modelfile template and rendered files, the
  registry code, the `ollama` stubs in every test, and Ollama-only switches
  (`CLAUDE_OLLAMA_LEASE_HEARTBEAT`, the `heartbeat` rung) from
  `shared/profile-env.json`.
- Update `CLAUDE.md`, `docs/ollama.md`, `docs/install.md`,
  `docs/backend-bench.md`; `check-config` fails on any `ollama ` command or
  `/api/` path left in `bin/`, `shared/` or `web/console/src/lib`.
- One `make test` on main, then `claude-custom update` and a relaunch on the
  work laptop, then a `task-eval` run to compare with the Phase 0 numbers.

## Contrarian views and risks

- **MLX may simply be faster on this hardware.** If Phase 0 shows Ollama MLX
  ahead on warm TTFT at 60k, the migration costs speed for control. Neither oMLX
  nor vllm-mlx has been measured yet either (`docs/backend-bench.md` has no
  results), so they are the fallback, not llama.cpp.
- **Hybrid-model caching may regress between builds.** The checkpoint logic has
  changed several times in 2026 and some issues were closed as stale, not fixed.
  Pin the llama.cpp build (a brew formula version or a built tag) the same way
  the weights are pinned, and make `doctor` report it.
- **Anthropic compatibility is best-effort.** The conversion goes through the
  OpenAI path; `thinking` blocks, `cache_control` and stop reasons may differ
  from Ollama's. Phase 0's 5/5 tool calls and `task-eval` catch the visible
  failures.
- **One router process per model** means a model crash is isolated, but the
  router itself is new code (December 2025) and its JSON shapes "can vary
  slightly between builds"; the backend module and its stub test absorb that.
- **The work laptop is the only real test bed.** Every number in this plan comes
  from it, and none of the local sessions here reflect it.

## Open questions

1. Does one router serve a chat preset and an embedding preset together, or does
   the embedding model need its own `llama-server --embeddings` on a second
   port?
2. Does `/v1/messages` honour `thinking: {"type": "disabled"}` for Qwen 3.8's
   template, or must a preset set `reasoning = off` (then a profile's
   `thinking: true` needs its own preset section)?
3. Can `POST /models/load` take arguments such as a context size, or are preset
   sections the only way (the plan assumes sections)?
4. Is there a GGUF of the `35b-coding` build worth keeping?
5. Which llama.cpp build to pin, and is Homebrew current enough or does the
   harness build from a tag?

## Sources

- https://huggingface.co/blog/ggml-org/anthropic-messages-api-in-llamacpp —
  launch post for `/v1/messages` (2026-01-19)
- https://github.com/ggml-org/llama.cpp/pull/17570 — the PR that added it
- https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md —
  endpoints, flags and defaults (read in part; router details partly summarised)
- https://huggingface.co/blog/ggml-org/model-management-in-llamacpp — router
  mode and presets (2025-12-11)
- https://glukhov.org/llm-hosting/llama-cpp/unload-llama-cpp-router-models/ —
  `/models` and unload shapes (third party)
- https://github.com/ggml-org/llama.cpp/discussions/30664 — cross-slot prefix
  sharing proposal, no replies (2026-10-16)
- https://github.com/ggml-org/llama.cpp/discussions/13606 — KV cache reuse and
  slot save/restore tutorial
- https://github.com/ggml-org/llama.cpp/pull/16391 — host-RAM prompt cache
  (`--cache-ram`)
- https://github.com/ggml-org/llama.cpp/discussions/30746 — host cache survives
  slot erase (user report)
- https://github.com/ggml-org/llama.cpp/issues/17107 — prompt caching on by
  default
- https://github.com/ggml-org/llama.cpp/issues/20003 — Qwen3.5 plus Claude Code
  full reprocessing (closed)
- https://github.com/ggml-org/llama.cpp/issues/23013 — Qwen3.6-27B checkpoints
  unusable (closed stale)
- https://github.com/ggml-org/llama.cpp/issues/24714 — Qwen3.5-2B full
  reprocessing
- https://github.com/ggml-org/llama.cpp/issues/22384 — proposed hybrid
  checkpoint fix (fork)
- https://zenn.dev/syoyo/articles/188508eb6ab389 — causes and checkpoint flags
  (Japanese, 2026-03-24)
- https://mykolaaleksandrov.dev/posts/2026/06/claude-code-llamacpp-prompt-cache-fix/
  — attribution header plus checkpoint flags (anecdotal)
- https://www.roborhythms.com/stop-claude-code-slowing-local-llm/ — attribution
  header write-up (blog)
- https://www.glukhov.org/llm-performance/benchmarks/comparing-qwen-3-6-mtp-vs-standard/
  — MTP vs standard numbers (RTX 4080)
- https://github.com/ggml-org/llama.cpp/issues/23302 — MTP divergence report,
  withdrawn
- https://mer.vin/2026/05/run-qwen-3-6-mtp-in-llama-cpp-faster-local-inference-with-built-in-speculative-decoding/
  — MTP setup and build requirement
- https://huggingface.co/ggml-org/Qwen3.8-27B-GGUF — official Qwen3.8 27B GGUF
- https://huggingface.co/byteshape/Qwen3.8-27B-GGUF — alternative quants and
  sizes
- https://levelup.gitconnected.com/ollama-mlx-nearly-doubles-llm-speed-on-your-mac-58-to-112-tok-s-and-your-old-models-get-none-of-fd1a9ec531fb
  — Ollama 0.19 MLX switch and numbers
- https://blog.starmorph.com/blog/apple-silicon-llm-inference-optimization-guide
  — MLX prefill caveat
- https://aitopics.org/doc/arxivorg:43577C43 — academic Apple Silicon runtime
  comparison
- https://bestllmfor.com/guide/mac-m4-max-llm-local-mlx/ — M4 Max figures (low
  quality)
- https://insiderllm.com/pdfs/qwen35-mac-mlx-vs-ollama.pdf — MLX vs Ollama
  claims (vendor-style)

## Rerun inputs

workflow: firecrawl-deep-research topic: migrating the claude-ollama work
harness from Ollama to llama.cpp llama-server depth: thorough output: markdown
