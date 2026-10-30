export type ConsoleSection = {
  href: string;
  title: string;
  summary: string;
};

export const CONSOLE_SECTIONS: readonly ConsoleSection[] = [
  { href: "/reviews", title: "Reviews", summary: "Live and past PR reviews" },
  {
    href: "/drafts",
    title: "Drafts",
    summary: "PR and review drafts to edit and post to GitHub",
  },
  {
    href: "/runs",
    title: "Runs",
    summary: "Every job the console started, live and past",
  },
  {
    href: "/health",
    title: "Health",
    summary: "Doctor checks and resolved settings per size",
  },
  { href: "/logs", title: "Logs", summary: "Ollama server log, live" },
  {
    href: "/server",
    title: "Server",
    summary: "Ollama server settings and reload",
  },
  {
    href: "/speed-check",
    title: "Speed check",
    summary: "MLX vs GGUF verdicts, live and past",
  },
  {
    href: "/tools",
    title: "Tools",
    summary: "Allow, ask or deny each tool in your user settings",
  },
  {
    href: "/benchmarks",
    title: "Benchmarks",
    summary: "Benches, bench-off report and tool telemetry",
  },
  {
    href: "/models",
    title: "Models",
    summary: "Sizes, installed models, prepare and prune",
  },
  {
    href: "/fetch-domains",
    title: "Fetch domains",
    summary: "Hosts claude-ollama sessions may fetch",
  },
  {
    href: "/machine",
    title: "Machine policy",
    summary: "gh repos, command rules, enabled tools and sandbox-off on this machine",
  },
  {
    href: "/history",
    title: "History",
    summary: "Every settings change, with diffs and restore",
  },
];
