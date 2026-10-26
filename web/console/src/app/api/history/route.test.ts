import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { recordChange } from "@/lib/history";
import { GET } from "./route";

vi.mock("next/server", async (importOriginal) => ({
  ...(await importOriginal<typeof import("next/server")>()),
  connection: async () => undefined,
}));

describe("/api/history", () => {
  let stateDir: string;

  beforeEach(() => {
    stateDir = fs.mkdtempSync(path.join(os.tmpdir(), "history-route-"));
    process.env.CLAUDE_CONSOLE_STATE_DIR = stateDir;
  });

  afterEach(() => {
    delete process.env.CLAUDE_CONSOLE_STATE_DIR;
    fs.rmSync(stateDir, { recursive: true, force: true });
  });

  it("answers an empty list before anything is recorded", async () => {
    const response = await GET();
    expect(await response.json()).toEqual({ entries: [] });
  });

  it("lists the recorded changes newest first", async () => {
    const target = path.join(stateDir, "settings.json");
    recordChange({ kind: "settings", path: target, before: null, after: "one", source: "terminal" });
    recordChange({ kind: "settings", path: target, before: "one", after: "two", source: "console" });

    const response = await GET();
    const body = (await response.json()) as { entries: { source: string }[] };

    expect(body.entries.map((entry) => entry.source)).toEqual(["console", "terminal"]);
  });
});
