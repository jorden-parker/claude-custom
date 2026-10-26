import type { RunSummary } from "./run-log";

const BENCH_COMMANDS = [
  "messages-bench",
  "cache-probe",
  "review-eval",
  "bench-off-run",
  "bench-off-report",
] as const;

export const BENCH_HISTORY_LIMIT = 20;

export function benchRuns(runs: readonly RunSummary[]): RunSummary[] {
  return runs
    .filter((run) => (BENCH_COMMANDS as readonly string[]).includes(run.command))
    .slice(0, BENCH_HISTORY_LIMIT);
}
