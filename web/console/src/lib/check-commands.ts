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
    description:
      "Weights, context sizes, hooks, the model server and its settings for one size.",
    needsSize: true,
  },
  {
    command: "thinking-check",
    title: "Thinking check",
    description:
      "Confirms thinking is off on the chat presets. Loads them first, so it can take a while.",
    needsSize: false,
  },
  {
    command: "config-check",
    title: "Config check",
    description:
      "Static checks that the ollama/ and personal/ files agree with each other.",
    needsSize: false,
  },
  {
    command: "models-outdated",
    title: "Outdated models",
    description:
      "Compares each size's pinned GGUF revision with Hugging Face: current or behind.",
    needsSize: false,
  },
  {
    command: "qwen-doctor",
    title: "Qwen doctor",
    description:
      "The same checks for the Qwen Code harness and its sandbox, for one size.",
    needsSize: true,
  },
];
