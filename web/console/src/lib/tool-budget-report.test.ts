import { describe, expect, it } from "vitest";
import type { RunOnceOptions } from "./run-once";
import type { ToolBudgetReport } from "./tool-budget";
import { toolBudgetReport } from "./tool-budget-report";

const REPORT: ToolBudgetReport = {
  since_days: 14,
  requests: 26,
  rows: [
    {
      tool: "WebFetch",
      schema_bytes: 2048,
      requests: 26,
      session_bytes: 53248,
      calls: 0,
      bytes_per_call: null,
    },
  ],
  protected: ["Bash"],
  protected_source: "built-in list in bin/tool-budget",
  suggest: { drop: ["WebFetch"], keep: [], saves_bytes: 2048 },
};

describe("toolBudgetReport", () => {
  const env = {
    CLAUDE_CONSOLE_STATE_DIR: "/state",
    CLAUDE_TOOL_TELEMETRY: "/calls.jsonl",
  };

  it("runs the script with the state dir's proxy log, the telemetry file and --json", async () => {
    const calls: { argv: readonly string[]; options: RunOnceOptions }[] = [];
    const run = async (argv: readonly string[], options: RunOnceOptions) => {
      calls.push({ argv, options });
      return { code: 0, stdout: JSON.stringify(REPORT), stderr: "" };
    };

    const result = await toolBudgetReport(env, "/repo", run);

    expect(result).toEqual({ ok: true, report: REPORT });
    expect(calls[0].argv).toEqual([
      "/repo/bin/tool-budget",
      "--proxy-log",
      "/state/proxy/requests.jsonl",
      "--telemetry",
      "/calls.jsonl",
      "--json",
    ]);
  });

  it("reads the telemetry file under the state dir when CLAUDE_TOOL_TELEMETRY is unset", async () => {
    const argvs: (readonly string[])[] = [];
    const run = async (argv: readonly string[]) => {
      argvs.push(argv);
      return { code: 0, stdout: JSON.stringify(REPORT), stderr: "" };
    };

    await toolBudgetReport(
      { CLAUDE_CONSOLE_STATE_DIR: "/state" },
      "/repo",
      run,
    );

    expect(argvs[0]).toContain("/state/telemetry/tool-calls.jsonl");
  });

  it("returns the script's stderr when it fails", async () => {
    const run = async () => ({
      code: 1,
      stdout: "",
      stderr: "tool-budget: boom\n",
    });

    expect(await toolBudgetReport(env, "/repo", run)).toEqual({
      ok: false,
      message: "tool-budget: boom",
    });
  });

  it("names unreadable output", async () => {
    const run = async () => ({ code: 0, stdout: "garbage", stderr: "" });

    expect(await toolBudgetReport(env, "/repo", run)).toEqual({
      ok: false,
      message: "tool-budget printed no report",
    });
  });
});
