import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { GET } from "./route";

vi.mock("next/server", async (importOriginal) => ({
  ...(await importOriginal<typeof import("next/server")>()),
  connection: async () => {},
}));

const REPORT = {
  since_days: 14,
  requests: 26,
  rows: [
    {
      tool: "WebFetch",
      schema_bytes: 2048,
      requests: 26,
      session_bytes: 53248,
      calls: 0,
      bytes_per_call: null,
    },
  ],
  protected: ["Bash"],
  protected_source: "built-in list in bin/tool-budget",
  suggest: { drop: ["WebFetch"], keep: [], saves_bytes: 2048 },
};

type TempDirs = { repo: string; state: string };

function useTempDirs(): TempDirs {
  const dirs: TempDirs = { repo: "", state: "" };

  beforeEach(() => {
    dirs.repo = fs.mkdtempSync(path.join(os.tmpdir(), "tool-budget-route-"));
    dirs.state = fs.mkdtempSync(path.join(os.tmpdir(), "tool-budget-state-"));
    process.env.CLAUDE_CUSTOM_HOME = dirs.repo;
    process.env.CLAUDE_CONSOLE_STATE_DIR = dirs.state;
    process.env.CLAUDE_TOOL_TELEMETRY = path.join(dirs.state, "calls.jsonl");
  });

  afterEach(() => {
    delete process.env.CLAUDE_CUSTOM_HOME;
    delete process.env.CLAUDE_CONSOLE_STATE_DIR;
    delete process.env.CLAUDE_TOOL_TELEMETRY;
    fs.rmSync(dirs.repo, { recursive: true, force: true });
    fs.rmSync(dirs.state, { recursive: true, force: true });
  });

  return dirs;
}

function writeBudgetScript(repo: string, body: string): void {
  fs.mkdirSync(path.join(repo, "bin"), { recursive: true });
  const script = path.join(repo, "bin", "tool-budget");
  fs.writeFileSync(script, `#!/bin/sh\n${body}\n`);
  fs.chmodSync(script, 0o755);
}

describe("/api/tool-budget", () => {
  const dirs = useTempDirs();

  it("runs the script on the state dir's proxy log with --json and returns the report", async () => {
    writeBudgetScript(
      dirs.repo,
      `echo "$@" > "${dirs.state}/args"\necho '${JSON.stringify(REPORT)}'`,
    );

    const response = await GET();

    expect(response.status).toBe(200);
    expect(await response.json()).toEqual(REPORT);
    expect(fs.readFileSync(path.join(dirs.state, "args"), "utf8").trim()).toBe(
      `--proxy-log ${dirs.state}/proxy/requests.jsonl --telemetry ${dirs.state}/calls.jsonl --json`,
    );
  });

  it("answers 502 with the script's stderr when it fails", async () => {
    writeBudgetScript(dirs.repo, "echo 'tool-budget: boom' >&2\nexit 1");

    const response = await GET();

    expect(response.status).toBe(502);
    expect(await response.json()).toEqual({ message: "tool-budget: boom" });
  });
});
