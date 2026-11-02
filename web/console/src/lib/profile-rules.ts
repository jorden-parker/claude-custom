import { TOOL_STATES, type ToolState } from "./tool-states";

export type ProfileKind = "claude-code" | "ollama";

export type ProfileOverride = {
  tools?: Record<string, ToolState>;
  sandbox?: boolean;
  context?: number;
  thinking?: boolean;
  parameters?: Record<string, number>;
  mcp?: Record<string, boolean>;
  env?: Record<string, string>;
};

export type ProfileRules = {
  kind: ProfileKind;
  toolNames: readonly string[];
  contextMaximum: number;
};

export type Validation =
  { ok: true; override: ProfileOverride } | { ok: false; message: string };

type ParameterRange = { min: number; max: number; integer?: boolean };

export const CONTEXT_MINIMUM = 4096;
export const CONTEXT_CAP = 262144;
export const OLLAMA_MCP_SERVERS = ["code-search", "repo", "dev"] as const;
export const PROFILE_ENV_KEYS = [
  "CLAUDE_OLLAMA_PROXY",
  "CLAUDE_OLLAMA_RULE_CARDS",
  "CLAUDE_OLLAMA_RELAUNCH",
  "CLAUDE_OLLAMA_HANDOFF_PCT",
  "CLAUDE_OLLAMA_NO_INDEX",
  "CLAUDE_CUSTOM_FRICTION",
  "CLAUDE_OLLAMA_LADDER",
  "CLAUDE_OLLAMA_TEST_AFTER_EDIT",
  "CLAUDE_OLLAMA_LEASE",
  "CLAUDE_OLLAMA_LEASE_HEARTBEAT",
  "CLAUDE_OLLAMA_FIT",
  "CLAUDE_OLLAMA_TELEMETRY",
  "CLAUDE_OLLAMA_INCIDENTS",
  "CLAUDE_OLLAMA_PROXY_RECORD",
  "CLAUDE_OLLAMA_BEACON",
  "CLAUDE_OLLAMA_OPEN_DRAFTS",
  "CLAUDE_OLLAMA_CMUX",
] as const;

type ProfileEnvKey = (typeof PROFILE_ENV_KEYS)[number];

export const PROFILE_ENV_GROUPS = [
  "Prompt and context",
  "Guards",
  "Ollama residency",
  "Diagnostics",
  "Browser",
] as const;

export type ProfileEnvGroup = (typeof PROFILE_ENV_GROUPS)[number];

export type NumberRange = { min: number; max: number; step: number };
export type EnvChoice = { value: string; word: string };

type ProfileEnvFieldBase = {
  key: ProfileEnvKey;
  label: string;
  help: string;
  group: ProfileEnvGroup;
  defaultValue: string;
  ollamaOnly: boolean;
};

export type ProfileEnvField =
  | (ProfileEnvFieldBase & { kind: "switch" })
  | (ProfileEnvFieldBase & { kind: "number"; range: NumberRange })
  | (ProfileEnvFieldBase & { kind: "choice"; choices: readonly EnvChoice[] });

export type GroupedEnvFields = {
  group: ProfileEnvGroup;
  fields: ProfileEnvField[];
};

const HANDOFF_PERCENT_RANGE: NumberRange = { min: 30, max: 85, step: 5 };
export const LEASE_HEARTBEAT_RANGE: NumberRange = {
  min: 30,
  max: 600,
  step: 10,
};

export const TEST_AFTER_EDIT_CHOICES: readonly EnvChoice[] = [
  { value: "0", word: "off" },
  { value: "suggest", word: "suggest" },
  { value: "run", word: "run" },
];

export const PROFILE_ENV_FIELDS: readonly ProfileEnvField[] = [
  {
    key: "CLAUDE_OLLAMA_PROXY",
    label: "Observe prompt drift through the messages proxy",
    help: "A proxy between claude and Ollama logs where each request's prompt diverged from the last one, so a cache miss has a cause.",
    group: "Prompt and context",
    kind: "switch",
    defaultValue: "1",
    ollamaOnly: true,
  },
  {
    key: "CLAUDE_OLLAMA_RULE_CARDS",
    label: "Deliver rule cards just in time",
    help: "A rule reaches the model when the tool call it governs comes up, instead of filling the system prompt up front.",
    group: "Prompt and context",
    kind: "switch",
    defaultValue: "1",
    ollamaOnly: true,
  },
  {
    key: "CLAUDE_OLLAMA_RELAUNCH",
    label: "Hand off before the context fills",
    help: "At the threshold the model saves a /handoff note and a fresh session resumes it; off means Claude Code compacts at 88% instead.",
    group: "Prompt and context",
    kind: "switch",
    defaultValue: "1",
    ollamaOnly: true,
  },
  {
    key: "CLAUDE_OLLAMA_HANDOFF_PCT",
    label: "Hand off at (% of context)",
    help: `A whole percent from ${HANDOFF_PERCENT_RANGE.min} to ${HANDOFF_PERCENT_RANGE.max}; empty keeps 70.`,
    group: "Prompt and context",
    kind: "number",
    range: HANDOFF_PERCENT_RANGE,
    defaultValue: "70",
    ollamaOnly: true,
  },
  {
    key: "CLAUDE_OLLAMA_NO_INDEX",
    label: "Skip the code search index",
    help: "Off indexes the project in the background at launch; on leaves semantic_search ranking by words only.",
    group: "Prompt and context",
    kind: "switch",
    defaultValue: "0",
    ollamaOnly: false,
  },
  {
    key: "CLAUDE_CUSTOM_FRICTION",
    label: "Reset a looping guard after three identical denials",
    help: "The fourth identical denial in a turn replaces the hook's reason with a plan reset, so the model stops retrying the same command.",
    group: "Guards",
    kind: "switch",
    defaultValue: "1",
    ollamaOnly: false,
  },
  {
    key: "CLAUDE_OLLAMA_LADDER",
    label: "Degrade rung by rung on incident evidence",
    help: "Three incidents of one kind fire one rung (embeddings off, a faster heartbeat, a smaller context) instead of the whole session failing at once.",
    group: "Guards",
    kind: "switch",
    defaultValue: "1",
    ollamaOnly: true,
  },
  {
    key: "CLAUDE_OLLAMA_TEST_AFTER_EDIT",
    label: "After each edit: suggest the test, or run it",
    help: "Suggest names the test to run after an edit; run executes it and reports pass or the first failing lines. Run executes repo test code outside the Bash sandbox, so leave it on suggest for repos you do not trust.",
    group: "Guards",
    kind: "choice",
    choices: TEST_AFTER_EDIT_CHOICES,
    defaultValue: "suggest",
    ollamaOnly: true,
  },
  {
    key: "CLAUDE_OLLAMA_LEASE",
    label: "Hold an Ollama residency lease and heartbeat",
    help: "A second session or bench waits instead of evicting this one's model, and a keep-alive request keeps it loaded.",
    group: "Ollama residency",
    kind: "switch",
    defaultValue: "1",
    ollamaOnly: true,
  },
  {
    key: "CLAUDE_OLLAMA_LEASE_HEARTBEAT",
    label: "Seconds between keep-alive heartbeats",
    help: `Whole seconds from ${LEASE_HEARTBEAT_RANGE.min} to ${LEASE_HEARTBEAT_RANGE.max}; empty keeps 120, halved while the ladder asks for a faster one.`,
    group: "Ollama residency",
    kind: "number",
    range: LEASE_HEARTBEAT_RANGE,
    defaultValue: "120",
    ollamaOnly: true,
  },
  {
    key: "CLAUDE_OLLAMA_FIT",
    label: "Check memory fit before launch",
    help: "The launch stops with a reason when the model plus its context will not fit in memory, instead of Ollama swapping mid-session.",
    group: "Ollama residency",
    kind: "switch",
    defaultValue: "1",
    ollamaOnly: true,
  },
  {
    key: "CLAUDE_OLLAMA_TELEMETRY",
    label: "Session telemetry",
    help: "One JSON line per tool call in ~/.claude-ollama/telemetry; never the tool input.",
    group: "Diagnostics",
    kind: "switch",
    defaultValue: "1",
    ollamaOnly: false,
  },
  {
    key: "CLAUDE_OLLAMA_INCIDENTS",
    label: "Record Ollama incidents",
    help: "Logs page, Incidents tab.",
    group: "Diagnostics",
    kind: "switch",
    defaultValue: "1",
    ollamaOnly: true,
  },
  {
    key: "CLAUDE_OLLAMA_PROXY_RECORD",
    label: "Record every request body for replay benches",
    help: "The proxy keeps each full request so a bench can replay the session's prompts; off logs only the drift summary.",
    group: "Diagnostics",
    kind: "switch",
    defaultValue: "0",
    ollamaOnly: true,
  },
  {
    key: "CLAUDE_OLLAMA_BEACON",
    label: "Write a machine beacon at launch",
    help: "A fingerprint of this checkout, models and hooks, so claude-custom sync-check can tell two machines apart.",
    group: "Diagnostics",
    kind: "switch",
    defaultValue: "1",
    ollamaOnly: true,
  },
  {
    key: "CLAUDE_OLLAMA_OPEN_DRAFTS",
    label: "Open drafts in the browser",
    help: "A saved PR or review draft opens on the console's Drafts page.",
    group: "Browser",
    kind: "switch",
    defaultValue: "1",
    ollamaOnly: false,
  },
  {
    key: "CLAUDE_OLLAMA_CMUX",
    label: "cmux browser tools",
    help: "The dev server's page tools drive a cmux browser split when the session runs in a cmux terminal.",
    group: "Browser",
    kind: "switch",
    defaultValue: "1",
    ollamaOnly: false,
  },
];

export function envFieldsByGroup(
  fields: readonly ProfileEnvField[],
): GroupedEnvFields[] {
  return PROFILE_ENV_GROUPS.map((group) => ({
    group,
    fields: fields.filter((field) => field.group === group),
  })).filter(({ fields: grouped }) => grouped.length > 0);
}

export const PARAMETER_RANGES: Record<string, ParameterRange> = {
  temperature: { min: 0, max: 2 },
  top_p: { min: 0, max: 1 },
  top_k: { min: 1, max: 500, integer: true },
  min_p: { min: 0, max: 1 },
  repeat_penalty: { min: 0.5, max: 2 },
};
const TOP_LEVEL_KEYS = [
  "tools",
  "sandbox",
  "context",
  "thinking",
  "parameters",
  "mcp",
  "env",
];
const OLLAMA_ONLY_KEYS = ["context", "thinking", "parameters", "mcp"];
const SWITCH_VALUES = ["0", "1"];

export function validateProfileOverride(
  body: unknown,
  rules: ProfileRules,
): Validation {
  if (!isRecord(body)) {
    return { ok: false, message: "Expected a profile object" };
  }
  const problem = keyProblem(body, rules) ?? sectionProblem(body, rules);
  if (problem !== null) {
    return { ok: false, message: problem };
  }
  return { ok: true, override: normalizeOverride(body as ProfileOverride) };
}

function normalizeOverride(override: ProfileOverride): ProfileOverride {
  const tools = withoutDefaults(override.tools);
  const parameters = nonEmpty(override.parameters);
  const mcp = nonEmpty(override.mcp);
  const env = nonEmpty(override.env);
  return {
    ...(tools && { tools }),
    ...(override.sandbox !== undefined && { sandbox: override.sandbox }),
    ...(override.context !== undefined && { context: override.context }),
    ...(override.thinking !== undefined && { thinking: override.thinking }),
    ...(parameters && { parameters }),
    ...(mcp && { mcp }),
    ...(env && { env }),
  };
}

export function overrideCount(override: ProfileOverride): number {
  const scalars = [
    override.sandbox,
    override.context,
    override.thinking,
  ].filter((value) => value !== undefined).length;
  const maps = [
    override.tools,
    override.parameters,
    override.mcp,
    override.env,
  ];
  return maps.reduce(
    (total, map) => total + Object.keys(map ?? {}).length,
    scalars,
  );
}

function keyProblem(
  body: Record<string, unknown>,
  rules: ProfileRules,
): string | null {
  const unknownKey = Object.keys(body).find(
    (key) => !TOP_LEVEL_KEYS.includes(key),
  );
  if (unknownKey !== undefined) {
    return `unknown key ${unknownKey}`;
  }
  if (rules.kind === "ollama" && Object.hasOwn(body, "sandbox")) {
    return "sandbox is always on for Ollama profiles";
  }
  if (rules.kind === "claude-code") {
    const misplaced = OLLAMA_ONLY_KEYS.find((key) => Object.hasOwn(body, key));
    return misplaced === undefined
      ? null
      : `${misplaced} only applies to Ollama profiles`;
  }
  return null;
}

function sectionProblem(
  body: Record<string, unknown>,
  rules: ProfileRules,
): string | null {
  return (
    toolsProblem(body.tools, rules) ??
    sandboxProblem(body.sandbox) ??
    contextProblem(body.context, rules.contextMaximum) ??
    thinkingProblem(body.thinking) ??
    parametersProblem(body.parameters) ??
    mcpProblem(body.mcp) ??
    envProblem(body.env, rules)
  );
}

function toolsProblem(tools: unknown, rules: ProfileRules): string | null {
  return (
    recordProblem(tools, "tools") ??
    firstProblem(entriesOf(tools), (entry) => toolProblem(entry, rules))
  );
}

function toolProblem(
  [name, state]: [string, unknown],
  rules: ProfileRules,
): string | null {
  if (!rules.toolNames.includes(name)) {
    return `unknown tool ${name}`;
  }
  if (!isToolState(state)) {
    return `${name} must be one of ${TOOL_STATES.join(", ")}`;
  }
  if (!toolStatesFor(rules.kind, name).includes(state)) {
    return "Agent stays off for Ollama profiles";
  }
  return null;
}

const AGENT_STATES_FOR_OLLAMA: readonly ToolState[] = ["default", "off"];

export function toolStatesFor(
  kind: ProfileKind,
  name: string,
): readonly ToolState[] {
  return kind === "ollama" && name === "Agent"
    ? AGENT_STATES_FOR_OLLAMA
    : TOOL_STATES;
}

function sandboxProblem(sandbox: unknown): string | null {
  return sandbox === undefined || typeof sandbox === "boolean"
    ? null
    : "sandbox must be true or false";
}

function thinkingProblem(thinking: unknown): string | null {
  return thinking === undefined || typeof thinking === "boolean"
    ? null
    : "thinking must be true or false";
}

function contextProblem(context: unknown, maximum: number): string | null {
  if (context === undefined || isContextInRange(context, maximum)) {
    return null;
  }
  return `context must be from ${CONTEXT_MINIMUM} to ${maximum}`;
}

function isContextInRange(value: unknown, maximum: number): boolean {
  return (
    typeof value === "number" &&
    Number.isInteger(value) &&
    value >= CONTEXT_MINIMUM &&
    value <= maximum
  );
}

function parametersProblem(parameters: unknown): string | null {
  return (
    recordProblem(parameters, "parameters") ??
    firstProblem(entriesOf(parameters), parameterProblem)
  );
}

function parameterProblem([name, value]: [string, unknown]): string | null {
  if (!Object.hasOwn(PARAMETER_RANGES, name)) {
    return `unknown parameter ${name}`;
  }
  const range = PARAMETER_RANGES[name];
  if (typeof value !== "number" || !Number.isFinite(value)) {
    return `${name} must be a number`;
  }
  if (range.integer && !Number.isInteger(value)) {
    return `${name} must be a whole number`;
  }
  return value < range.min || value > range.max
    ? `${name} must be from ${range.min} to ${range.max}`
    : null;
}

function mcpProblem(mcp: unknown): string | null {
  return (
    recordProblem(mcp, "mcp") ??
    firstProblem(entriesOf(mcp), ([name, enabled]) =>
      mcpEntryProblem(name, enabled),
    )
  );
}

function mcpEntryProblem(name: string, enabled: unknown): string | null {
  if (!(OLLAMA_MCP_SERVERS as readonly string[]).includes(name)) {
    return `unknown MCP server ${name}`;
  }
  return typeof enabled === "boolean" ? null : `${name} must be true or false`;
}

function envProblem(env: unknown, rules: ProfileRules): string | null {
  return (
    recordProblem(env, "env") ??
    firstProblem(entriesOf(env), ([name, value]) =>
      envEntryProblem(name, value, rules),
    )
  );
}

function envEntryProblem(
  name: string,
  value: unknown,
  rules: ProfileRules,
): string | null {
  const field = PROFILE_ENV_FIELDS.find((candidate) => candidate.key === name);
  if (field === undefined) {
    return `unknown env key ${name}`;
  }
  if (field.ollamaOnly && rules.kind === "claude-code") {
    return `${name} only applies to Ollama profiles`;
  }
  if (field.kind === "number") {
    return wholeNumberProblem(name, value, field.range);
  }
  if (field.kind === "choice") {
    return choiceProblem(name, value, field.choices);
  }
  return switchProblem(name, value);
}

function choiceProblem(
  name: string,
  value: unknown,
  choices: readonly EnvChoice[],
): string | null {
  return choices.some((choice) => choice.value === value)
    ? null
    : `${name} must be one of ${choices.map((choice) => choice.value).join(", ")}`;
}

function switchProblem(name: string, value: unknown): string | null {
  return typeof value === "string" && SWITCH_VALUES.includes(value)
    ? null
    : `${name} must be 0 or 1`;
}

function wholeNumberProblem(
  name: string,
  value: unknown,
  { min, max }: NumberRange,
): string | null {
  return isWholeNumberWithin(value, min, max)
    ? null
    : `${name} must be a whole number from ${min} to ${max}`;
}

function isWholeNumberWithin(
  value: unknown,
  min: number,
  max: number,
): boolean {
  if (typeof value !== "string" || !/^\d+$/.test(value)) {
    return false;
  }
  const whole = Number(value);
  return whole >= min && whole <= max;
}

function withoutDefaults(
  tools: Record<string, ToolState> | undefined,
): Record<string, ToolState> | undefined {
  if (tools === undefined) {
    return undefined;
  }
  return nonEmpty(
    Object.fromEntries(
      Object.entries(tools).filter(([, state]) => state !== "default"),
    ),
  );
}

function nonEmpty<T>(
  map: Record<string, T> | undefined,
): Record<string, T> | undefined {
  return map !== undefined && Object.keys(map).length > 0 ? map : undefined;
}

function recordProblem(value: unknown, name: string): string | null {
  return value === undefined || isRecord(value)
    ? null
    : `${name} must be an object`;
}

function entriesOf(value: unknown): [string, unknown][] {
  return value === undefined
    ? []
    : Object.entries(value as Record<string, unknown>);
}

function firstProblem<T>(
  items: readonly T[],
  check: (item: T) => string | null,
): string | null {
  return items.map(check).find((problem) => problem !== null) ?? null;
}

function isToolState(value: unknown): value is ToolState {
  return (
    typeof value === "string" &&
    (TOOL_STATES as readonly string[]).includes(value)
  );
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
