import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { readLogPath } from "./log-path";

describe("readLogPath", () => {
  let repo: string;

  beforeEach(() => {
    repo = fs.mkdtempSync(path.join(os.tmpdir(), "log-path-"));
    fs.mkdirSync(path.join(repo, "bin"));
  });

  afterEach(() => {
    fs.rmSync(repo, { recursive: true, force: true });
  });

  function writeLauncher(body: string) {
    fs.writeFileSync(path.join(repo, "bin", "claude-ollama"), `#!/bin/sh\n${body}\n`, { mode: 0o755 });
  }

  it("returns the path the launcher prints", async () => {
    writeLauncher("echo /var/log/ollama.log");
    expect(await readLogPath(repo)).toEqual({ ok: true, path: "/var/log/ollama.log" });
  });

  it("returns the launcher's message when there is no log", async () => {
    writeLauncher("echo 'no Ollama log found' >&2\nexit 1");
    expect(await readLogPath(repo)).toEqual({ ok: false, message: "no Ollama log found" });
  });

  it("returns a fixed message when the launcher prints nothing", async () => {
    writeLauncher("exit 0");
    expect(await readLogPath(repo)).toEqual({ ok: false, message: "No Ollama log found" });
  });
});
