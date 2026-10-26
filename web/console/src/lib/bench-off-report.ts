import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const REPORT_NAME = "bench-off.html";

export function benchOffReportFile(env: Record<string, string | undefined>): string {
  const resultsDir = env.BENCH_RESULTS || path.join(os.homedir(), "bench-results");
  return path.join(resultsDir, REPORT_NAME);
}

export function readBenchOffReport(env: Record<string, string | undefined>): string | null {
  try {
    return fs.readFileSync(benchOffReportFile(env), "utf8");
  } catch {
    return null;
  }
}

export function hasBenchOffReport(env: Record<string, string | undefined>): boolean {
  return fs.existsSync(benchOffReportFile(env));
}
