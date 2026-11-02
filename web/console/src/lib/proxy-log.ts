import type { LogFrame, LogLevel } from "./log-line";

const TOP_SECTIONS = 3;
const PREFIX_SECTIONS = ["system", "tools"] as const;

export type ProxyLedger = {
  system: number;
  tools: Record<string, number>;
  messages: number;
};

export type ProxyRow = {
  ts: string;
  requestId: string;
  sections: number;
  stableSections: number;
  divergedAt: string | null;
  offset: number | null;
  diff: string | null;
  promptBytes: number;
  ledger: ProxyLedger | null;
};

export type PrefixHitRate = {
  stable: number;
  requests: number;
  percent: number;
};

export type DivergingSection = { section: string; count: number };

export type LedgerTool = { name: string; bytes: number; share: number };

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

function isByteTable(value: unknown): value is Record<string, number> {
  return (
    typeof value === "object" &&
    value !== null &&
    Object.values(value).every((bytes) => typeof bytes === "number")
  );
}

function parseLedger(value: unknown): ProxyLedger | null {
  if (typeof value !== "object" || value === null) {
    return null;
  }
  const { system, tools, messages } = value as Record<string, unknown>;
  if (
    typeof system !== "number" ||
    !isByteTable(tools) ||
    typeof messages !== "number"
  ) {
    return null;
  }
  return { system, tools, messages };
}

function numberOrNull(value: unknown): number | null {
  return typeof value === "number" ? value : null;
}

function stringOrNull(value: unknown): string | null {
  return typeof value === "string" ? value : null;
}

export function parseProxyRow(line: string): ProxyRow | null {
  const row = parseRow(line);
  if (row === null) {
    return null;
  }
  const { ts, request_id, sections, stable_sections, prompt_bytes } = row;
  if (
    typeof ts !== "string" ||
    typeof request_id !== "string" ||
    typeof sections !== "number" ||
    typeof stable_sections !== "number" ||
    typeof prompt_bytes !== "number"
  ) {
    return null;
  }
  return {
    ts,
    requestId: request_id,
    sections,
    stableSections: stable_sections,
    divergedAt: stringOrNull(row.diverged_at),
    offset: numberOrNull(row.offset),
    diff: stringOrNull(row.diff),
    promptBytes: prompt_bytes,
    ledger: parseLedger(row.ledger),
  };
}

function afterFirst(rows: ProxyRow[]): ProxyRow[] {
  return rows.filter(
    (row) => row.divergedAt !== null || row.stableSections > 0,
  );
}

function stableThroughTools(row: ProxyRow): boolean {
  return row.divergedAt === null || row.divergedAt.startsWith("message:");
}

export function prefixHitRate(rows: ProxyRow[]): PrefixHitRate {
  const counted = afterFirst(rows);
  const stable = counted.filter(stableThroughTools).length;
  const percent =
    counted.length === 0 ? 0 : Math.round((100 * stable) / counted.length);
  return { stable, requests: counted.length, percent };
}

export function prefixSummary(rate: PrefixHitRate): string {
  return `${rate.percent}% of ${rate.requests} requests stable through tools`;
}

export function averagePromptBytes(rows: ProxyRow[]): number {
  if (rows.length === 0) {
    return 0;
  }
  const total = rows.reduce((sum, row) => sum + row.promptBytes, 0);
  return Math.round(total / rows.length);
}

function sectionRank(section: string): [number, number] {
  const prefixIndex = PREFIX_SECTIONS.findIndex((name) => name === section);
  if (prefixIndex >= 0) {
    return [prefixIndex, 0];
  }
  const index = Number(section.split(":")[1]);
  return [PREFIX_SECTIONS.length, Number.isNaN(index) ? 0 : index];
}

function compareSections(
  left: DivergingSection,
  right: DivergingSection,
): number {
  if (left.count !== right.count) {
    return right.count - left.count;
  }
  const [leftGroup, leftIndex] = sectionRank(left.section);
  const [rightGroup, rightIndex] = sectionRank(right.section);
  return leftGroup - rightGroup || leftIndex - rightIndex;
}

export function topDivergingSections(rows: ProxyRow[]): DivergingSection[] {
  const counts = new Map<string, number>();
  for (const row of rows) {
    if (row.divergedAt !== null) {
      counts.set(row.divergedAt, (counts.get(row.divergedAt) ?? 0) + 1);
    }
  }
  return Array.from(counts, ([section, count]) => ({ section, count }))
    .sort(compareSections)
    .slice(0, TOP_SECTIONS);
}

export function latestLedger(rows: ProxyRow[]): ProxyLedger | null {
  for (let index = rows.length - 1; index >= 0; index -= 1) {
    if (rows[index].ledger !== null) {
      return rows[index].ledger;
    }
  }
  return null;
}

export function ledgerTools(ledger: ProxyLedger): LedgerTool[] {
  const sorted = Object.entries(ledger.tools)
    .map(([name, bytes]) => ({ name, bytes }))
    .sort((left, right) => right.bytes - left.bytes);
  const largest = sorted[0]?.bytes ?? 0;
  return sorted.map((tool) => ({
    ...tool,
    share: largest === 0 ? 0 : tool.bytes / largest,
  }));
}

function clockOf(ts: string): string {
  const moment = new Date(ts);
  if (Number.isNaN(moment.getTime())) {
    return ts;
  }
  return moment.toTimeString().slice(0, 8);
}

function levelOf(row: ProxyRow): LogLevel {
  if (row.divergedAt === null) {
    return "debug";
  }
  return row.divergedAt.startsWith("message:") ? "info" : "warn";
}

function describeRow(row: ProxyRow): string {
  if (row.divergedAt === null) {
    return `stable · ${row.sections} sections`;
  }
  return `${row.divergedAt} · ${row.offset ?? 0} · ${row.diff ?? ""}`;
}

export function proxyFrame(row: ProxyRow): LogFrame {
  return {
    text: `${clockOf(row.ts)} ${describeRow(row)}`,
    level: levelOf(row),
  };
}
