import { TOOL_STATES, type ToolState } from "./tool-states";

export type ProfileKind = "claude-code" | "ollama";

export type ProfileOverride = {
  tools?: Record<string, ToolState>;
  sandbox?: boolean;
  context?: number;
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
] as const;

export const PARAMETER_RANGES: Record<string, ParameterRange> = {
  temperature: { min: 0, max: 2 },
  top_p: { min: 0, max: 1 },
  top_k: { min: 1, max: 500, integer: true },
  min_p: { min: 0, max: 1 },
  repeat_penalty: { min: 0.5, max: 2 },
};
const TOP_LEVEL_KEYS = ["tools", "sandbox", "context", "parameters", "mcp", "env"];
const OLLAMA_ONLY_KEYS = ["context", "parameters", "mcp"];
const ENV_VALUES = ["0", "1"];

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
    ...(parameters && { parameters }),
    ...(mcp && { mcp }),
    ...(env && { env }),
  };
}

export function overrideCount(override: ProfileOverride): number {
  const scalars = [override.sandbox, override.context].filter((value) => value !== undefined).length;
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
    parametersProblem(body.parameters) ??
    mcpProblem(body.mcp) ??
    envProblem(body.env)
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

function envProblem(env: unknown): string | null {
  return recordProblem(env, "env") ?? firstProblem(entriesOf(env), ([name, value]) => envEntryProblem(name, value));
}

function envEntryProblem(name: string, value: unknown): string | null {
  if (!(PROFILE_ENV_KEYS as readonly string[]).includes(name)) {
    return `unknown env key ${name}`;
  }
  return typeof value === "string" && ENV_VALUES.includes(value) ? null : `${name} must be 0 or 1`;
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
