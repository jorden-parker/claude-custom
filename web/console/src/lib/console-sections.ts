export const CONSOLE_SECTION_GROUPS = ["Work", "Observe", "Configure"] as const;

export type ConsoleSectionGroup = (typeof CONSOLE_SECTION_GROUPS)[number];

export type ConsoleSection = {
  href: string;
  title: string;
  summary: string;
  group: ConsoleSectionGroup;
};

export const CONSOLE_SECTIONS: readonly ConsoleSection[] = [
  {
    href: "/reviews",
    title: "Reviews",
    summary: "Live and past PR reviews",
    group: "Work",
  },
  {
    href: "/drafts",
    title: "Drafts",
    summary: "PR and review drafts to edit and post to GitHub",
    group: "Work",
  },
  {
    href: "/runs",
    title: "Runs",
    summary: "Every job the console started, live and past",
    group: "Work",
  },
  {
    href: "/mockups",
    title: "Mockups",
    summary: "Rendered json-render specs from the latest mock-spike",
    group: "Work",
  },
  {
    href: "/health",
    title: "Checks",
    summary: "Doctor, thinking, config, outdated-model and Qwen checks",
    group: "Observe",
  },
  {
    href: "/logs",
    title: "Logs",
    summary: "Model server log, live",
    group: "Observe",
  },
  {
    href: "/diagnose",
    title: "Diagnose",
    summary: "Why the last run went wrong, rescue report, rule cards, recipes",
    group: "Observe",
  },
  {
    href: "/speed-check",
    title: "Speed check",
    summary: "MLX vs GGUF verdicts, live and past",
    group: "Observe",
  },
  {
    href: "/benchmarks",
    title: "Benchmarks",
    summary: "Benches, bench-off report and tool telemetry",
    group: "Observe",
  },
  {
    href: "/server",
    title: "Server",
    summary: "Model server settings and reload",
    group: "Configure",
  },
  {
    href: "/models",
    title: "Models",
    summary: "Sizes, installed models, prepare and prune",
    group: "Configure",
  },
  {
    href: "/tools",
    title: "Global tools",
    summary: "~/.claude/settings.json, every session",
    group: "Configure",
  },
  {
    href: "/profiles",
    title: "Profiles",
    summary: "Per-profile tools, sandbox, model, MCP servers and env",
    group: "Configure",
  },
  {
    href: "/settings",
    title: "Settings",
    summary: "Every harness switch, its default and each profile's value",
    group: "Configure",
  },
  {
    href: "/fetch-domains",
    title: "Fetch domains",
    summary: "Hosts claude-ollama sessions may fetch",
    group: "Configure",
  },
  {
    href: "/machine",
    title: "Machine policy",
    summary:
      "gh repos, command rules, enabled tools and sandbox-off on this machine",
    group: "Configure",
  },
  {
    href: "/workspaces",
    title: "Workspaces",
    summary:
      "Folders claude-ollama trusts, and the project skills each one offers",
    group: "Configure",
  },
  {
    href: "/history",
    title: "History",
    summary: "Every settings change, with diffs and restore",
    group: "Configure",
  },
];

export function sectionsInGroup(
  group: ConsoleSectionGroup,
): readonly ConsoleSection[] {
  return CONSOLE_SECTIONS.filter((section) => section.group === group);
}

export function sectionSummaryForTitle(title: string): string | undefined {
  return CONSOLE_SECTIONS.find((section) => section.title === title)?.summary;
}
