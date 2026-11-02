export type WhyPrefix = { percent: number; stable: number; requests: number };

export type WhyDivergingSection = { section: string; count: number };

export type WhyReport = {
  verdict: string;
  summary: string;
  evidence: string;
  fix: string;
  prefix: WhyPrefix;
  diverging: WhyDivergingSection[];
  incidents: Record<string, number>;
  window: string;
};

export type RescueSummary = { path: string; lines: string[] };

export type RuleCardListing = { id: string; triggers: string[] };

export type RuleCard = RuleCardListing & { body: string };

export type RecipeEntry = { match: string; steps: string[] };

export type HookRecipes = { hook: string; entries: RecipeEntry[] };

const RESCUE_PATH_PATTERN = /^(~|\/).*\.md$/;
const RESCUE_SUMMARY_PREFIXES = [
  "doctor:",
  "lease:",
  "incidents:",
  "proxy:",
  "memory:",
];
const CARD_LIST_PATTERN = /^([a-z0-9][a-z0-9-]*): (.+)$/;
const FRONT_MATTER_FENCE = "---";
const TRIGGER_ITEM_PATTERN = /^\s*-\s*(.+?)\s*$/;

export function parseWhyReport(lines: readonly string[]): WhyReport | null {
  const start = lines.findIndex((line) => line.trim() === "{");
  if (start < 0) {
    return null;
  }
  const parsed = parseJson(lines.slice(start).join("\n"));
  return isWhyReport(parsed) ? parsed : null;
}

function isWhyReport(value: unknown): value is WhyReport {
  if (!isRecord(value)) {
    return false;
  }
  const texts = ["verdict", "summary", "evidence", "fix", "window"];
  return (
    texts.every((key) => typeof value[key] === "string") &&
    isPrefix(value.prefix) &&
    Array.isArray(value.diverging) &&
    isRecord(value.incidents)
  );
}

function isPrefix(value: unknown): value is WhyPrefix {
  return (
    isRecord(value) &&
    typeof value.percent === "number" &&
    typeof value.stable === "number" &&
    typeof value.requests === "number"
  );
}

export function parseRescueSummary(
  lines: readonly string[],
): RescueSummary | null {
  const path = lines.find((line) => RESCUE_PATH_PATTERN.test(line.trim()));
  if (path === undefined) {
    return null;
  }
  const summaryLines = lines.filter((line) =>
    RESCUE_SUMMARY_PREFIXES.some((prefix) => line.startsWith(prefix)),
  );
  return { path: path.trim(), lines: summaryLines };
}

export function parseRuleCardList(stdout: string): RuleCardListing[] {
  return stdout
    .split("\n")
    .map((line) => CARD_LIST_PATTERN.exec(line))
    .filter((match): match is RegExpExecArray => match !== null)
    .map((match) => ({
      id: match[1],
      triggers: match[2].split(",").map((trigger) => trigger.trim()),
    }));
}

export function parseRuleCard(id: string, text: string): RuleCard {
  const lines = text.split("\n");
  if (lines[0]?.trim() !== FRONT_MATTER_FENCE) {
    return { id, triggers: [], body: text.trim() };
  }
  const closing = lines.findIndex(
    (line, index) => index > 0 && line.trim() === FRONT_MATTER_FENCE,
  );
  if (closing < 0) {
    return { id, triggers: [], body: text.trim() };
  }
  return {
    id,
    triggers: triggersOf(lines.slice(1, closing)),
    body: lines
      .slice(closing + 1)
      .join("\n")
      .trim(),
  };
}

function triggersOf(frontMatter: readonly string[]): string[] {
  return frontMatter
    .map((line) => TRIGGER_ITEM_PATTERN.exec(line))
    .filter((match): match is RegExpExecArray => match !== null)
    .map((match) => match[1]);
}

export function parseRecipeEntries(text: string): RecipeEntry[] {
  const parsed = parseJson(text);
  if (!Array.isArray(parsed)) {
    return [];
  }
  return parsed.filter(isRecipeEntry);
}

function isRecipeEntry(value: unknown): value is RecipeEntry {
  return (
    isRecord(value) &&
    typeof value.match === "string" &&
    Array.isArray(value.steps) &&
    value.steps.every((step) => typeof step === "string")
  );
}

function parseJson(text: string): unknown {
  try {
    return JSON.parse(text);
  } catch {
    return null;
  }
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
