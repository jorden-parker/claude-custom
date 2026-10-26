import fs from "node:fs";
import os from "node:os";
import path from "node:path";

export type SpeedReport = { file: string; at: string; verdict: string[]; next: string };

const REPORT_PATTERN = /^speed-check-(\d{4})(\d{2})(\d{2})-(\d{2})(\d{2})\.json$/;

function speedReportsDir(): string {
  return path.join(os.homedir(), "bench-results");
}

export function listSpeedReports(directory: string = speedReportsDir()): SpeedReport[] {
  const names = readNames(directory).filter((name) => REPORT_PATTERN.test(name));
  return names
    .sort()
    .reverse()
    .flatMap((name) => {
      const report = readReport(path.join(directory, name), name);
      return report === null ? [] : [report];
    });
}

function readNames(directory: string): string[] {
  try {
    return fs.readdirSync(directory);
  } catch {
    return [];
  }
}

function readReport(file: string, name: string): SpeedReport | null {
  try {
    const value = JSON.parse(fs.readFileSync(file, "utf8")) as { verdict?: unknown; next?: unknown };
    if (!isVerdict(value.verdict) || typeof value.next !== "string") {
      return null;
    }
    return { file: name, at: timestampOf(name), verdict: value.verdict, next: value.next };
  } catch {
    return null;
  }
}

function isVerdict(value: unknown): value is string[] {
  return Array.isArray(value) && value.every((line) => typeof line === "string");
}

function timestampOf(name: string): string {
  const [, year, month, day, hour, minute] = REPORT_PATTERN.exec(name) ?? [];
  return `${year}-${month}-${day} ${hour}:${minute}`;
}
