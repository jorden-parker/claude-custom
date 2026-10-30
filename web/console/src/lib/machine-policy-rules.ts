export const GH_REPO_PATTERN =
  /^[A-Za-z0-9][A-Za-z0-9-]{0,38}\/[A-Za-z0-9_][A-Za-z0-9._-]{0,99}$/;
const BARE_TOOL_PATTERN = /^[A-Za-z][A-Za-z0-9_]*$/;
export const MAX_LINES = 200;
export const POLICY_FILES = ["gh-repos", "enabled-tools"] as const;

const COMMENT_PREFIX = "#";

export type PolicyFile = (typeof POLICY_FILES)[number];
type LineCheck = (line: string, knownTools: readonly string[]) => string | null;
export type InvalidLine = { line: string; reason: string };
export type ParsedLines = { valid: string[]; invalid: InvalidLine[] };
export type LinePlan = { text: string; lines: string[] };

const CHECKS: Record<PolicyFile, LineCheck> = {
  "gh-repos": checkGhRepo,
  "enabled-tools": checkEnabledTool,
};

export function isPolicyFile(name: string): name is PolicyFile {
  return (POLICY_FILES as readonly string[]).includes(name);
}

export function bareToolNames(rules: readonly string[]): string[] {
  return rules.filter((rule) => BARE_TOOL_PATTERN.test(rule));
}

export function parseLines(
  file: PolicyFile,
  text: string,
  knownTools: readonly string[] = [],
): ParsedLines {
  const parsed: ParsedLines = { valid: [], invalid: [] };
  for (const line of nonEmptyTrimmed(text.split("\n"))) {
    const reason = lineProblem(file, line, knownTools);
    if (reason === null) {
      parsed.valid.push(line);
    } else {
      parsed.invalid.push({ line, reason });
    }
  }
  return parsed;
}

export function planLines(
  file: PolicyFile,
  lines: string[],
  knownTools: readonly string[] = [],
): LinePlan {
  const kept = nonEmptyTrimmed(lines);
  if (kept.length > MAX_LINES) {
    throw new Error(`at most ${MAX_LINES} lines`);
  }
  for (const line of kept) {
    const reason = lineProblem(file, line, knownTools);
    if (reason !== null) {
      throw new Error(`${line}: ${reason}`);
    }
  }
  return { text: kept.map((line) => `${line}\n`).join(""), lines: kept };
}

function nonEmptyTrimmed(lines: string[]): string[] {
  return lines.map((line) => line.trim()).filter((line) => line !== "");
}

function lineProblem(
  file: PolicyFile,
  line: string,
  knownTools: readonly string[],
): string | null {
  if (file === "gh-repos" && line.startsWith(COMMENT_PREFIX)) {
    return null;
  }
  return CHECKS[file](line, knownTools);
}

function checkGhRepo(line: string): string | null {
  return GH_REPO_PATTERN.test(line) ? null : "expected owner/name";
}

function checkEnabledTool(
  line: string,
  knownTools: readonly string[],
): string | null {
  const isKnownBareTool =
    BARE_TOOL_PATTERN.test(line) && knownTools.includes(line);
  return isKnownBareTool
    ? null
    : "not a bare tool name in the overlay's deny list";
}
