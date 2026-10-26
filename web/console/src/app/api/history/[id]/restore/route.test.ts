import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { listHistory, recordChange } from "@/lib/history";
import { POST } from "./route";

vi.mock("next/server", async (importOriginal) => ({
  ...(await importOriginal<typeof import("next/server")>()),
  connection: async () => undefined,
}));

const UNKNOWN_ID = "20261026-093000-settings-beef";

function context(id: string) {
  return { params: Promise.resolve({ id }) };
}

describe("/api/history/[id]/restore", () => {
  let stateDir: string;
  let target: string;

  beforeEach(() => {
    stateDir = fs.mkdtempSync(path.join(os.tmpdir(), "history-restore-route-"));
    process.env.CLAUDE_CONSOLE_STATE_DIR = stateDir;
    target = path.join(stateDir, "settings.json");
  });

  afterEach(() => {
    delete process.env.CLAUDE_CONSOLE_STATE_DIR;
    fs.rmSync(stateDir, { recursive: true, force: true });
  });

  it("answers 404 for an unknown id", async () => {
    const response = await POST(
      new Request("http://127.0.0.1/"),
      context(UNKNOWN_ID),
    );
    expect(response.status).toBe(404);
  });

  it("answers 409 with the reason when the change had no before", async () => {
    recordChange({
      kind: "settings",
      path: target,
      before: null,
      after: "{}",
      source: "terminal",
    });
    const [entry] = listHistory();

    const response = await POST(
      new Request("http://127.0.0.1/"),
      context(entry.id),
    );

    expect(response.status).toBe(409);
    expect(((await response.json()) as { message: string }).message).toContain(
      "didn't exist",
    );
  });

  it("restores the before bytes and answers the new entry", async () => {
    fs.writeFileSync(target, '{"deny":["WebFetch"]}');
    recordChange({
      kind: "settings",
      path: target,
      before: "{}",
      after: '{"deny":["WebFetch"]}',
      source: "console",
    });
    const [entry] = listHistory();

    const response = await POST(
      new Request("http://127.0.0.1/"),
      context(entry.id),
    );

    expect(response.status).toBe(200);
    expect(
      ((await response.json()) as { entry: { source: string } }).entry.source,
    ).toBe("console-restore");
    expect(fs.readFileSync(target, "utf8")).toBe("{}");
  });
});
