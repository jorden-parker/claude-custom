import type { ProfileOverride } from "./profile-rules";
import type { ToolState } from "./tool-states";

export function withToolState(override: ProfileOverride, name: string, state: ToolState): ProfileOverride {
  return { ...override, tools: mapWith(override.tools, name, state === "default" ? null : state) };
}

export function withParameter(override: ProfileOverride, name: string, value: number | null): ProfileOverride {
  return { ...override, parameters: mapWith(override.parameters, name, value) };
}

export function withMcp(override: ProfileOverride, name: string, enabled: boolean | null): ProfileOverride {
  return { ...override, mcp: mapWith(override.mcp, name, enabled) };
}

export function withEnv(override: ProfileOverride, name: string, value: string | null): ProfileOverride {
  return { ...override, env: mapWith(override.env, name, value) };
}

export function withContext(override: ProfileOverride, context: number | null): ProfileOverride {
  return { ...override, context: context ?? undefined };
}

export function withOutputTokens(override: ProfileOverride, outputTokens: number | null): ProfileOverride {
  return { ...override, output_tokens: outputTokens ?? undefined };
}

export function withThinking(override: ProfileOverride, thinking: boolean | null): ProfileOverride {
  return { ...override, thinking: thinking ?? undefined };
}

export function withSandbox(override: ProfileOverride, sandbox: boolean | null): ProfileOverride {
  return { ...override, sandbox: sandbox ?? undefined };
}

function mapWith<Value>(
  map: Record<string, Value> | undefined,
  key: string,
  value: Value | null,
): Record<string, Value> | undefined {
  const next: Record<string, Value> = { ...map };
  if (value === null) {
    delete next[key];
  } else {
    next[key] = value;
  }
  return Object.keys(next).length > 0 ? next : undefined;
}
