import { configuredSizes } from "./sizes";
import { validServerValue } from "./server-vars";

export type CommandParams = Record<string, string>;

export type ConsoleCommand = {
  name: string;
  label: (params: CommandParams) => string;
  argv: (params: CommandParams, repoDir: string) => string[] | null;
};

type Assignment = { name: string; value: string };

const MAX_ASSIGNMENTS = 8;

const doctor: ConsoleCommand = {
  name: "doctor",
  label: (params) => `Doctor (${params.size})`,
  argv: (params, repoDir) => {
    const onlySize = Object.keys(params).every((key) => key === "size");
    if (!onlySize || !configuredSizes(repoDir).includes(params.size)) {
      return null;
    }
    return [`${repoDir}/bin/claude-ollama`, "doctor", params.size];
  },
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

export const CONSOLE_COMMANDS: readonly ConsoleCommand[] = [doctor, serverSet, serverApply, speedCheck];

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
