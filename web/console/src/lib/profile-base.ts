import fs from "node:fs";
import path from "node:path";
import { CONTEXT_CAP, OLLAMA_MCP_SERVERS, type ProfileOverride, type ProfileRules } from "./profile-rules";
import { profileKind, sizeOfProfile, type ProfileSummary } from "./profiles";
import { sizeSettings } from "./size-models";
import { consoleRepoDir } from "./sizes";
import { runOnce } from "./run-once";
import type { ToolReport, ToolRow } from "./tool-states";

export type HookLine = { event: string; matcher: string; command: string };

export type ProfileBase = {
  settingsPath: string;
  tools: ToolRow[];
  context: number | null;
  parameters: Record<string, number>;
  hooks: HookLine[];
  mcpServers: readonly string[];
};

export type ProfileDetail = ProfileSummary & { override: ProfileOverride; base: ProfileBase };

export type BaseLoad = { ok: true; base: ProfileBase } | { ok: false; message: string };

const TOOLS_TIMEOUT_MS = 60_000;
const TOOLS_MAX_BYTES = 5_000_000;
const DEFAULT_MATCHER = "*";

export function settingsPathFor(repoDir: string, id: string): string {
  const size = sizeOfProfile(id);
  return size === null
    ? path.join(repoDir, "personal", "settings.tokens.json")
    : path.join(repoDir, "ollama", `settings.${size}.json`);
}

export function profileRules(id: string, base: ProfileBase): ProfileRules {
  return {
    kind: profileKind(id),
    toolNames: base.tools.map((tool) => tool.name),
    contextMaximum: CONTEXT_CAP,
  };
}

export async function loadProfileBase(id: string): Promise<BaseLoad> {
  const repoDir = consoleRepoDir();
  const settingsPath = settingsPathFor(repoDir, id);
  const report = await toolsReport(repoDir, settingsPath);
  if (!report.ok) {
    return report;
  }
  const size = sizeOfProfile(id);
  const sizing = size === null ? null : sizeSettings(repoDir, size);
  return {
    ok: true,
    base: {
      settingsPath,
      tools: report.tools,
      context: sizing?.context ?? null,
      parameters: sizing?.parameters ?? {},
      hooks: hookLines(readJsonFile(settingsPath)),
      mcpServers: size === null ? [] : OLLAMA_MCP_SERVERS,
    },
  };
}

async function toolsReport(
  repoDir: string,
  settingsPath: string,
): Promise<{ ok: true; tools: ToolRow[] } | { ok: false; message: string }> {
  const result = await runOnce([`${repoDir}/bin/claude-tools`, "-json", "-settings", settingsPath], {
    timeoutMs: TOOLS_TIMEOUT_MS,
    maxBytes: TOOLS_MAX_BYTES,
  });
  if (result.code !== 0) {
    return { ok: false, message: result.stderr.trim() || "claude-tools failed" };
  }
  return parseReport(result.stdout);
}

function parseReport(stdout: string): { ok: true; tools: ToolRow[] } | { ok: false; message: string } {
  try {
    return { ok: true, tools: (JSON.parse(stdout) as ToolReport).tools };
  } catch {
    return { ok: false, message: "claude-tools printed no report" };
  }
}

export function hookLines(settings: unknown): HookLine[] {
  const hooks = isRecord(settings) && isRecord(settings.hooks) ? settings.hooks : {};
  return Object.entries(hooks).flatMap(([event, groups]) => groupLines(event, groups));
}

function groupLines(event: string, groups: unknown): HookLine[] {
  if (!Array.isArray(groups)) {
    return [];
  }
  return groups.flatMap((group) => {
    if (!isRecord(group) || !Array.isArray(group.hooks)) {
      return [];
    }
    const matcher = typeof group.matcher === "string" ? group.matcher : DEFAULT_MATCHER;
    return group.hooks.flatMap((hook) => commandLine(event, matcher, hook));
  });
}

function commandLine(event: string, matcher: string, hook: unknown): HookLine[] {
  if (!isRecord(hook) || typeof hook.command !== "string") {
    return [];
  }
  return [{ event, matcher, command: scriptName(hook.command) }];
}

function scriptName(command: string): string {
  const lastArgument = command.trim().split(/\s+/).pop() ?? command;
  return lastArgument.split("/").pop() ?? lastArgument;
}

function readJsonFile(target: string): unknown {
  try {
    return JSON.parse(fs.readFileSync(target, "utf8"));
  } catch {
    return null;
  }
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
