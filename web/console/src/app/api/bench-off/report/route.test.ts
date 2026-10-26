import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { GET } from "./route";

describe("GET /api/bench-off/report", () => {
  let results: string;

  beforeEach(() => {
    results = fs.mkdtempSync(path.join(os.tmpdir(), "bench-off-route-"));
    process.env.BENCH_RESULTS = results;
  });

  afterEach(() => {
    delete process.env.BENCH_RESULTS;
    fs.rmSync(results, { recursive: true, force: true });
  });

  it("answers 404 when no report exists", async () => {
    const response = await GET();
    expect(response.status).toBe(404);
  });

  it("serves the report as HTML in a script-only sandbox", async () => {
    fs.writeFileSync(path.join(results, "bench-off.html"), "<html>report</html>");
    const response = await GET();
    expect(response.status).toBe(200);
    expect(response.headers.get("Content-Type")).toContain("text/html");
    expect(response.headers.get("Content-Security-Policy")).toBe("sandbox allow-scripts");
    expect(await response.text()).toBe("<html>report</html>");
  });
});
