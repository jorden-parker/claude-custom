export type ConsoleSection = {
  href: string;
  title: string;
  summary: string;
};

export const CONSOLE_SECTIONS: readonly ConsoleSection[] = [
  { href: "/reviews", title: "Reviews", summary: "Live and past PR reviews" },
  { href: "/runs", title: "Runs", summary: "Every job the console started, live and past" },
  { href: "/server", title: "Server", summary: "Ollama server settings and reload" },
  { href: "/speed-check", title: "Speed check", summary: "MLX vs GGUF verdicts, live and past" },
];
