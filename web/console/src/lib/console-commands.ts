import { BENCH_OFF_MODELS, BENCH_OFF_SERVERS, PREFIX_TOKENS, THINKING_MODES } from "./bench-choices";
import { configuredSizes } from "./sizes";
import { modelForSize } from "./size-models";

export type CommandParams = Record<string, string>;

export type ConsoleCommand = {
  name: string;
  label: (params: CommandParams) => string;
  argv: (params: CommandParams, repoDir: string) => string[] | null;
};

function hasOnlyKeys(params: CommandParams, keys: readonly string[]): boolean {
  const given = Object.keys(params);
  return given.length === keys.length && keys.every((key) => given.includes(key));
}

function isChoice(choices: readonly string[], value: string): boolean {
  return choices.includes(value);
}

function isConfiguredSizeOnly(params: CommandParams, repoDir: string): boolean {
  return hasOnlyKeys(params, ["size"]) && configuredSizes(repoDir).includes(params.size);
}

function configuredModel(params: CommandParams, repoDir: string): string | null {
  return configuredSizes(repoDir).includes(params.size) ? modelForSize(repoDir, params.size) : null;
}

const doctor: ConsoleCommand = {
  name: "doctor",
  label: (params) => `Doctor (${params.size})`,
  argv: (params, repoDir) => {
    if (!isConfiguredSizeOnly(params, repoDir)) {
      return null;
    }
    return [`${repoDir}/bin/claude-ollama`, "doctor", params.size];
  },
};

const messagesBench: ConsoleCommand = {
  name: "messages-bench",
  label: (params) => `Messages bench ${params.size} (${params.thinking}, ${params.prefix})`,
  argv: (params, repoDir) => {
    const model = configuredModel(params, repoDir);
    if (
      !hasOnlyKeys(params, ["size", "thinking", "prefix"]) ||
      model === null ||
      !isChoice(THINKING_MODES, params.thinking) ||
      !isChoice(PREFIX_TOKENS, params.prefix)
    ) {
      return null;
    }
    return [
      `${repoDir}/bin/messages-bench`,
      "--model",
      model,
      "--thinking",
      params.thinking,
      "--prefix-tokens",
      params.prefix,
    ];
  },
};

const cacheProbe: ConsoleCommand = {
  name: "cache-probe",
  label: (params) => `Cache probe (${params.size})`,
  argv: (params, repoDir) => {
    if (!isConfiguredSizeOnly(params, repoDir)) {
      return null;
    }
    return [`${repoDir}/bin/ollama-cache-probe`, params.size];
  },
};

const reviewEval: ConsoleCommand = {
  name: "review-eval",
  label: (params) => `Review eval (${params.size})`,
  argv: (params, repoDir) => {
    const model = configuredModel(params, repoDir);
    if (!hasOnlyKeys(params, ["size"]) || model === null) {
      return null;
    }
    return [`${repoDir}/bin/pr-review-eval`, "--model", model];
  },
};

const benchOffRun: ConsoleCommand = {
  name: "bench-off-run",
  label: (params) => `Bench-off ${params.server} ${params.model}`,
  argv: (params, repoDir) => {
    if (
      !hasOnlyKeys(params, ["server", "model"]) ||
      !isChoice(BENCH_OFF_SERVERS, params.server) ||
      !isChoice(BENCH_OFF_MODELS, params.model)
    ) {
      return null;
    }
    return [`${repoDir}/bin/backend-bench-off`, "run", params.server, params.model];
  },
};

const benchOffReport: ConsoleCommand = {
  name: "bench-off-report",
  label: () => "Bench-off report",
  argv: (params, repoDir) => {
    if (!hasOnlyKeys(params, [])) {
      return null;
    }
    return [`${repoDir}/bin/backend-bench-off`, "report"];
  },
};

export const CONSOLE_COMMANDS: readonly ConsoleCommand[] = [
  doctor,
  messagesBench,
  cacheProbe,
  reviewEval,
  benchOffRun,
  benchOffReport,
];

export function findCommand(name: string): ConsoleCommand | undefined {
  return CONSOLE_COMMANDS.find((command) => command.name === name);
}
