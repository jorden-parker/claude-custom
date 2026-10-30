export const GH_REPO_PATTERN =
  /^[A-Za-z0-9][A-Za-z0-9-]*\/([A-Za-z0-9_][A-Za-z0-9._-]*|\*)$/;
export const RULE_FIELD_PATTERN = /^[A-Za-z0-9._/-]+$/;
const BARE_TOOL_PATTERN = /^[A-Za-z][A-Za-z0-9_]*$/;
const RULE_VERDICTS = ["allow", "deny"] as const;
const RULE_PROGRAMS = {
  gh: ["pr_comment", "issue_comment", "pr_create"],
  short: ["create", "story-edit"],
} as const;
export const MAX_LINES = 200;
const POLICY_FILES = ["gh-repos", "command-rules", "enabled-tools"] as const;

const COMMENT_PREFIX = "#";
const COMMAND_RULE_FIELD_COUNTS = { min: 3, max: 4 };

export type PolicyFile = (typeof POLICY_FILES)[number];
type RuleProgram = keyof typeof RULE_PROGRAMS;
type LineCheck = (line: string, knownTools: readonly string[]) => string | null;
export type InvalidLine = { line: string; reason: string };
export type ParsedLines = { valid: string[]; invalid: InvalidLine[] };
export type LinePlan = { text: string; lines: string[] };

const CHECKS: Record<PolicyFile, LineCheck> = {
  "gh-repos": checkGhRepo,
  "command-rules": checkCommandRule,
  "enabled-tools": checkEnabledTool,
};

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
  if (file === "command-rules" && line.startsWith(COMMENT_PREFIX)) {
    return null;
  }
  return CHECKS[file](line, knownTools);
}

function checkGhRepo(line: string): string | null {
  return GH_REPO_PATTERN.test(line) ? null : "expected owner/name or owner/*";
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

function checkCommandRule(line: string): string | null {
  const fields = line.split(/\s+/);
  if (
    fields.length < COMMAND_RULE_FIELD_COUNTS.min ||
    fields.length > COMMAND_RULE_FIELD_COUNTS.max
  ) {
    return "expected 3 or 4 fields";
  }
  const unsafeField = fields.find((field) => !RULE_FIELD_PATTERN.test(field));
  if (unsafeField !== undefined) {
    return `field ${unsafeField} has characters a rule may not hold`;
  }
  const [verdict, program, action] = fields;
  if (!(RULE_VERDICTS as readonly string[]).includes(verdict)) {
    return "verdict must be allow or deny";
  }
  if (!isRuleProgram(program)) {
    return `unknown program ${program}`;
  }
  if (!(RULE_PROGRAMS[program] as readonly string[]).includes(action)) {
    return `unknown action ${action} for ${program}`;
  }
  return null;
}

function isRuleProgram(name: string): name is RuleProgram {
  return Object.keys(RULE_PROGRAMS).includes(name);
}
