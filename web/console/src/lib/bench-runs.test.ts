import { describe, expect, it } from "vitest";
import type { RunSummary } from "./run-log";
import { benchRuns, BENCH_HISTORY_LIMIT } from "./bench-runs";

function run(id: string, command: string): RunSummary {
  return { id, command, label: id, status: "ok", startedAt: "2026-10-26T10:00:00Z", seconds: 1 };
}

describe("bench runs", () => {
  it("keeps only the bench commands, newest first as listed", () => {
    const runs = [run("a", "doctor"), run("b", "messages-bench"), run("c", "bench-off-report"), run("d", "pull")];
    expect(benchRuns(runs).map((item) => item.id)).toEqual(["b", "c"]);
  });

  it("keeps at most the last twenty bench runs", () => {
    const runs = Array.from({ length: 25 }, (_, index) => run(`r${index}`, "cache-probe"));
    const kept = benchRuns(runs);
    expect(kept).toHaveLength(BENCH_HISTORY_LIMIT);
    expect(kept[0].id).toBe("r0");
  });
});
