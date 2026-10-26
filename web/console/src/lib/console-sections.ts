export type ConsoleSection = {
  href: string;
  title: string;
  summary: string;
};

export const CONSOLE_SECTIONS: readonly ConsoleSection[] = [
  { href: "/reviews", title: "Reviews", summary: "Live and past PR reviews" },
  { href: "/runs", title: "Runs", summary: "Every job the console started, live and past" },
  { href: "/health", title: "Health", summary: "Doctor checks and resolved settings per size" },
  { href: "/logs", title: "Logs", summary: "Ollama server log, live" },
  { href: "/server", title: "Server", summary: "Ollama server settings and reload" },
  { href: "/speed-check", title: "Speed check", summary: "MLX vs GGUF verdicts, live and past" },
  { href: "/tools", title: "Tools", summary: "Allow, ask or deny each tool in your user settings" },
  { href: "/benchmarks", title: "Benchmarks", summary: "Benches, bench-off report and tool telemetry" },
];
