import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { GET } from "./route";

vi.mock("next/server", async (importOriginal) => ({
  ...(await importOriginal<typeof import("next/server")>()),
  connection: async () => undefined,
}));

describe("/api/rescue/latest", () => {
  let home: string;
  let previousHome: string | undefined;

  beforeEach(() => {
    home = fs.mkdtempSync(path.join(os.tmpdir(), "rescue-route-"));
    previousHome = process.env.HOME;
    process.env.HOME = home;
  });

  afterEach(() => {
    process.env.HOME = previousHome;
    fs.rmSync(home, { recursive: true, force: true });
  });

  it("returns the newest markdown report under ~/.claude-ollama/rescue", async () => {
    const dir = path.join(home, ".claude-ollama", "rescue");
    fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(path.join(dir, "20261101T090000Z.md"), "# old\n");
    fs.writeFileSync(path.join(dir, "20261102T140211Z.md"), "# new\n");
    fs.writeFileSync(path.join(dir, "notes.txt"), "ignored");

    const response = await GET();

    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({
      path: path.join(dir, "20261102T140211Z.md"),
      text: "# new\n",
    });
  });

  it("answers 404 when no report exists", async () => {
    const response = await GET();

    expect(response.status).toBe(404);
    expect(await response.json()).toEqual({
      message: "No rescue report yet; run claude-ollama rescue first",
    });
  });
});
