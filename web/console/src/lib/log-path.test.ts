import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { parseLogSource, readLogPath, readLogSource } from "./log-path";

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
    fs.writeFileSync(
      path.join(repo, "bin", "claude-ollama"),
      `#!/bin/sh\n${body}\n`,
      { mode: 0o755 },
    );
  }

  it("returns the path the launcher prints", async () => {
    writeLauncher("echo /var/log/ollama.log");
    expect(await readLogPath(repo)).toEqual({
      ok: true,
      path: "/var/log/ollama.log",
    });
  });

  it("returns the launcher's message when there is no log", async () => {
    writeLauncher("echo 'no Ollama log found' >&2\nexit 1");
    expect(await readLogPath(repo)).toEqual({
      ok: false,
      message: "no Ollama log found",
    });
  });

  it("returns a fixed message when the launcher prints nothing", async () => {
    writeLauncher("exit 0");
    expect(await readLogPath(repo)).toEqual({
      ok: false,
      message: "No Ollama log found",
    });
  });
});

describe("parseLogSource", () => {
  it("defaults to the server log", () => {
    expect(parseLogSource(null)).toBe("server");
  });

  it("accepts the server and launcher logs", () => {
    expect(parseLogSource("server")).toBe("server");
    expect(parseLogSource("launcher")).toBe("launcher");
  });

  it("rejects any other source", () => {
    expect(parseLogSource("../etc/passwd")).toBeNull();
  });
});

describe("readLogSource", () => {
  let stateDir: string;

  beforeEach(() => {
    stateDir = fs.mkdtempSync(path.join(os.tmpdir(), "log-source-"));
    process.env.CLAUDE_CONSOLE_STATE_DIR = stateDir;
  });

  afterEach(() => {
    delete process.env.CLAUDE_CONSOLE_STATE_DIR;
    fs.rmSync(stateDir, { recursive: true, force: true });
  });

  it("returns the launcher log in the console state dir", async () => {
    fs.writeFileSync(
      path.join(stateDir, "launcher.log"),
      "claude-ollama: launch 27b\n",
    );
    expect(await readLogSource("launcher", "/no/repo")).toEqual({
      ok: true,
      path: path.join(stateDir, "launcher.log"),
    });
  });

  it("says the launcher log starts with the next launch when it is missing", async () => {
    expect(await readLogSource("launcher", "/no/repo")).toEqual({
      ok: false,
      message:
        "No launcher log yet; it starts with the next claude-ollama launch",
    });
  });
});
