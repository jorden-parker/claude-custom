import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { GET } from "./route";

vi.mock("next/server", async (importOriginal) => ({
  ...(await importOriginal<typeof import("next/server")>()),
  connection: async () => {},
}));

describe("/api/server", () => {
  let repo: string;

  const writeAgent = (body: string) => {
    fs.mkdirSync(path.join(repo, "bin"), { recursive: true });
    const agent = path.join(repo, "bin", "ollama-agent");
    fs.writeFileSync(agent, `#!/bin/sh\n${body}\n`);
    fs.chmodSync(agent, 0o755);
  };

  beforeEach(() => {
    repo = fs.mkdtempSync(path.join(os.tmpdir(), "server-route-"));
    process.env.CLAUDE_CUSTOM_HOME = repo;
  });

  afterEach(() => {
    delete process.env.CLAUDE_CUSTOM_HOME;
    fs.rmSync(repo, { recursive: true, force: true });
  });

  it("returns the snapshot the agent prints", async () => {
    const snapshot = { path: "/p.plist", exists: false, variables: [], conflicts: [] };
    writeAgent(`echo '${JSON.stringify(snapshot)}'`);

    const response = await GET();

    expect(response.status).toBe(200);
    expect(await response.json()).toEqual(snapshot);
  });

  it("answers 502 with the agent's stderr when the agent fails", async () => {
    writeAgent("echo 'plist is unreadable' >&2\nexit 1");

    const response = await GET();

    expect(response.status).toBe(502);
    expect(await response.json()).toEqual({ message: "plist is unreadable" });
  });
});
