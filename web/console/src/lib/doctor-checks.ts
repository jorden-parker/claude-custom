export type DoctorLevel = "ok" | "warn" | "fail";
export type DoctorCheck = { level: DoctorLevel; text: string };
export type DoctorSummary = Record<DoctorLevel, number>;

const CHECK_LINE = /^(ok|warn|fail)\s+(.*)$/;

export function parseDoctorLine(line: string): DoctorCheck | null {
  const match = CHECK_LINE.exec(line);
  if (match === null) {
    return null;
  }
  return { level: match[1] as DoctorLevel, text: match[2] };
}

export function doctorSummary(checks: readonly DoctorCheck[]): DoctorSummary {
  const summary: DoctorSummary = { ok: 0, warn: 0, fail: 0 };
  for (const check of checks) {
    summary[check.level] += 1;
  }
  return summary;
}
