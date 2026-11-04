export type ValueCheck = (value: string) => boolean;

const KEEP_ALIVE_PATTERN = /^(-1|\d{1,6}(ms|s|m|h)?)$/;
const MAX_VALUE_LENGTH = 256;

function integerBetween(low: number, high: number): ValueCheck {
  return (value) => /^\d+$/.test(value) && Number(value) >= low && Number(value) <= high;
}

function oneOf(choices: readonly string[]): ValueCheck {
  return (value) => choices.includes(value);
}

export const EDITABLE_VARIABLES: ReadonlyMap<string, ValueCheck> = new Map<string, ValueCheck>([
  ["OLLAMA_KEEP_ALIVE", (value) => KEEP_ALIVE_PATTERN.test(value)],
  ["OLLAMA_MAX_LOADED_MODELS", integerBetween(1, 16)],
  ["OLLAMA_NUM_PARALLEL", integerBetween(1, 16)],
  ["OLLAMA_MAX_QUEUE", integerBetween(1, 100000)],
  ["OLLAMA_CONTEXT_LENGTH", integerBetween(2048, 262144)],
  ["OLLAMA_FLASH_ATTENTION", oneOf(["0", "1"])],
  ["OLLAMA_DEBUG", oneOf(["0", "1"])],
  ["OLLAMA_KV_CACHE_TYPE", oneOf(["f16", "q8_0", "q4_0"])],
]);

export function validServerValue(name: string, value: string): boolean {
  const check = EDITABLE_VARIABLES.get(name);
  if (check === undefined || value.length > MAX_VALUE_LENGTH || /[,=]/.test(value)) {
    return false;
  }
  return check(value);
}
