import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { loadServerSnapshot } from "./server-snapshot";

describe("loadServerSnapshot", () => {
  let repo: string;

  const writeAgent = (body: string) => {
    fs.mkdirSync(path.join(repo, "bin"), { recursive: true });
    const agent = path.join(repo, "bin", "ollama-agent");
    fs.writeFileSync(agent, `#!/bin/sh\n${body}\n`);
    fs.chmodSync(agent, 0o755);
  };

  beforeEach(() => {
    repo = fs.mkdtempSync(path.join(os.tmpdir(), "server-snapshot-"));
  });

  afterEach(() => {
    fs.rmSync(repo, { recursive: true, force: true });
  });

  it("returns the snapshot that ollama-agent -json prints", async () => {
    const snapshot = { path: "/p.plist", exists: true, variables: [], conflicts: [] };
    writeAgent(`echo '${JSON.stringify(snapshot)}'`);

    expect(await loadServerSnapshot(repo)).toEqual({ ok: true, snapshot });
  });

  it("returns the stderr text when the agent exits non-zero", async () => {
    writeAgent("echo 'plist is unreadable' >&2\nexit 1");

    expect(await loadServerSnapshot(repo)).toEqual({ ok: false, message: "plist is unreadable" });
  });

  it("fails when the agent prints something that is not JSON", async () => {
    writeAgent("echo 'not json'");

    const result = await loadServerSnapshot(repo);
    expect(result.ok).toBe(false);
  });

  it("fails when there is no agent to run", async () => {
    const result = await loadServerSnapshot(repo);
    expect(result.ok).toBe(false);
  });
});
