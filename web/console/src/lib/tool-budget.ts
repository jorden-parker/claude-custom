import type { ProfileOverride } from "./profile-rules";

export type ToolBudgetRow = {
  tool: string;
  schema_bytes: number;
  requests: number;
  session_bytes: number;
  calls: number;
  bytes_per_call: number | null;
};

export type ToolBudgetSuggestion = {
  drop: string[];
  keep: string[];
  saves_bytes: number;
};

export type ToolBudgetReport = {
  since_days: number;
  requests: number;
  rows: ToolBudgetRow[];
  protected: string[];
  protected_source: string;
  suggest: ToolBudgetSuggestion;
};

export type BudgetBar = { tool: string; share: number };

export type AppliedSuggestion = {
  override: ProfileOverride;
  applied: string[];
  skipped: string[];
};

const KIB = 1024;

export function parseToolBudgetReport(text: string): ToolBudgetReport | null {
  let parsed: unknown;
  try {
    parsed = JSON.parse(text);
  } catch {
    return null;
  }
  return isReport(parsed) ? parsed : null;
}

export function budgetBars(rows: readonly ToolBudgetRow[]): BudgetBar[] {
  const largest = Math.max(0, ...rows.map((row) => row.session_bytes));
  return rows.map((row) => ({
    tool: row.tool,
    share: largest === 0 ? 0 : row.session_bytes / largest,
  }));
}

export function savesText(suggestion: ToolBudgetSuggestion): string {
  return `saves ${(suggestion.saves_bytes / KIB).toFixed(1)} KiB per request`;
}

export function costText(row: ToolBudgetRow): string {
  return row.bytes_per_call === null
    ? "never called"
    : `${row.bytes_per_call} bytes per call`;
}

export function applySuggestion(
  override: ProfileOverride,
  drop: readonly string[],
  toolNames: readonly string[],
): AppliedSuggestion {
  const tools = { ...(override.tools ?? {}) };
  const applied: string[] = [];
  const skipped: string[] = [];
  for (const name of drop) {
    if (toolNames.includes(name) && tools[name] !== "off") {
      tools[name] = "off";
      applied.push(name);
    } else {
      skipped.push(name);
    }
  }
  return { override: { ...override, tools }, applied, skipped };
}

function isReport(value: unknown): value is ToolBudgetReport {
  if (
    !isRecord(value) ||
    !Array.isArray(value.rows) ||
    !value.rows.every(isRow)
  ) {
    return false;
  }
  return (
    typeof value.since_days === "number" &&
    typeof value.requests === "number" &&
    isStringList(value.protected) &&
    typeof value.protected_source === "string" &&
    isSuggestion(value.suggest)
  );
}

function isRow(value: unknown): value is ToolBudgetRow {
  if (!isRecord(value)) {
    return false;
  }
  return (
    typeof value.tool === "string" &&
    typeof value.schema_bytes === "number" &&
    typeof value.requests === "number" &&
    typeof value.session_bytes === "number" &&
    typeof value.calls === "number" &&
    (value.bytes_per_call === null || typeof value.bytes_per_call === "number")
  );
}

function isSuggestion(value: unknown): value is ToolBudgetSuggestion {
  return (
    isRecord(value) &&
    isStringList(value.drop) &&
    isStringList(value.keep) &&
    typeof value.saves_bytes === "number"
  );
}

function isStringList(value: unknown): value is string[] {
  return (
    Array.isArray(value) && value.every((item) => typeof item === "string")
  );
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
