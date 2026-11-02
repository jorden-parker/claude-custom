export type DoctorLevel = "ok" | "warn" | "fail";
export type DoctorCheck = { level: DoctorLevel; text: string; fixes?: string[] };
export type DoctorSummary = Record<DoctorLevel, number>;

const CHECK_LINE = /^(ok|warn|fail|current|skipped|unknown|behind|unpinned)\s+(.*)$/;
const FIX_LINE = /^\s+fix: (.+)$/;

const WORD_LEVELS: Record<string, DoctorLevel> = {
  ok: "ok",
  warn: "warn",
  fail: "fail",
  current: "ok",
  skipped: "ok",
  unknown: "warn",
  behind: "fail",
  unpinned: "fail",
};

const DOCTOR_WORDS = new Set(["ok", "warn", "fail"]);

export function parseDoctorLine(line: string): DoctorCheck | null {
  const match = CHECK_LINE.exec(line);
  if (match === null) {
    return null;
  }
  const word = match[1];
  const text = DOCTOR_WORDS.has(word) ? match[2] : `${word} ${match[2]}`;
  return { level: WORD_LEVELS[word], text };
}

function parseFixLine(line: string): string | null {
  return FIX_LINE.exec(line)?.[1] ?? null;
}

export function doctorSummary(checks: readonly DoctorCheck[]): DoctorSummary {
  const summary: DoctorSummary = { ok: 0, warn: 0, fail: 0 };
  for (const check of checks) {
    summary[check.level] += 1;
  }
  return summary;
}

export type DoctorOutput = { checks: DoctorCheck[]; other: string[] };

export function checksFromLines(lines: readonly string[]): DoctorOutput {
  const output: DoctorOutput = { checks: [], other: [] };
  for (const line of lines) {
    const check = parseDoctorLine(line);
    if (check !== null) {
      output.checks.push(check);
      continue;
    }
    const fix = parseFixLine(line);
    const previous = output.checks.at(-1);
    if (fix !== null && previous !== undefined) {
      previous.fixes = [...(previous.fixes ?? []), fix];
    } else {
      output.other.push(line);
    }
  }
  return output;
}
