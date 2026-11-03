import causeLevels from "./incident-causes.generated.json";
import type { LogFrame, LogLevel } from "./log-line";

export type IncidentCause = keyof typeof causeLevels;

const causeLevel = causeLevels as Record<IncidentCause, LogLevel>;

export const INCIDENT_CAUSES = Object.keys(causeLevel) as IncidentCause[];

export type IncidentEvent = {
  kind: string;
  ts: string;
};

export type Incident = {
  ts: string;
  cause: IncidentCause;
  detail: string;
  tokens: number | null;
  rule?: string;
  precededBy?: IncidentEvent;
};

export type ClassifierHealth = {
  ts: string;
  rules: Record<string, number>;
  unmatched: number;
  lines: number;
};

function isCause(value: unknown): value is IncidentCause {
  return INCIDENT_CAUSES.some((cause) => cause === value);
}

function parseRow(line: string): Record<string, unknown> | null {
  let parsed: unknown;
  try {
    parsed = JSON.parse(line);
  } catch {
    return null;
  }
  if (typeof parsed !== "object" || parsed === null) {
    return null;
  }
  return parsed as Record<string, unknown>;
}

function parseEvent(value: unknown): IncidentEvent | undefined {
  if (typeof value !== "object" || value === null) {
    return undefined;
  }
  const { kind, ts } = value as Record<string, unknown>;
  return typeof kind === "string" && typeof ts === "string"
    ? { kind, ts }
    : undefined;
}

export function parseIncident(line: string): Incident | null {
  const row = parseRow(line);
  if (row === null || row.kind !== undefined) {
    return null;
  }
  const { ts, cause, detail, tokens, rule, preceded_by } = row;
  if (typeof ts !== "string" || typeof detail !== "string") {
    return null;
  }
  const precededBy = parseEvent(preceded_by);
  return {
    ts,
    cause: isCause(cause) ? cause : "unknown",
    detail,
    tokens: typeof tokens === "number" ? tokens : null,
    ...(typeof rule === "string" ? { rule } : {}),
    ...(precededBy === undefined ? {} : { precededBy }),
  };
}

function isCountTable(value: unknown): value is Record<string, number> {
  return (
    typeof value === "object" &&
    value !== null &&
    Object.values(value).every((count) => typeof count === "number")
  );
}

export function parseHealth(line: string): ClassifierHealth | null {
  const row = parseRow(line);
  if (row === null || row.kind !== "health") {
    return null;
  }
  const { ts, rules, unmatched, lines } = row;
  if (
    typeof ts !== "string" ||
    !isCountTable(rules) ||
    typeof unmatched !== "number" ||
    typeof lines !== "number"
  ) {
    return null;
  }
  return { ts, rules, unmatched, lines };
}

export function latestHealth(lines: string[]): ClassifierHealth | null {
  for (let index = lines.length - 1; index >= 0; index -= 1) {
    const health = parseHealth(lines[index]);
    if (health !== null) {
      return health;
    }
  }
  return null;
}

export function healthSummary(health: ClassifierHealth | null): string {
  if (health === null) {
    return "no health row yet";
  }
  return `saw ${health.lines} lines, ${health.unmatched} unmatched`;
}

export function incidentCounts(
  incidents: Incident[],
): Record<IncidentCause, number> {
  const counts = Object.fromEntries(
    INCIDENT_CAUSES.map((cause) => [cause, 0]),
  ) as Record<IncidentCause, number>;
  for (const incident of incidents) {
    counts[incident.cause] += 1;
  }
  return counts;
}

function clockOf(ts: string): string {
  const moment = new Date(ts);
  if (Number.isNaN(moment.getTime())) {
    return ts;
  }
  return moment.toTimeString().slice(0, 8);
}

function tokensOf(tokens: number | null): string {
  return tokens === null ? "" : ` (${Math.round(tokens / 1000)}k tokens)`;
}

function labelOf(incident: Incident): string {
  const parts: string[] = [incident.cause];
  if (incident.precededBy !== undefined) {
    parts.push(`after ${incident.precededBy.kind}`);
  }
  if (incident.rule !== undefined) {
    parts.push(incident.rule);
  }
  return parts.join(" · ").padEnd(11);
}

export function incidentFrame(incident: Incident): LogFrame {
  return {
    text: `${clockOf(incident.ts)} ${labelOf(incident)} ${incident.detail}${tokensOf(incident.tokens)}`,
    level: causeLevel[incident.cause],
  };
}
