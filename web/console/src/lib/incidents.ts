import type { LogFrame, LogLevel } from "./log-line";

export const INCIDENT_CAUSES = [
  "aborted",
  "evicted",
  "truncated",
  "reprefilled",
  "compacted",
  "relaunched",
  "unknown",
] as const;

export type IncidentCause = (typeof INCIDENT_CAUSES)[number];

export type Incident = {
  ts: string;
  cause: IncidentCause;
  detail: string;
  tokens: number | null;
};

const causeLevel: Record<IncidentCause, LogLevel> = {
  aborted: "warn",
  evicted: "error",
  truncated: "error",
  reprefilled: "warn",
  compacted: "info",
  relaunched: "info",
  unknown: "debug",
};

function isCause(value: unknown): value is IncidentCause {
  return INCIDENT_CAUSES.some((cause) => cause === value);
}

export function parseIncident(line: string): Incident | null {
  let parsed: unknown;
  try {
    parsed = JSON.parse(line);
  } catch {
    return null;
  }
  if (typeof parsed !== "object" || parsed === null) {
    return null;
  }
  const { ts, cause, detail, tokens } = parsed as Record<string, unknown>;
  if (typeof ts !== "string" || typeof detail !== "string") {
    return null;
  }
  return {
    ts,
    cause: isCause(cause) ? cause : "unknown",
    detail,
    tokens: typeof tokens === "number" ? tokens : null,
  };
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

export function incidentFrame(incident: Incident): LogFrame {
  return {
    text: `${clockOf(incident.ts)} ${incident.cause.padEnd(11)} ${incident.detail}${tokensOf(incident.tokens)}`,
    level: causeLevel[incident.cause],
  };
}
