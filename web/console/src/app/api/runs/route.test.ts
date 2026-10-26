import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { POST } from "./route";

function jsonRequest(body: string, contentType = "application/json"): Request {
  return new Request("http://127.0.0.1/api/runs", {
    method: "POST",
    headers: { "Content-Type": contentType },
    body,
  });
}

describe("/api/runs", () => {
  let stateDir: string;

  beforeEach(() => {
    stateDir = fs.mkdtempSync(path.join(os.tmpdir(), "runs-route-"));
    process.env.CLAUDE_CONSOLE_STATE_DIR = stateDir;
  });

  afterEach(() => {
    delete process.env.CLAUDE_CONSOLE_STATE_DIR;
    fs.rmSync(stateDir, { recursive: true, force: true });
  });

  it("answers 415 to a POST that is not JSON", async () => {
    const response = await POST(jsonRequest("command=doctor", "text/plain"));
    expect(response.status).toBe(415);
  });

  it("answers 400 to a body without a command and params", async () => {
    const response = await POST(jsonRequest(JSON.stringify({ command: "doctor", params: { size: 27 } })));
    expect(response.status).toBe(400);
  });

  it("answers 400 to a body that is not JSON", async () => {
    const response = await POST(jsonRequest("{not json"));
    expect(response.status).toBe(400);
  });

  it("answers 400 to an unknown command", async () => {
    const response = await POST(jsonRequest(JSON.stringify({ command: "pull", params: {} })));
    expect(response.status).toBe(400);
  });
});
