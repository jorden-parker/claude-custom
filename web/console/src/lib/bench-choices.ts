export const THINKING_MODES = ["omit", "claude-code", "disabled"] as const;

export const PREFIX_TOKENS = ["2000", "20000", "60000"] as const;

export const BENCH_OFF_SERVERS = [
  "ollama",
  "ollama-mtp",
  "omlx",
  "omlx-mtp",
  "vllm-mlx",
  "vllm-mlx-mtp",
  "vllm-metal",
  "llama-server",
  "llama-server-q8kv",
  "llama-server-mtp",
  "llama-server-ngram",
  "llama-server-src",
  "lmstudio-mlx",
  "mtplx",
  "mtplx-nomtp",
  "rapid-mlx",
  "rapid-mlx-nomtp",
  "optiq",
  "optiq-mtp",
  "optiq-ngram",
  "mistralrs",
] as const;

export const BENCH_OFF_MODELS = ["qwen3.6-35b", "qwen3.8-27b"] as const;
