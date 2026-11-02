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
    title: "Checks",
    summary: "Doctor, thinking, config, outdated-model and Qwen checks",
  },
  { href: "/logs", title: "Logs", summary: "Ollama server log, live" },
  {
    href: "/diagnose",
    title: "Diagnose",
    summary: "Why the last run went wrong, rescue report, rule cards, recipes",
  },
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
    title: "Global tools",
    summary: "~/.claude/settings.json, every session",
  },
  {
    href: "/profiles",
    title: "Profiles",
    summary: "Per-profile tools, sandbox, model, MCP servers and env",
  },
  {
    href: "/settings",
    title: "Settings",
    summary: "Every harness switch, its default and each profile's value",
  },
  {
    href: "/benchmarks",
    title: "Benchmarks",
    summary: "Benches, bench-off report and tool telemetry",
  },
  {
    href: "/mockups",
    title: "Mockups",
    summary: "Rendered json-render specs from the latest mock-spike",
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
    summary:
      "gh repos, command rules, enabled tools and sandbox-off on this machine",
  },
  {
    href: "/workspaces",
    title: "Workspaces",
    summary:
      "Folders claude-ollama trusts, and the project skills each one offers",
  },
  {
    href: "/history",
    title: "History",
    summary: "Every settings change, with diffs and restore",
  },
];
