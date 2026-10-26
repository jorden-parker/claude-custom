import { describe, expect, it } from "vitest";
import { telemetryReport } from "./telemetry";

const REPO = "/repo";

function stubRunner(code: number, stdout = "", stderr = "") {
  const calls: string[][] = [];
  const run = async (argv: readonly string[]) => {
    calls.push([...argv]);
    return { code, stdout, stderr };
  };
  return { run, calls };
}

describe("telemetry report", () => {
  it("is not configured without CLAUDE_TOOL_TELEMETRY and runs nothing", async () => {
    const { run, calls } = stubRunner(0, "table");
    expect(await telemetryReport({}, REPO, run)).toEqual({ configured: false });
    expect(calls).toEqual([]);
  });

  it("returns the report output when the report command succeeds", async () => {
    const { run, calls } = stubRunner(0, "tool  calls\nBash  3\n");
    const report = await telemetryReport({ CLAUDE_TOOL_TELEMETRY: "/log.jsonl" }, REPO, run);
    expect(report).toEqual({ configured: true, output: "tool  calls\nBash  3\n" });
    expect(calls).toEqual([["/repo/bin/tool-telemetry-report"]]);
  });

  it("returns the error text when the report command fails", async () => {
    const { run } = stubRunner(1, "", "no telemetry log at /log.jsonl\n");
    const report = await telemetryReport({ CLAUDE_TOOL_TELEMETRY: "/log.jsonl" }, REPO, run);
    expect(report).toEqual({ configured: true, error: "no telemetry log at /log.jsonl" });
  });

  it("names the exit code when the failure has no error text", async () => {
    const { run } = stubRunner(2);
    const report = await telemetryReport({ CLAUDE_TOOL_TELEMETRY: "/log.jsonl" }, REPO, run);
    expect(report).toEqual({ configured: true, error: "exited 2" });
  });
});
