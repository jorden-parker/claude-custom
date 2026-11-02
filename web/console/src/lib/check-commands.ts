export type CheckCommand = {
  command: string;
  title: string;
  description: string;
  needsSize: boolean;
};

export const CHECK_COMMANDS: readonly CheckCommand[] = [
  {
    command: "doctor",
    title: "Doctor",
    description: "Models, context sizes, hooks, Ollama and the server env for one size.",
    needsSize: true,
  },
  {
    command: "thinking-check",
    title: "Thinking check",
    description: "Confirms thinking is off on the MLX sizes. Pulls them first, so it can take a while.",
    needsSize: false,
  },
  {
    command: "config-check",
    title: "Config check",
    description: "Static checks that the ollama/ and personal/ files agree with each other.",
    needsSize: false,
  },
  {
    command: "models-outdated",
    title: "Outdated models",
    description: "Compares each pinned model with the registry: current, behind or unpinned.",
    needsSize: false,
  },
  {
    command: "qwen-doctor",
    title: "Qwen doctor",
    description: "The same checks for the Qwen Code harness and its sandbox, for one size.",
    needsSize: true,
  },
];
