import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { GET } from "./route";

vi.mock("next/server", async (importOriginal) => ({
  ...(await importOriginal<typeof import("next/server")>()),
  connection: async () => {},
}));

const FIT_LINE =
  "model 16.0 GiB + kv 8.0 GiB + embedding 0.6 GiB = 24.6 GiB of 24.2 GiB free";

type TempDirs = { home: string; repo: string };

function useTempDirs(): TempDirs {
  const dirs: TempDirs = { home: "", repo: "" };
  let previousHome: string | undefined;

  beforeEach(() => {
    dirs.repo = fs.mkdtempSync(path.join(os.tmpdir(), "lease-route-"));
    dirs.home = fs.mkdtempSync(path.join(os.tmpdir(), "lease-route-home-"));
    previousHome = process.env.HOME;
    process.env.HOME = dirs.home;
    process.env.CLAUDE_CUSTOM_HOME = dirs.repo;
    process.env.CLAUDE_CONSOLE_STATE_DIR = path.join(dirs.home, "state");
    fs.mkdirSync(process.env.CLAUDE_CONSOLE_STATE_DIR, { recursive: true });
  });

  afterEach(() => {
    process.env.HOME = previousHome;
    delete process.env.CLAUDE_CUSTOM_HOME;
    delete process.env.CLAUDE_CONSOLE_STATE_DIR;
    fs.rmSync(dirs.repo, { recursive: true, force: true });
    fs.rmSync(dirs.home, { recursive: true, force: true });
  });

  return dirs;
}

function writeLeaseScript(repo: string, body: string): void {
  fs.mkdirSync(path.join(repo, "bin"), { recursive: true });
  const script = path.join(repo, "bin", "ollama-lease");
  fs.writeFileSync(script, `#!/bin/sh\n${body}\n`);
  fs.chmodSync(script, 0o755);
}

describe("/api/lease", () => {
  const dirs = useTempDirs();

  it("returns the holders, the session rung and the fit line", async () => {
    writeLeaseScript(
      dirs.repo,
      "echo 'live session pid 4242 model qwen3.8-27b-cc rung embeddings-off'",
    );
    fs.writeFileSync(
      path.join(dirs.home, "state", "launcher.log"),
      `claude-ollama: memory fit: ${FIT_LINE}\n`,
    );

    const response = await GET();

    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({
      holders: [
        {
          state: "live",
          name: "session",
          pid: 4242,
          model: "qwen3.8-27b-cc",
          rung: "embeddings-off",
        },
      ],
      rung: "embeddings-off",
      fit: FIT_LINE,
    });
  });

  it("answers 502 with the script's stderr when holders fails", async () => {
    writeLeaseScript(dirs.repo, "echo 'ollama lease: lock held' >&2\nexit 1");

    const response = await GET();

    expect(response.status).toBe(502);
    expect(await response.json()).toEqual({
      message: "ollama lease: lock held",
    });
  });
});
