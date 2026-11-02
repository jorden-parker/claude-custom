import path from "node:path";
import { runOnce, type RunOnceOptions, type RunOnceResult } from "./run-once";
import { parseToolBudgetReport, type ToolBudgetReport } from "./tool-budget";

export type ToolBudgetResult =
  { ok: true; report: ToolBudgetReport } | { ok: false; message: string };

type RunCommand = (
  argv: readonly string[],
  options: RunOnceOptions,
) => Promise<RunOnceResult>;

const REPORT_OPTIONS: RunOnceOptions = {
  timeoutMs: 20_000,
  maxBytes: 4 * 1024 * 1024,
};
const PROXY_LOG = ["proxy", "requests.jsonl"];
const TELEMETRY_LOG = ["telemetry", "tool-calls.jsonl"];

export async function toolBudgetReport(
  env: Record<string, string | undefined>,
  repoDir: string,
  run: RunCommand = runOnce,
): Promise<ToolBudgetResult> {
  const stateDir = env.CLAUDE_CONSOLE_STATE_DIR ?? "";
  const telemetry =
    env.CLAUDE_TOOL_TELEMETRY ?? path.join(stateDir, ...TELEMETRY_LOG);
  const result = await run(
    [
      `${repoDir}/bin/tool-budget`,
      "--proxy-log",
      path.join(stateDir, ...PROXY_LOG),
      "--telemetry",
      telemetry,
      "--json",
    ],
    REPORT_OPTIONS,
  );
  if (result.code !== 0) {
    return {
      ok: false,
      message: result.stderr.trim() || `tool-budget exited ${result.code}`,
    };
  }
  const report = parseToolBudgetReport(result.stdout);
  return report === null
    ? { ok: false, message: "tool-budget printed no report" }
    : { ok: true, report };
}
