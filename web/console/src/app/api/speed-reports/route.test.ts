import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { GET } from "./route";

vi.mock("next/server", async (importOriginal) => ({
  ...(await importOriginal<typeof import("next/server")>()),
  connection: async () => {},
}));

describe("/api/speed-reports", () => {
  let home: string;
  let previousHome: string | undefined;

  beforeEach(() => {
    home = fs.mkdtempSync(path.join(os.tmpdir(), "speed-route-"));
    previousHome = process.env.HOME;
    process.env.HOME = home;
    fs.mkdirSync(path.join(home, "bench-results"));
    fs.writeFileSync(
      path.join(home, "bench-results", "speed-check-20261026-1405.json"),
      JSON.stringify({ verdict: ["MLX wins"], next: "Keep MLX" }),
    );
  });

  afterEach(() => {
    process.env.HOME = previousHome;
    fs.rmSync(home, { recursive: true, force: true });
  });

  it("returns the reports in ~/bench-results", async () => {
    const response = await GET();

    expect(await response.json()).toEqual([
      { file: "speed-check-20261026-1405.json", at: "2026-10-26 14:05", verdict: ["MLX wins"], next: "Keep MLX" },
    ]);
  });
});
