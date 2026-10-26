import { configuredSizes } from "./sizes";

export type CommandParams = Record<string, string>;

export type ConsoleCommand = {
  name: string;
  label: (params: CommandParams) => string;
  argv: (params: CommandParams, repoDir: string) => string[] | null;
};

const NAME_PATTERN = /^[A-Za-z0-9._:/-]{1,128}$/;
const MAX_PRUNE_NAMES = 50;

function hasExactly(params: CommandParams, keys: readonly string[]): boolean {
  const given = Object.keys(params);
  return given.length === keys.length && keys.every((key) => given.includes(key));
}

function sizeArgv(subcommand: string) {
  return (params: CommandParams, repoDir: string): string[] | null => {
    if (!hasExactly(params, ["size"]) || !configuredSizes(repoDir).includes(params.size)) {
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

function pruneNames(params: CommandParams): string[] | null {
  if (!hasExactly(params, ["names"])) {
    return null;
  }
  const names = params.names.split(",");
  const valid = names.length <= MAX_PRUNE_NAMES && names.every((name) => NAME_PATTERN.test(name) && !name.startsWith("-"));
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

export const CONSOLE_COMMANDS: readonly ConsoleCommand[] = [doctor, prepare, prune];

export function findCommand(name: string): ConsoleCommand | undefined {
  return CONSOLE_COMMANDS.find((command) => command.name === name);
}
