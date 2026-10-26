import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { listHistory, recordChange } from "@/lib/history";
import { GET } from "./route";

vi.mock("next/server", async (importOriginal) => ({
  ...(await importOriginal<typeof import("next/server")>()),
  connection: async () => undefined,
}));

const UNKNOWN_ID = "20261026-093000-settings-beef";

function context(id: string) {
  return { params: Promise.resolve({ id }) };
}

describe("/api/history/[id]", () => {
  let stateDir: string;

  beforeEach(() => {
    stateDir = fs.mkdtempSync(path.join(os.tmpdir(), "history-entry-route-"));
    process.env.CLAUDE_CONSOLE_STATE_DIR = stateDir;
  });

  afterEach(() => {
    delete process.env.CLAUDE_CONSOLE_STATE_DIR;
    fs.rmSync(stateDir, { recursive: true, force: true });
  });

  it("answers 404 for an unknown id", async () => {
    const response = await GET(new Request("http://127.0.0.1/"), context(UNKNOWN_ID));
    expect(response.status).toBe(404);
  });

  it("answers the entry with its before and after bytes", async () => {
    const target = path.join(stateDir, "settings.json");
    recordChange({ kind: "settings", path: target, before: "{}", after: '{"deny":["WebFetch"]}', source: "console" });
    const [entry] = listHistory();

    const response = await GET(new Request("http://127.0.0.1/"), context(entry.id));

    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({
      entry,
      before: "{}",
      after: '{"deny":["WebFetch"]}',
    });
  });
});
