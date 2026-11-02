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

  it("accepts the server and launcher logs and the incidents", () => {
    expect(parseLogSource("server")).toBe("server");
    expect(parseLogSource("launcher")).toBe("launcher");
    expect(parseLogSource("incidents")).toBe("incidents");
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

  function writeCurrentIncidents(named: string, body: string | null) {
    const incidentsDir = path.join(stateDir, "incidents");
    fs.mkdirSync(incidentsDir, { recursive: true });
    fs.writeFileSync(path.join(incidentsDir, "current"), `${named}\n`);
    if (body !== null) {
      fs.writeFileSync(path.join(incidentsDir, path.basename(named)), body);
    }
  }

  it("returns the incidents file named by incidents/current", async () => {
    const incidents = path.join(stateDir, "incidents", "20261102-1.jsonl");
    writeCurrentIncidents(incidents, '{"cause":"aborted"}\n');
    expect(await readLogSource("incidents", "/no/repo")).toEqual({
      ok: true,
      path: incidents,
    });
  });

  it("says the watcher starts with the next launch when there is no current file", async () => {
    expect(await readLogSource("incidents", "/no/repo")).toEqual({
      ok: false,
      message:
        "No incidents file yet; the next claude-ollama launch starts the watcher",
    });
  });

  it("refuses a current file that names a file outside the incidents folder", async () => {
    fs.writeFileSync(path.join(stateDir, "launcher.log"), "secret\n");
    writeCurrentIncidents(path.join(stateDir, "launcher.log"), null);
    expect(await readLogSource("incidents", "/no/repo")).toEqual({
      ok: false,
      message:
        "No incidents file yet; the next claude-ollama launch starts the watcher",
    });
  });

  it("refuses a current file whose incidents file is gone", async () => {
    writeCurrentIncidents(path.join(stateDir, "incidents", "gone.jsonl"), null);
    expect((await readLogSource("incidents", "/no/repo")).ok).toBe(false);
  });
});
