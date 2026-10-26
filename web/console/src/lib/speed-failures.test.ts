import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { failedSpeedChecks } from "./speed-failures";

const RUN_ID = "20261026-140500-speed-check-a1b2";
const OK_RUN_ID = "20261026-150000-speed-check-c3d4";
const DOCTOR_RUN_ID = "20261026-160000-doctor-e5f6";

const eventLines = (events: object[]) => events.map((event) => JSON.stringify(event)).join("\n") + "\n";

describe("failedSpeedChecks", () => {
  let runs: string;

  beforeEach(() => {
    runs = fs.mkdtempSync(path.join(os.tmpdir(), "speed-failures-"));
    const start = { t: 0, kind: "start", command: "speed-check", label: "Speed check", started_at: "2026-10-26T14:05:00Z" };
    const stopped = { t: 2, kind: "line", stream: "stderr", text: "speed-check stopped: no AC power" };
    fs.writeFileSync(path.join(runs, `${RUN_ID}.jsonl`), eventLines([start, stopped, { t: 3, kind: "end", code: 1 }]));
    fs.writeFileSync(path.join(runs, `${OK_RUN_ID}.jsonl`), eventLines([start, { t: 3, kind: "end", code: 0 }]));
    fs.writeFileSync(
      path.join(runs, `${DOCTOR_RUN_ID}.jsonl`),
      eventLines([{ ...start, command: "doctor" }, { t: 3, kind: "end", code: 1 }]),
    );
  });

  afterEach(() => {
    fs.rmSync(runs, { recursive: true, force: true });
  });

  it("lists only failed speed-check runs with their stopped line", () => {
    expect(failedSpeedChecks(runs)).toEqual([
      { id: RUN_ID, startedAt: "2026-10-26T14:05:00Z", stoppedLine: "speed-check stopped: no AC power" },
    ]);
  });

  it("leaves the stopped line empty when the run never printed one", () => {
    fs.writeFileSync(
      path.join(runs, `${RUN_ID}.jsonl`),
      eventLines([{ t: 0, kind: "start", command: "speed-check", label: "Speed check", started_at: "x" }, { t: 3, kind: "end", code: 1 }]),
    );

    expect(failedSpeedChecks(runs)).toEqual([{ id: RUN_ID, startedAt: "x", stoppedLine: null }]);
  });
});
