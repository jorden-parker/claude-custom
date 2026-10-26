import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import {
  isRunId,
  listRuns,
  newRunId,
  parseRunEvents,
  resolveRunFile,
  runStatus,
} from "./run-log";

const RUN_ID = "20261026-101500-doctor-3fa9";
const alive = () => true;
const dead = () => false;

function startEvent(pid: number) {
  return { t: 0, kind: "start", id: RUN_ID, command: "doctor", label: "Doctor (27b)", argv: [], pid, started_at: "2026-10-26T10:15:00Z" };
}

describe("run ids", () => {
  it("accepts the documented shape", () => {
    expect(isRunId(RUN_ID)).toBe(true);
  });

  it("rejects traversal, uppercase command names and short hex", () => {
    expect(isRunId("../20261026-101500-doctor-3fa9")).toBe(false);
    expect(isRunId("20261026-101500-Doctor-3fa9")).toBe(false);
    expect(isRunId("20261026-101500-doctor-3fa")).toBe(false);
  });

  it("builds an id from the time and the random hex", () => {
    const now = new Date("2026-10-26T10:15:00Z");
    expect(newRunId("doctor", now, "3fa9")).toBe(RUN_ID);
  });
});

describe("resolveRunFile", () => {
  let directory: string;

  beforeEach(() => {
    directory = fs.mkdtempSync(path.join(os.tmpdir(), "run-log-"));
    process.env.CLAUDE_CONSOLE_STATE_DIR = directory;
    fs.mkdirSync(path.join(directory, "runs"));
  });

  afterEach(() => {
    delete process.env.CLAUDE_CONSOLE_STATE_DIR;
    fs.rmSync(directory, { recursive: true, force: true });
  });

  it("returns the log file for a known id", () => {
    fs.writeFileSync(path.join(directory, "runs", `${RUN_ID}.jsonl`), "");
    expect(resolveRunFile(RUN_ID)).toBe(path.join(directory, "runs", `${RUN_ID}.jsonl`));
  });

  it("returns null for an unknown id, a bad id or a traversal id", () => {
    expect(resolveRunFile(RUN_ID)).toBeNull();
    expect(resolveRunFile("../../etc/passwd")).toBeNull();
    expect(resolveRunFile("not-an-id")).toBeNull();
  });
});

describe("parseRunEvents", () => {
  it("skips lines that are not events", () => {
    const text = `${JSON.stringify({ t: 0, kind: "line", text: "a" })}\nnot json\n\n{"no":"kind"}\n`;
    expect(parseRunEvents(text)).toEqual([{ t: 0, kind: "line", text: "a" }]);
  });
});

describe("runStatus", () => {
  it("is cancelled when the end event says so", () => {
    const events = [startEvent(1), { t: 3, kind: "end", code: -15, cancelled: true }];
    expect(runStatus(events, dead)).toBe("cancelled");
  });

  it("is ok for exit code 0", () => {
    const events = [startEvent(1), { t: 3, kind: "end", code: 0, cancelled: false }];
    expect(runStatus(events, dead)).toBe("ok");
  });

  it("is failed for any other exit code", () => {
    const events = [startEvent(1), { t: 3, kind: "end", code: 1, cancelled: false }];
    expect(runStatus(events, alive)).toBe("failed");
  });

  it("is running with no end while the pid is alive", () => {
    expect(runStatus([startEvent(4242)], alive)).toBe("running");
  });

  it("is lost with no end and a dead pid", () => {
    expect(runStatus([startEvent(4242)], dead)).toBe("lost");
  });

  it("is lost when there is no start event", () => {
    expect(runStatus([], alive)).toBe("lost");
  });
});

describe("listRuns", () => {
  let directory: string;

  beforeEach(() => {
    directory = fs.mkdtempSync(path.join(os.tmpdir(), "run-list-"));
  });

  afterEach(() => {
    fs.rmSync(directory, { recursive: true, force: true });
  });

  function writeRun(id: string, lines: object[]) {
    fs.writeFileSync(path.join(directory, `${id}.jsonl`), lines.map((line) => JSON.stringify(line)).join("\n") + "\n");
  }

  it("lists runs newest first with their status and duration", () => {
    writeRun("20261026-101500-doctor-3fa9", [
      { ...startEvent(1), id: "20261026-101500-doctor-3fa9" },
      { t: 9.5, kind: "end", code: 0, cancelled: false },
    ]);
    writeRun("20261026-111500-doctor-aaaa", [
      { ...startEvent(2), id: "20261026-111500-doctor-aaaa", label: "Doctor (35b)" },
    ]);
    fs.writeFileSync(path.join(directory, "notes.txt"), "ignored");

    const runs = listRuns(directory, dead);

    expect(runs.map((run) => run.id)).toEqual(["20261026-111500-doctor-aaaa", "20261026-101500-doctor-3fa9"]);
    expect(runs[0]).toMatchObject({ command: "doctor", label: "Doctor (35b)", status: "lost", startedAt: "2026-10-26T10:15:00Z" });
    expect(runs[1]).toMatchObject({ status: "ok", seconds: 9.5 });
  });

  it("returns an empty list when the folder does not exist", () => {
    expect(listRuns(path.join(directory, "missing"), alive)).toEqual([]);
  });
});
