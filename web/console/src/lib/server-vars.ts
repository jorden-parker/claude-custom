export type SettingInput =
  | { kind: "number"; min: number; max: number }
  | { kind: "choice"; choices: readonly string[] };

export type ServerSetting = { key: string; label: string; help: string; input: SettingInput };

const CACHE_TYPES = ["f16", "q8_0", "q4_0"] as const;
const WHOLE_NUMBER = /^-?(0|[1-9]\d*)$/;
const MAX_VALUE_LENGTH = 16;

function numberBetween(min: number, max: number): SettingInput {
  return { kind: "number", min, max };
}

function choiceOf(choices: readonly string[]): SettingInput {
  return { kind: "choice", choices };
}

export const SERVER_SETTINGS: readonly ServerSetting[] = [
  {
    key: "models-max",
    label: "Models loaded at once",
    help: "How many presets the router keeps loaded; the chat model and the embedding model need 2.",
    input: numberBetween(1, 4),
  },
  {
    key: "ctx-checkpoints",
    label: "Context checkpoints per slot",
    help: "How many prompt checkpoints a slot keeps, so a changed prompt reuses the longest cached prefix.",
    input: numberBetween(0, 256),
  },
  {
    key: "checkpoint-min-step",
    label: "Tokens between checkpoints",
    help: "The fewest prompt tokens between two checkpoints.",
    input: numberBetween(1, 8192),
  },
  {
    key: "cache-ram",
    label: "Prompt cache RAM (MiB)",
    help: "How much RAM the prompt cache may keep across requests, in MiB; 0 turns it off.",
    input: numberBetween(0, 65536),
  },
  {
    key: "cache-type-k",
    label: "K cache type",
    help: "The element type of the attention keys in the KV cache; q8_0 halves their memory.",
    input: choiceOf(CACHE_TYPES),
  },
  {
    key: "cache-type-v",
    label: "V cache type",
    help: "The element type of the attention values in the KV cache; q8_0 halves their memory.",
    input: choiceOf(CACHE_TYPES),
  },
  {
    key: "flash-attn",
    label: "Flash attention",
    help: "Fused attention kernels, which save memory and time on Apple silicon.",
    input: choiceOf(["on", "off", "auto"]),
  },
  {
    key: "parallel",
    label: "Parallel slots",
    help: "How many requests one model serves at once; each slot holds its own context.",
    input: numberBetween(1, 8),
  },
  {
    key: "batch-size",
    label: "Batch size",
    help: "The most prompt tokens sent to the model in one logical batch.",
    input: numberBetween(32, 8192),
  },
  {
    key: "ubatch-size",
    label: "Micro-batch size",
    help: "The most prompt tokens in one physical batch; at most the batch size.",
    input: numberBetween(32, 8192),
  },
  {
    key: "cache-reuse",
    label: "Cache reuse chunk",
    help: "The fewest tokens a shifted chunk of the cache needs to be reused; 0 turns it off.",
    input: numberBetween(0, 4096),
  },
  {
    key: "prio",
    label: "Process priority",
    help: "The scheduling priority of the model processes, from -1 (low) to 3 (realtime).",
    input: numberBetween(-1, 3),
  },
  {
    key: "sleep-idle-seconds",
    label: "Idle seconds before unloading",
    help: "Seconds without a request before a model is unloaded; -1 never unloads it.",
    input: numberBetween(-1, 86400),
  },
];

export function serverSetting(key: string): ServerSetting | undefined {
  return SERVER_SETTINGS.find((setting) => setting.key === key);
}

export function validServerValue(key: string, value: string): boolean {
  const setting = serverSetting(key);
  if (setting === undefined || value.length > MAX_VALUE_LENGTH) {
    return false;
  }
  const { input } = setting;
  if (input.kind === "choice") {
    return input.choices.includes(value);
  }
  return WHOLE_NUMBER.test(value) && Number(value) >= input.min && Number(value) <= input.max;
}
