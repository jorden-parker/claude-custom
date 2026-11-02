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
  | { ok: true; override: ProfileOverride }
  | { ok: false; message: string };

type ParameterRange = { min: number; max: number; integer?: boolean };

export const CONTEXT_MINIMUM = 4096;
export const CONTEXT_CAP = 262144;
export const OLLAMA_MCP_SERVERS = ["code-search", "repo", "dev"] as const;
export const PROFILE_ENV_KEYS = [
  "CLAUDE_OLLAMA_TELEMETRY",
  "CLAUDE_OLLAMA_NO_INDEX",
  "CLAUDE_OLLAMA_OPEN_DRAFTS",
  "CLAUDE_OLLAMA_CMUX",
  "CLAUDE_OLLAMA_RELAUNCH",
  "CLAUDE_OLLAMA_HANDOFF_PCT",
  "CLAUDE_OLLAMA_INCIDENTS",
] as const;

export type ProfileEnvKey = (typeof PROFILE_ENV_KEYS)[number];

export type ProfileEnvField = {
  key: ProfileEnvKey;
  label: string;
  help: string;
  kind: "switch" | "percent";
  defaultValue: string;
  ollamaOnly: boolean;
};

export const HANDOFF_PERCENT_RANGE = { min: 30, max: 85, step: 5 } as const;

export const PROFILE_ENV_FIELDS: readonly ProfileEnvField[] = [
  {
    key: "CLAUDE_OLLAMA_TELEMETRY",
    label: "Session telemetry",
    help: "One JSON line per tool call in ~/.claude-ollama/telemetry; never the tool input.",
    kind: "switch",
    defaultValue: "1",
    ollamaOnly: false,
  },
  {
    key: "CLAUDE_OLLAMA_NO_INDEX",
    label: "Skip the code search index",
    help: "Off indexes the project in the background at launch; on leaves semantic_search ranking by words only.",
    kind: "switch",
    defaultValue: "0",
    ollamaOnly: false,
  },
  {
    key: "CLAUDE_OLLAMA_OPEN_DRAFTS",
    label: "Open drafts in the browser",
    help: "A saved PR or review draft opens on the console's Drafts page.",
    kind: "switch",
    defaultValue: "1",
    ollamaOnly: false,
  },
  {
    key: "CLAUDE_OLLAMA_CMUX",
    label: "cmux browser tools",
    help: "The dev server's page tools drive a cmux browser split when the session runs in a cmux terminal.",
    kind: "switch",
    defaultValue: "1",
    ollamaOnly: false,
  },
  {
    key: "CLAUDE_OLLAMA_RELAUNCH",
    label: "Hand off before the context fills",
    help: "At the threshold the model saves a /handoff note and a fresh session resumes it; off means Claude Code compacts at 88% instead.",
    kind: "switch",
    defaultValue: "1",
    ollamaOnly: true,
  },
  {
    key: "CLAUDE_OLLAMA_HANDOFF_PCT",
    label: "Hand off at (% of context)",
    help: `A whole percent from ${HANDOFF_PERCENT_RANGE.min} to ${HANDOFF_PERCENT_RANGE.max}; empty keeps 70.`,
    kind: "percent",
    defaultValue: "70",
    ollamaOnly: true,
  },
  {
    key: "CLAUDE_OLLAMA_INCIDENTS",
    label: "Record Ollama incidents",
    help: "Logs page, Incidents tab.",
    kind: "switch",
    defaultValue: "1",
    ollamaOnly: true,
  },
];

export const PARAMETER_RANGES: Record<string, ParameterRange> = {
  temperature: { min: 0, max: 2 },
  top_p: { min: 0, max: 1 },
  top_k: { min: 1, max: 500, integer: true },
  min_p: { min: 0, max: 1 },
  repeat_penalty: { min: 0.5, max: 2 },
};
const TOP_LEVEL_KEYS = ["tools", "sandbox", "context", "thinking", "parameters", "mcp", "env"];
const OLLAMA_ONLY_KEYS = ["context", "thinking", "parameters", "mcp"];
const SWITCH_VALUES = ["0", "1"];

export function validateProfileOverride(body: unknown, rules: ProfileRules): Validation {
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
  const scalars = [override.sandbox, override.context, override.thinking].filter((value) => value !== undefined).length;
  const maps = [override.tools, override.parameters, override.mcp, override.env];
  return maps.reduce((total, map) => total + Object.keys(map ?? {}).length, scalars);
}

function keyProblem(body: Record<string, unknown>, rules: ProfileRules): string | null {
  const unknownKey = Object.keys(body).find((key) => !TOP_LEVEL_KEYS.includes(key));
  if (unknownKey !== undefined) {
    return `unknown key ${unknownKey}`;
  }
  if (rules.kind === "ollama" && Object.hasOwn(body, "sandbox")) {
    return "sandbox is always on for Ollama profiles";
  }
  if (rules.kind === "claude-code") {
    const misplaced = OLLAMA_ONLY_KEYS.find((key) => Object.hasOwn(body, key));
    return misplaced === undefined ? null : `${misplaced} only applies to Ollama profiles`;
  }
  return null;
}

function sectionProblem(body: Record<string, unknown>, rules: ProfileRules): string | null {
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
  return recordProblem(tools, "tools") ?? firstProblem(entriesOf(tools), (entry) => toolProblem(entry, rules));
}

function toolProblem([name, state]: [string, unknown], rules: ProfileRules): string | null {
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

export function toolStatesFor(kind: ProfileKind, name: string): readonly ToolState[] {
  return kind === "ollama" && name === "Agent" ? AGENT_STATES_FOR_OLLAMA : TOOL_STATES;
}

function sandboxProblem(sandbox: unknown): string | null {
  return sandbox === undefined || typeof sandbox === "boolean" ? null : "sandbox must be true or false";
}

function thinkingProblem(thinking: unknown): string | null {
  return thinking === undefined || typeof thinking === "boolean" ? null : "thinking must be true or false";
}

function contextProblem(context: unknown, maximum: number): string | null {
  if (context === undefined || isContextInRange(context, maximum)) {
    return null;
  }
  return `context must be from ${CONTEXT_MINIMUM} to ${maximum}`;
}

function isContextInRange(value: unknown, maximum: number): boolean {
  return typeof value === "number" && Number.isInteger(value) && value >= CONTEXT_MINIMUM && value <= maximum;
}

function parametersProblem(parameters: unknown): string | null {
  return recordProblem(parameters, "parameters") ?? firstProblem(entriesOf(parameters), parameterProblem);
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
  return value < range.min || value > range.max ? `${name} must be from ${range.min} to ${range.max}` : null;
}

function mcpProblem(mcp: unknown): string | null {
  return recordProblem(mcp, "mcp") ?? firstProblem(entriesOf(mcp), ([name, enabled]) => mcpEntryProblem(name, enabled));
}

function mcpEntryProblem(name: string, enabled: unknown): string | null {
  if (!(OLLAMA_MCP_SERVERS as readonly string[]).includes(name)) {
    return `unknown MCP server ${name}`;
  }
  return typeof enabled === "boolean" ? null : `${name} must be true or false`;
}

function envProblem(env: unknown, rules: ProfileRules): string | null {
  return (
    recordProblem(env, "env") ?? firstProblem(entriesOf(env), ([name, value]) => envEntryProblem(name, value, rules))
  );
}

function envEntryProblem(name: string, value: unknown, rules: ProfileRules): string | null {
  const field = PROFILE_ENV_FIELDS.find((candidate) => candidate.key === name);
  if (field === undefined) {
    return `unknown env key ${name}`;
  }
  if (field.ollamaOnly && rules.kind === "claude-code") {
    return `${name} only applies to Ollama profiles`;
  }
  return field.kind === "percent" ? percentProblem(name, value) : switchProblem(name, value);
}

function switchProblem(name: string, value: unknown): string | null {
  return typeof value === "string" && SWITCH_VALUES.includes(value) ? null : `${name} must be 0 or 1`;
}

function percentProblem(name: string, value: unknown): string | null {
  const { min, max } = HANDOFF_PERCENT_RANGE;
  return isWholePercent(value, min, max) ? null : `${name} must be a whole number from ${min} to ${max}`;
}

function isWholePercent(value: unknown, min: number, max: number): boolean {
  if (typeof value !== "string" || !/^\d+$/.test(value)) {
    return false;
  }
  const percent = Number(value);
  return percent >= min && percent <= max;
}

function withoutDefaults(tools: Record<string, ToolState> | undefined): Record<string, ToolState> | undefined {
  if (tools === undefined) {
    return undefined;
  }
  return nonEmpty(Object.fromEntries(Object.entries(tools).filter(([, state]) => state !== "default")));
}

function nonEmpty<T>(map: Record<string, T> | undefined): Record<string, T> | undefined {
  return map !== undefined && Object.keys(map).length > 0 ? map : undefined;
}

function recordProblem(value: unknown, name: string): string | null {
  return value === undefined || isRecord(value) ? null : `${name} must be an object`;
}

function entriesOf(value: unknown): [string, unknown][] {
  return value === undefined ? [] : Object.entries(value as Record<string, unknown>);
}

function firstProblem<T>(items: readonly T[], check: (item: T) => string | null): string | null {
  return items.map(check).find((problem) => problem !== null) ?? null;
}

function isToolState(value: unknown): value is ToolState {
  return typeof value === "string" && (TOOL_STATES as readonly string[]).includes(value);
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
