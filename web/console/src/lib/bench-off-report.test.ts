import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { benchOffReportFile, hasBenchOffReport, readBenchOffReport } from "./bench-off-report";

describe("bench-off report file", () => {
  let results: string;

  beforeEach(() => {
    results = fs.mkdtempSync(path.join(os.tmpdir(), "bench-off-report-"));
  });

  afterEach(() => {
    fs.rmSync(results, { recursive: true, force: true });
  });

  it("points at bench-off.html in BENCH_RESULTS", () => {
    expect(benchOffReportFile({ BENCH_RESULTS: results })).toBe(path.join(results, "bench-off.html"));
  });

  it("defaults to ~/bench-results when BENCH_RESULTS is unset", () => {
    expect(benchOffReportFile({})).toBe(path.join(os.homedir(), "bench-results", "bench-off.html"));
  });

  it("reads the report when it exists", () => {
    fs.writeFileSync(path.join(results, "bench-off.html"), "<html>report</html>");
    expect(readBenchOffReport({ BENCH_RESULTS: results })).toBe("<html>report</html>");
  });

  it("returns null when no report exists yet", () => {
    expect(readBenchOffReport({ BENCH_RESULTS: results })).toBeNull();
  });
});

describe("bench-off report existence", () => {
  let results: string;

  beforeEach(() => {
    results = fs.mkdtempSync(path.join(os.tmpdir(), "bench-off-exists-"));
  });

  afterEach(() => {
    fs.rmSync(results, { recursive: true, force: true });
  });

  it("is true once the report file exists", () => {
    fs.writeFileSync(path.join(results, "bench-off.html"), "");
    expect(hasBenchOffReport({ BENCH_RESULTS: results })).toBe(true);
  });

  it("is false while no report exists", () => {
    expect(hasBenchOffReport({ BENCH_RESULTS: results })).toBe(false);
  });
});
