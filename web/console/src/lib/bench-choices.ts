export const THINKING_MODES = ["omit", "claude-code", "disabled"] as const;

export const PREFIX_TOKENS = ["2000", "20000", "60000"] as const;

export const BENCH_OFF_SERVERS = [
  "ollama",
  "ollama-mtp",
  "omlx",
  "omlx-mtp",
  "vllm-mlx",
  "vllm-mlx-mtp",
] as const;

export const BENCH_OFF_MODELS = ["qwen3.6-35b", "qwen3.8-27b"] as const;
