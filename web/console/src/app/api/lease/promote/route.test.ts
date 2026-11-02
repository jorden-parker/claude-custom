import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { POST } from "./route";

const JSON_HEADERS = { "content-type": "application/json" };
const SESSION_LINE =
  "echo 'live session pid 4242 model qwen3.8-27b-cc rung context-down'";

type TempDirs = { home: string; repo: string };

function promoteRequest(
  body: unknown,
  headers: Record<string, string> = JSON_HEADERS,
) {
  return new Request("http://127.0.0.1:8765/api/lease/promote", {
    method: "POST",
    headers,
    body: typeof body === "string" ? body : JSON.stringify(body),
  });
}

function writeLeaseScript(repo: string, body: string): void {
  fs.mkdirSync(path.join(repo, "bin"), { recursive: true });
  const script = path.join(repo, "bin", "ollama-lease");
  fs.writeFileSync(script, `#!/bin/sh\n${body}\n`);
  fs.chmodSync(script, 0o755);
}

function relaunchDir(home: string, pid: number): string {
  return path.join(home, ".claude-ollama", "relaunch", String(pid));
}

function useTempDirs(): TempDirs {
  const dirs: TempDirs = { home: "", repo: "" };
  let previousHome: string | undefined;

  beforeEach(() => {
    dirs.repo = fs.mkdtempSync(path.join(os.tmpdir(), "lease-promote-"));
    dirs.home = fs.mkdtempSync(path.join(os.tmpdir(), "lease-promote-home-"));
    previousHome = process.env.HOME;
    process.env.HOME = dirs.home;
    process.env.CLAUDE_CUSTOM_HOME = dirs.repo;
    writeLeaseScript(dirs.repo, SESSION_LINE);
  });

  afterEach(() => {
    process.env.HOME = previousHome;
    delete process.env.CLAUDE_CUSTOM_HOME;
    fs.rmSync(dirs.repo, { recursive: true, force: true });
    fs.rmSync(dirs.home, { recursive: true, force: true });
  });

  return dirs;
}

describe("/api/lease/promote accepts", () => {
  const dirs = useTempDirs();

  it("writes ladder-up for the live session and answers with the pid", async () => {
    const target = relaunchDir(dirs.home, 4242);
    fs.mkdirSync(target, { recursive: true });

    const response = await POST(promoteRequest({ rung: "context-down" }));

    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({
      ok: true,
      pid: 4242,
      rung: "context-down",
    });
    expect(
      JSON.parse(fs.readFileSync(path.join(target, "ladder-up"), "utf8")),
    ).toEqual({ rung: "context-down", reason: "promoted from the console" });
  });
});

describe("/api/lease/promote refuses", () => {
  const dirs = useTempDirs();

  it("a body that is not JSON with 415", async () => {
    const response = await POST(
      promoteRequest("rung=context-down", { "content-type": "text/plain" }),
    );

    expect(response.status).toBe(415);
  });

  it("a rung that is not a ladder rung with 400", async () => {
    const response = await POST(promoteRequest({ rung: "../escape" }));

    expect(response.status).toBe(400);
    expect(await response.json()).toEqual({
      message: "Expected { rung: embeddings-off | context-down }",
    });
  });

  it("a rung the session is not on with 409", async () => {
    fs.mkdirSync(relaunchDir(dirs.home, 4242), { recursive: true });

    const response = await POST(promoteRequest({ rung: "embeddings-off" }));

    expect(response.status).toBe(409);
    expect(await response.json()).toEqual({
      message: "The session is on the context-down rung, not embeddings-off",
    });
  });

  it("with 502 when holders fails", async () => {
    writeLeaseScript(dirs.repo, "echo 'ollama lease: lock held' >&2\nexit 1");

    const response = await POST(promoteRequest({ rung: "context-down" }));

    expect(response.status).toBe(502);
    expect(await response.json()).toEqual({
      message: "ollama lease: lock held",
    });
  });
});
