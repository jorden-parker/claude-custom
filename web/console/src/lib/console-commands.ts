import fs from "node:fs";
import { configuredSizes } from "./sizes";

export type CommandParams = Record<string, string>;

export type ConsoleCommand = {
  name: string;
  label: (params: CommandParams) => string;
  argv: (params: CommandParams, repoDir: string) => string[] | null;
  cwd?: () => string | undefined;
};

const PR_NUMBER_PATTERN = /^[1-9][0-9]{0,6}$/;

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

function projectDirectory(): string | undefined {
  const dir = process.env.CONSOLE_PROJECT_DIR;
  return dir && fs.existsSync(dir) && fs.statSync(dir).isDirectory() ? dir : undefined;
}

const review: ConsoleCommand = {
  name: "review",
  label: (params) => `Review PR ${params.pr} (${params.size})`,
  argv: (params, repoDir) => {
    const onlySizeAndPr = Object.keys(params).every((key) => key === "size" || key === "pr");
    const validPr = PR_NUMBER_PATTERN.test(params.pr ?? "");
    if (!onlySizeAndPr || !validPr || !configuredSizes(repoDir).includes(params.size) || !projectDirectory()) {
      return null;
    }
    return [`${repoDir}/bin/claude-ollama`, "review", params.size, params.pr];
  },
  cwd: projectDirectory,
};

export const CONSOLE_COMMANDS: readonly ConsoleCommand[] = [doctor, review];

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
