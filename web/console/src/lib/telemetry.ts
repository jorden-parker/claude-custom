import { runOnce, type RunOnceOptions, type RunOnceResult } from "./run-once";

export type TelemetryReport = { configured: boolean; output?: string; error?: string };
export type RunCommand = (argv: readonly string[], options: RunOnceOptions) => Promise<RunOnceResult>;

const REPORT_OPTIONS: RunOnceOptions = { timeoutMs: 10000, maxBytes: 1024 * 1024 };

export async function telemetryReport(
  env: Record<string, string | undefined>,
  repoDir: string,
  run: RunCommand = runOnce,
): Promise<TelemetryReport> {
  if (!env.CLAUDE_TOOL_TELEMETRY) {
    return { configured: false };
  }
  const result = await run([`${repoDir}/bin/tool-telemetry-report`], REPORT_OPTIONS);
  if (result.code === 0) {
    return { configured: true, output: result.stdout };
  }
  return { configured: true, error: result.stderr.trim() || `exited ${result.code}` };
}
