import fs from "node:fs";
import { BENCH_OFF_MODELS, BENCH_OFF_SERVERS, PREFIX_TOKENS, THINKING_MODES } from "./bench-choices";
import { configuredSizes } from "./sizes";
import { modelForSize } from "./size-models";
import { PR_NUMBER_PATTERN } from "./pr-number";
import { validServerValue } from "./server-vars";

export type CommandParams = Record<string, string>;

export type ConsoleCommand = {
  name: string;
  label: (params: CommandParams) => string;
  argv: (params: CommandParams, repoDir: string) => string[] | null;
  cwd?: () => string | undefined;
};

export type ConsoleQuery = {
  argv: (params: CommandParams, repoDir: string) => string[] | null;
};

type Assignment = { name: string; value: string };

const MAX_ASSIGNMENTS = 8;

const NAME_PATTERN = /^[A-Za-z0-9._:/-]{1,128}$/;

const MAX_PRUNE_NAMES = 50;

function isConfiguredSizeOnly(params: CommandParams, repoDir: string): boolean {
  return hasExactKeys(params, ["size"]) && configuredSizes(repoDir).includes(params.size);
}

function isChoice(choices: readonly string[], value: string): boolean {
  return choices.includes(value);
}

function configuredModel(params: CommandParams, repoDir: string): string | null {
  return configuredSizes(repoDir).includes(params.size) ? modelForSize(repoDir, params.size) : null;
}

function sizeArgv(subcommand: string) {
  return (params: CommandParams, repoDir: string): string[] | null => {
    if (!isConfiguredSizeOnly(params, repoDir)) {
      return null;
    }
    return [`${repoDir}/bin/claude-ollama`, subcommand, params.size];
  };
}

const doctor: ConsoleCommand = {
  name: "doctor",
  label: (params) => `Doctor (${params.size})`,
  argv: sizeArgv("doctor"),
};

const prepare: ConsoleCommand = {
  name: "prepare",
  label: (params) => `Prepare ${params.size}`,
  argv: sizeArgv("prepare"),
};

const prepareEmbedding: ConsoleCommand = {
  name: "prepare-embedding",
  label: () => "Set up embedding model",
  argv: (params, repoDir) => (hasExactKeys(params, []) ? [`${repoDir}/bin/claude-ollama`, "prepare-embedding"] : null),
};

function pruneNames(params: CommandParams): string[] | null {
  if (!hasExactKeys(params, ["names"])) {
    return null;
  }
  const names = params.names.split(",");
  const valid =
    names.length <= MAX_PRUNE_NAMES && names.every((name) => NAME_PATTERN.test(name) && !name.startsWith("-"));
  return valid ? names : null;
}

const prune: ConsoleCommand = {
  name: "prune",
  label: (params) => {
    const count = pruneNames(params)?.length ?? 0;
    return `Prune ${count} ${count === 1 ? "model" : "models"}`;
  },
  argv: (params, repoDir) => {
    const names = pruneNames(params);
    if (names === null) {
      return null;
    }
    return [`${repoDir}/bin/ollama-models`, "prune", "--yes", "--only", ...names];
  },
};

function projectDirectory(): string | undefined {
  const dir = process.env.CONSOLE_PROJECT_DIR;
  return dir && fs.existsSync(dir) && fs.statSync(dir).isDirectory() ? dir : undefined;
}

const review: ConsoleCommand = {
  name: "review",
  label: (params) => `Review PR ${params.pr} (${params.size})`,
  argv: (params, repoDir) => {
    const validPr = PR_NUMBER_PATTERN.test(params.pr ?? "");
    if (
      !hasExactKeys(params, ["size", "pr"]) ||
      !validPr ||
      !configuredSizes(repoDir).includes(params.size) ||
      !projectDirectory()
    ) {
      return null;
    }
    return [`${repoDir}/bin/claude-ollama`, "review", params.size, params.pr];
  },
  cwd: projectDirectory,
};

const serverSet: ConsoleCommand = {
  name: "server-set",
  label: (params) => `Set ${params.assignments.split(",").join(", ")}`,
  argv: (params, repoDir) => {
    const assignments = hasExactKeys(params, ["assignments"]) ? parseAssignments(params.assignments) : null;
    if (assignments === null) {
      return null;
    }
    return [ollamaAgentPath(repoDir), ...assignments.flatMap(({ name, value }) => ["-set", `${name}=${value}`])];
  },
};

const serverApply: ConsoleCommand = {
  name: "server-apply",
  label: () => "Apply server.env",
  argv: (params, repoDir) => (hasExactKeys(params, []) ? [ollamaAgentPath(repoDir), "-apply"] : null),
};

const speedCheck: ConsoleCommand = {
  name: "speed-check",
  label: () => "Speed check",
  argv: (params, repoDir) => (hasExactKeys(params, []) ? [`${repoDir}/bin/claude-ollama`, "speed-check"] : null),
};

export const CONSOLE_QUERIES = {
  printConfig: {
    argv: (params, repoDir) => {
      if (!isConfiguredSizeOnly(params, repoDir)) {
        return null;
      }
      return [`${repoDir}/bin/claude-ollama`, "--print-config", params.size];
    },
  },
  logPath: {
    argv: (params, repoDir) => {
      if (Object.keys(params).length > 0) {
        return null;
      }
      return [`${repoDir}/bin/claude-ollama`, "logs", "--path"];
    },
  },
} satisfies Record<string, ConsoleQuery>;

const ASSIGNMENT_LIMIT = 40;
const ASSIGNMENT_PATTERN = /^[A-Za-z][A-Za-z0-9]{0,63}=(default|deny|(allow|ask)(,off)?)$/;

const toolsSet: ConsoleCommand = {
  name: "tools-set",
  label: (params) => `Tool permissions (${assignmentsOf(params.assignments)?.length ?? 0} changes)`,
  argv: (params, repoDir) => {
    const assignments = hasExactKeys(params, ["assignments"]) ? assignmentsOf(params.assignments) : null;
    if (assignments === null) {
      return null;
    }
    const setFlags = assignments.flatMap((assignment) => ["-set", assignment]);
    return [`${repoDir}/bin/claude-tools`, ...setFlags, ...toolsSettingsScope()];
  },
};

const messagesBench: ConsoleCommand = {
  name: "messages-bench",
  label: (params) => `Messages bench ${params.size} (${params.thinking}, ${params.prefix})`,
  argv: (params, repoDir) => {
    const model = configuredModel(params, repoDir);
    if (
      !hasExactKeys(params, ["size", "thinking", "prefix"]) ||
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
    if (!hasExactKeys(params, ["size"]) || model === null) {
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
      !hasExactKeys(params, ["server", "model"]) ||
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
    if (!hasExactKeys(params, [])) {
      return null;
    }
    return [`${repoDir}/bin/backend-bench-off`, "report"];
  },
};

export const CONSOLE_COMMANDS: readonly ConsoleCommand[] = [
  doctor,
  prepare,
  prepareEmbedding,
  prune,
  review,
  serverSet,
  serverApply,
  speedCheck,
  toolsSet,
  messagesBench,
  cacheProbe,
  reviewEval,
  benchOffRun,
  benchOffReport,
];

export function toolsReportArgv(repoDir: string): string[] {
  return [`${repoDir}/bin/claude-tools`, "-json", ...toolsSettingsScope()];
}

function toolsSettingsScope(): string[] {
  const override = process.env.CONSOLE_TOOLS_SETTINGS;
  return override ? ["-settings", override] : ["user"];
}

function assignmentsOf(text: string | undefined): string[] | null {
  if (text === undefined) {
    return null;
  }
  const items = text.split(";");
  const valid = items.length <= ASSIGNMENT_LIMIT && items.every((item) => ASSIGNMENT_PATTERN.test(item));
  return valid ? items : null;
}

export function findCommand(name: string): ConsoleCommand | undefined {
  return CONSOLE_COMMANDS.find((command) => command.name === name);
}

function ollamaAgentPath(repoDir: string): string {
  return `${repoDir}/bin/ollama-agent`;
}

function hasExactKeys(params: CommandParams, keys: readonly string[]): boolean {
  const names = Object.keys(params);
  return names.length === keys.length && keys.every((key) => names.includes(key));
}

function parseAssignments(text: string): Assignment[] | null {
  const parts = text.split(",");
  if (parts.length > MAX_ASSIGNMENTS) {
    return null;
  }
  const assignments = parts.map(splitAssignment).filter((item): item is Assignment => item !== null);
  if (assignments.length !== parts.length || new Set(assignments.map(({ name }) => name)).size !== parts.length) {
    return null;
  }
  return assignments.every(({ name, value }) => validServerValue(name, value)) ? assignments : null;
}

function splitAssignment(part: string): Assignment | null {
  const equals = part.indexOf("=");
  if (equals < 0) {
    return null;
  }
  return { name: part.slice(0, equals), value: part.slice(equals + 1) };
}
