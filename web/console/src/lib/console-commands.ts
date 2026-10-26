import { configuredSizes } from "./sizes";

export type CommandParams = Record<string, string>;

export type ConsoleCommand = {
  name: string;
  label: (params: CommandParams) => string;
  argv: (params: CommandParams, repoDir: string) => string[] | null;
};

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

const ASSIGNMENT_LIMIT = 40;
const ASSIGNMENT_PATTERN = /^[A-Za-z][A-Za-z0-9]{0,63}=(default|deny|(allow|ask)(,off)?)$/;

const toolsSet: ConsoleCommand = {
  name: "tools-set",
  label: (params) => `Tool permissions (${assignmentsOf(params.assignments)?.length ?? 0} changes)`,
  argv: (params, repoDir) => {
    const onlyAssignments = Object.keys(params).every((key) => key === "assignments");
    const assignments = assignmentsOf(params.assignments);
    if (!onlyAssignments || assignments === null) {
      return null;
    }
    const setFlags = assignments.flatMap((assignment) => ["-set", assignment]);
    return [`${repoDir}/bin/claude-tools`, ...setFlags, ...toolsSettingsScope()];
  },
};

export const CONSOLE_COMMANDS: readonly ConsoleCommand[] = [doctor, toolsSet];

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
