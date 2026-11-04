export type DoctorLevel = "ok" | "warn" | "fail";
export type DoctorCheck = { level: DoctorLevel; text: string; fixes?: string[] };
export type DoctorSummary = Record<DoctorLevel, number>;

const CHECK_LINE = /^(ok|warn|fail)\s+(.*)$/;
const OUTDATED_LINE = /^(current|behind|unknown)\s+([a-z0-9][a-z0-9.-]*)(?:\s+(\(.+\)))?$/;
const OUTDATED_LEVEL: Record<string, DoctorLevel> = { current: "ok", behind: "fail", unknown: "warn" };
const FIX_LINE = /^\s*fix: (.+)$/;

export function parseDoctorLine(line: string): DoctorCheck | null {
  const match = CHECK_LINE.exec(line);
  return match === null ? null : { level: match[1] as DoctorLevel, text: match[2] };
}

export function parseOutdatedLine(line: string): DoctorCheck | null {
  const match = OUTDATED_LINE.exec(line.trim());
  if (match === null || (match[1] === "current") !== (match[3] === undefined)) {
    return null;
  }
  const detail = match[3] === undefined ? "" : ` ${match[3]}`;
  return { level: OUTDATED_LEVEL[match[1]], text: `${match[2]} ${match[1]}${detail}` };
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
    const check = parseDoctorLine(line) ?? parseOutdatedLine(line);
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
