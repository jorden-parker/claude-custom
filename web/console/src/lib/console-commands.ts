import { configuredSizes } from "./sizes";

export type CommandParams = Record<string, string>;

export type ConsoleCommand = {
  name: string;
  label: (params: CommandParams) => string;
  argv: (params: CommandParams, repoDir: string) => string[] | null;
};

export type ConsoleQuery = {
  argv: (params: CommandParams, repoDir: string) => string[] | null;
};

function isConfiguredSizeOnly(params: CommandParams, repoDir: string): boolean {
  const onlySize = Object.keys(params).every((key) => key === "size");
  return onlySize && configuredSizes(repoDir).includes(params.size);
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

export const CONSOLE_COMMANDS: readonly ConsoleCommand[] = [doctor];

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

export function findCommand(name: string): ConsoleCommand | undefined {
  return CONSOLE_COMMANDS.find((command) => command.name === name);
}
