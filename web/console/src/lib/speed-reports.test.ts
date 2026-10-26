import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { listSpeedReports } from "./speed-reports";

const report = (verdict: unknown, next: unknown) => JSON.stringify({ verdict, next, thinking: {} });

describe("listSpeedReports", () => {
  let folder: string;

  beforeEach(() => {
    folder = fs.mkdtempSync(path.join(os.tmpdir(), "speed-reports-"));
  });

  afterEach(() => {
    fs.rmSync(folder, { recursive: true, force: true });
  });

  it("lists good reports newest first with their time and verdict", () => {
    fs.writeFileSync(path.join(folder, "speed-check-20261025-0930.json"), report(["MLX wins"], "Keep MLX"));
    fs.writeFileSync(path.join(folder, "speed-check-20261026-1405.json"), report(["GGUF wins"], "Keep GGUF"));

    expect(listSpeedReports(folder)).toEqual([
      { file: "speed-check-20261026-1405.json", at: "2026-10-26 14:05", verdict: ["GGUF wins"], next: "Keep GGUF" },
      { file: "speed-check-20261025-0930.json", at: "2026-10-25 09:30", verdict: ["MLX wins"], next: "Keep MLX" },
    ]);
  });

  it("skips a report that does not parse", () => {
    fs.writeFileSync(path.join(folder, "speed-check-20261026-1405.json"), "{not json");

    expect(listSpeedReports(folder)).toEqual([]);
  });

  it("skips a report whose verdict or next line has the wrong shape", () => {
    fs.writeFileSync(path.join(folder, "speed-check-20261026-1405.json"), report("one line", "Keep MLX"));
    fs.writeFileSync(path.join(folder, "speed-check-20261026-1406.json"), report(["ok", 3], "Keep MLX"));
    fs.writeFileSync(path.join(folder, "speed-check-20261026-1407.json"), report(["ok"], 5));

    expect(listSpeedReports(folder)).toEqual([]);
  });

  it("ignores files that are not speed reports", () => {
    fs.writeFileSync(path.join(folder, "notes.json"), report(["x"], "y"));
    fs.writeFileSync(path.join(folder, "speed-check-20261026-1405.json.bak"), report(["x"], "y"));

    expect(listSpeedReports(folder)).toEqual([]);
  });

  it("returns an empty list when the folder is missing", () => {
    expect(listSpeedReports(path.join(folder, "missing"))).toEqual([]);
  });
});
