import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import {
  latestFitLine,
  loadResidency,
  parseHolders,
  promoteSession,
  sessionRung,
} from "./lease";

const HOLDERS_TEXT = [
  "live session pid 4242 model qwen3.8-27b-cc rung context-down",
  "live embedding pid 4300 model qwen3-embedding:0.6b rung -",
  "stale review pid 99 model qwen3.6-35b-cc",
  "",
].join("\n");

const FIT_LINE =
  "model 16.0 GiB + kv 4.0 GiB + embedding 0.0 GiB = 20.0 GiB of 21.0 GiB free";

type TempDirs = { home: string; repo: string };

function useTempDirs(): TempDirs {
  const dirs: TempDirs = { home: "", repo: "" };
  let previous: { home?: string; state?: string };

  beforeEach(() => {
    dirs.home = fs.mkdtempSync(path.join(os.tmpdir(), "lease-home-"));
    dirs.repo = fs.mkdtempSync(path.join(os.tmpdir(), "lease-repo-"));
    previous = {
      home: process.env.HOME,
      state: process.env.CLAUDE_CONSOLE_STATE_DIR,
    };
    process.env.HOME = dirs.home;
    process.env.CLAUDE_CONSOLE_STATE_DIR = path.join(dirs.home, "state");
    fs.mkdirSync(process.env.CLAUDE_CONSOLE_STATE_DIR, { recursive: true });
  });

  afterEach(() => {
    process.env.HOME = previous.home;
    if (previous.state === undefined) {
      delete process.env.CLAUDE_CONSOLE_STATE_DIR;
    } else {
      process.env.CLAUDE_CONSOLE_STATE_DIR = previous.state;
    }
    fs.rmSync(dirs.home, { recursive: true, force: true });
    fs.rmSync(dirs.repo, { recursive: true, force: true });
  });

  return dirs;
}

function writeLeaseScript(repo: string, body: string): void {
  fs.mkdirSync(path.join(repo, "bin"), { recursive: true });
  const script = path.join(repo, "bin", "ollama-lease");
  fs.writeFileSync(script, `#!/bin/sh\n${body}\n`);
  fs.chmodSync(script, 0o755);
}

const RELAUNCH_MODULE = path.resolve(
  __dirname,
  "../../../../shared/relaunch_dir.py",
);

function linkRelaunchModule(repo: string): void {
  fs.mkdirSync(path.join(repo, "shared"), { recursive: true });
  fs.symlinkSync(RELAUNCH_MODULE, path.join(repo, "shared", "relaunch_dir.py"));
}

function relaunchDir(home: string, pid: number): string {
  return path.join(home, ".claude-ollama", "relaunch", String(pid));
}

describe("parseHolders", () => {
  it("reads live and stale holders from the holders output", () => {
    expect(parseHolders(HOLDERS_TEXT)).toEqual([
      {
        state: "live",
        name: "session",
        pid: 4242,
        model: "qwen3.8-27b-cc",
        rung: "context-down",
      },
      {
        state: "live",
        name: "embedding",
        pid: 4300,
        model: "qwen3-embedding:0.6b",
        rung: null,
      },
      {
        state: "stale",
        name: "review",
        pid: 99,
        model: "qwen3.6-35b-cc",
        rung: null,
      },
    ]);
  });

  it("skips lines that are not holder lines", () => {
    expect(parseHolders("ollama lease: /tmp/lease.lock is held\n")).toEqual([]);
  });
});

describe("sessionRung", () => {
  it("is the live session holder's rung", () => {
    expect(sessionRung(parseHolders(HOLDERS_TEXT))).toBe("context-down");
  });

  it("is null without a live session", () => {
    expect(
      sessionRung(parseHolders("stale session pid 1 model m\n")),
    ).toBeNull();
  });
});

describe("latestFitLine", () => {
  it("keeps the newest memory fit line without its prefix", () => {
    const log = [
      "claude-ollama: launch 27b in /repo at 2026-11-02T10:00:00Z",
      "claude-ollama: memory fit: model 16.0 GiB + kv 8.0 GiB + embedding 0.6 GiB = 24.6 GiB of 28.9 GiB free",
      "claude-ollama: starting claude",
      "claude-ollama: memory fit: model 16.0 GiB + kv 8.0 GiB + embedding 0.6 GiB = 24.6 GiB of 24.2 GiB free",
      "claude-ollama: ladder embeddings-off: does not fit with the embedding model (0.4 GiB short)",
    ].join("\n");
    expect(latestFitLine(log)).toBe(
      "model 16.0 GiB + kv 8.0 GiB + embedding 0.6 GiB = 24.6 GiB of 24.2 GiB free",
    );
  });

  it("is null when no launch measured the fit", () => {
    expect(latestFitLine("claude-ollama: starting claude\n")).toBeNull();
  });
});

describe("loadResidency", () => {
  const dirs = useTempDirs();

  it("loads the holders, the session rung and the newest fit line", async () => {
    writeLeaseScript(
      dirs.repo,
      `[ "$1" = holders ] || exit 2\ncat <<'HOLDERS'\n${HOLDERS_TEXT}HOLDERS`,
    );
    fs.writeFileSync(
      path.join(dirs.home, "state", "launcher.log"),
      `claude-ollama: memory fit: ${FIT_LINE}\n`,
    );

    expect(await loadResidency(dirs.repo)).toEqual({
      ok: true,
      residency: {
        holders: parseHolders(HOLDERS_TEXT),
        rung: "context-down",
        fit: FIT_LINE,
      },
    });
  });

  it("reports no fit line without a launcher log", async () => {
    writeLeaseScript(dirs.repo, "exit 0");

    expect(await loadResidency(dirs.repo)).toEqual({
      ok: true,
      residency: { holders: [], rung: null, fit: null },
    });
  });

  it("fails with the script's stderr when holders fails", async () => {
    writeLeaseScript(dirs.repo, "echo 'ollama lease: lock held' >&2\nexit 1");

    expect(await loadResidency(dirs.repo)).toEqual({
      ok: false,
      message: "ollama lease: lock held",
    });
  });
});

describe("promoteSession", () => {
  const dirs = useTempDirs();

  beforeEach(() => {
    linkRelaunchModule(dirs.repo);
  });

  it("writes ladder-up into the live session's relaunch dir", async () => {
    const target = relaunchDir(dirs.home, 4242);
    fs.mkdirSync(target, { recursive: true });

    const result = await promoteSession(
      dirs.repo,
      parseHolders(HOLDERS_TEXT),
      "context-down",
    );

    expect(result).toEqual({ ok: true, pid: 4242, rung: "context-down" });
    const ladderUp = path.join(target, "ladder-up");
    expect(JSON.parse(fs.readFileSync(ladderUp, "utf8"))).toEqual({
      rung: "context-down",
      reason: "promoted from the console",
    });
    expect(fs.statSync(ladderUp).mode & 0o777).toBe(0o600);
  });

  it("refuses without a live session", async () => {
    expect(await promoteSession(dirs.repo, [], "context-down")).toEqual({
      ok: false,
      message: "No live session lease to promote",
    });
  });

  it("refuses a rung the session is not on", async () => {
    fs.mkdirSync(relaunchDir(dirs.home, 4242), { recursive: true });

    expect(
      await promoteSession(
        dirs.repo,
        parseHolders(HOLDERS_TEXT),
        "embeddings-off",
      ),
    ).toEqual({
      ok: false,
      message: "The session is on the context-down rung, not embeddings-off",
    });
  });

  it("refuses a session that has no relaunch dir", async () => {
    const missing = relaunchDir(dirs.home, 4242);

    expect(
      await promoteSession(
        dirs.repo,
        parseHolders(HOLDERS_TEXT),
        "context-down",
      ),
    ).toEqual({
      ok: false,
      message: `relaunch dir: no relaunch dir at ${missing}; that session cannot relaunch`,
    });
  });
});
