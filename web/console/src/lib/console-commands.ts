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

export const CONSOLE_COMMANDS: readonly ConsoleCommand[] = [doctor];

export function findCommand(name: string): ConsoleCommand | undefined {
  return CONSOLE_COMMANDS.find((command) => command.name === name);
}
