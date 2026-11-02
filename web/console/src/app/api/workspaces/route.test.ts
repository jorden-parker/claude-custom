import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { GET, PUT } from "./route";

vi.mock("next/server", async (importOriginal) => ({
  ...(await importOriginal<typeof import("next/server")>()),
  connection: async () => undefined,
}));

const ORIGIN = "http://127.0.0.1:8808";

const jsonRequest = (body: unknown, contentType = "application/json") =>
  new Request(`${ORIGIN}/api/workspaces`, {
    method: "PUT",
    headers: { "content-type": contentType, origin: ORIGIN },
    body: JSON.stringify(body),
  });

describe("/api/workspaces", () => {
  let home: string;
  let project: string;
  let previous: { home?: string; state?: string };

  beforeEach(() => {
    home = fs.mkdtempSync(path.join(os.tmpdir(), "workspaces-route-home-"));
    project = fs.realpathSync(
      fs.mkdtempSync(path.join(os.tmpdir(), "workspaces-route-project-")),
    );
    previous = {
      home: process.env.HOME,
      state: process.env.CLAUDE_CONSOLE_STATE_DIR,
    };
    process.env.HOME = home;
    process.env.CLAUDE_CONSOLE_STATE_DIR = path.join(home, "state");
  });

  afterEach(() => {
    process.env.HOME = previous.home;
    if (previous.state === undefined) {
      delete process.env.CLAUDE_CONSOLE_STATE_DIR;
    } else {
      process.env.CLAUDE_CONSOLE_STATE_DIR = previous.state;
    }
    fs.rmSync(home, { recursive: true, force: true });
    fs.rmSync(project, { recursive: true, force: true });
  });

  it("answers the state file path and an empty list before any launch", async () => {
    const body = await (await GET()).json();

    expect(body).toEqual({
      path: path.join(home, ".claude-ollama", ".claude.json"),
      workspaces: [],
    });
  });

  it("trusts a folder and answers the new list", async () => {
    const response = await PUT(jsonRequest({ path: project, trusted: true }));

    expect(response.status).toBe(200);
    expect(await response.json()).toMatchObject({
      workspaces: [{ path: project, trusted: true, exists: true, skills: [] }],
    });
  });

  it("rejects a body without a boolean trusted flag", async () => {
    const response = await PUT(jsonRequest({ path: project, trusted: "yes" }));

    expect(response.status).toBe(400);
    expect(await response.json()).toEqual({
      message: "Expected { path: string, trusted: boolean }",
    });
  });

  it("rejects a folder that does not exist", async () => {
    const response = await PUT(
      jsonRequest({ path: "/no/such/folder", trusted: true }),
    );

    expect(response.status).toBe(400);
    expect(await response.json()).toEqual({
      message: "/no/such/folder is not a folder on this machine",
    });
  });

  it("rejects a body that is not JSON", async () => {
    const response = await PUT(
      jsonRequest({ path: project, trusted: true }, "text/plain"),
    );

    expect(response.status).toBe(415);
  });
});
