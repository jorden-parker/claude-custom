import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { listMockSpikeReports, specFromReply } from "./reports.ts";

const patches = [
  '{"op":"add","path":"/root","value":"main"}',
  '{"op":"add","path":"/elements/main","value":{"type":"Card","props":{"title":"Pricing","description":null},"children":[]}}',
];

let directory: string;

beforeEach(() => {
  directory = fs.mkdtempSync(path.join(os.tmpdir(), "mock-spike-reports-"));
});

afterEach(() => {
  fs.rmSync(directory, { recursive: true, force: true });
});

describe("specFromReply", () => {
  it("compiles the patch lines and ignores prose", () => {
    const spec = specFromReply(["note", ...patches].join("\n"));
    expect(spec.root).toBe("main");
    expect(spec.elements?.main.type).toBe("Card");
  });
});

describe("listMockSpikeReports", () => {
  it("reads reports newest first with compiled specs", () => {
    const stored = {
      model: "m",
      summary: { verdict: "sound" },
      results: [{ brief: "pricing", run: 1, reply: patches.join("\n") }],
    };
    fs.writeFileSync(
      path.join(directory, "mock-spike-m-20261101T100000.json"),
      JSON.stringify(stored),
    );
    fs.writeFileSync(
      path.join(directory, "mock-spike-m-20261102T100000.json"),
      JSON.stringify(stored),
    );
    fs.writeFileSync(
      path.join(directory, "speed-check-20261102-1000.json"),
      "{}",
    );
    fs.writeFileSync(path.join(directory, "mock-spike-broken.json"), "nope");
    const reports = listMockSpikeReports(directory);
    expect(reports.map((report) => report.file)).toEqual([
      "mock-spike-m-20261102T100000.json",
      "mock-spike-m-20261101T100000.json",
    ]);
    expect(reports[0]).toMatchObject({ model: "m", verdict: "sound" });
    expect(reports[0].runs[0].spec.root).toBe("main");
    expect(reports[0].runs[0].score.valid).toBe(true);
  });

  it("returns nothing for a missing folder", () => {
    expect(listMockSpikeReports(path.join(directory, "missing"))).toEqual([]);
  });
});
