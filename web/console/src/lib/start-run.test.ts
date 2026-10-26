import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { afterEach, beforeEach, describe, expect, it, vi, type Mock } from "vitest";
import { cancelRun, startRun, type CancelDeps, type StartDeps } from "./start-run";
import type { RunSummary } from "./run-log";

const RUN_ID = "20261026-101500-doctor-3fa9";

describe("startRun", () => {
  let repo: string;
  let runsDirectory: string;
  let spawnDetached: Mock<StartDeps["spawnDetached"]>;

  beforeEach(() => {
    repo = fs.mkdtempSync(path.join(os.tmpdir(), "start-run-repo-"));
    fs.mkdirSync(path.join(repo, "ollama"));
    fs.writeFileSync(path.join(repo, "ollama", "settings.27b.json"), "{}");
    fs.writeFileSync(path.join(repo, "ollama", "Modelfile.27b"), "");
    runsDirectory = fs.mkdtempSync(path.join(os.tmpdir(), "start-run-runs-"));
    spawnDetached = vi.fn<StartDeps["spawnDetached"]>();
  });

  afterEach(() => {
    fs.rmSync(repo, { recursive: true, force: true });
    fs.rmSync(runsDirectory, { recursive: true, force: true });
  });

  function depsWith(overrides: Partial<StartDeps> = {}): StartDeps {
    return {
      repoDir: repo,
      runsDir: runsDirectory,
      now: () => new Date("2026-10-26T10:15:00Z"),
      randomHex: () => "3fa9",
      spawnDetached,
      listRuns: () => [],
      waitForFile: async () => true,
      ...overrides,
    };
  }

  it("starts the runner with the command's argv and returns the id", async () => {
    const result = await startRun("doctor", { size: "27b" }, depsWith());

    expect(result).toEqual({ ok: true, id: RUN_ID });
    expect(spawnDetached).toHaveBeenCalledWith(`${repo}/bin/console-run`, [
      "--log",
      path.join(runsDirectory, `${RUN_ID}.jsonl`),
      "--id",
      RUN_ID,
      "--command",
      "doctor",
      "--label",
      "Doctor (27b)",
      "--",
      `${repo}/bin/claude-ollama`,
      "doctor",
      "27b",
    ]);
  });

  it("refuses an unknown command without starting anything", async () => {
    const result = await startRun("pull", {}, depsWith());

    expect(result).toEqual({ ok: false, status: 400, message: "Unknown command or parameters" });
    expect(spawnDetached).not.toHaveBeenCalled();
  });

  it("refuses parameters the command does not accept", async () => {
    const result = await startRun("doctor", { size: "27b; rm -rf ~" }, depsWith());

    expect(result).toMatchObject({ ok: false, status: 400 });
    expect(spawnDetached).not.toHaveBeenCalled();
  });

  it("refuses a second run of the same command while one is running", async () => {
    const running: RunSummary = {
      id: "20261026-100000-doctor-aaaa",
      command: "doctor",
      label: "Doctor (27b)",
      status: "running",
      startedAt: "",
      seconds: 1,
    };
    const result = await startRun("doctor", { size: "27b" }, depsWith({ listRuns: () => [running] }));

    expect(result).toMatchObject({ ok: false, status: 409 });
    expect(spawnDetached).not.toHaveBeenCalled();
  });

  it("reports a failure when the log never appears", async () => {
    const result = await startRun("doctor", { size: "27b" }, depsWith({ waitForFile: async () => false }));

    expect(result).toMatchObject({ ok: false, status: 500 });
  });
});

describe("cancelRun", () => {
  let runsDirectory: string;
  let kill: Mock<CancelDeps["kill"]>;

  beforeEach(() => {
    runsDirectory = fs.mkdtempSync(path.join(os.tmpdir(), "cancel-run-"));
    kill = vi.fn<CancelDeps["kill"]>();
  });

  afterEach(() => {
    fs.rmSync(runsDirectory, { recursive: true, force: true });
  });

  function writeRun(lines: object[]) {
    const body = lines.map((line) => JSON.stringify(line)).join("\n") + "\n";
    fs.writeFileSync(path.join(runsDirectory, `${RUN_ID}.jsonl`), body);
  }

  const startLine = { t: 0, kind: "start", id: RUN_ID, command: "doctor", label: "Doctor (27b)", argv: [], pid: 4242, started_at: "2026-10-26T10:15:00Z" };

  it("sends SIGTERM to the runner pid of a running run", () => {
    writeRun([startLine]);

    const result = cancelRun(RUN_ID, { runsDir: runsDirectory, isAlive: () => true, kill });

    expect(result).toEqual({ ok: true });
    expect(kill).toHaveBeenCalledWith(4242, "SIGTERM");
  });

  it("refuses a run that has already ended", () => {
    writeRun([startLine, { t: 3, kind: "end", code: 0, cancelled: false }]);

    const result = cancelRun(RUN_ID, { runsDir: runsDirectory, isAlive: () => true, kill });

    expect(result).toMatchObject({ ok: false, status: 409 });
    expect(kill).not.toHaveBeenCalled();
  });

  it("refuses a lost run whose runner is gone", () => {
    writeRun([startLine]);

    const result = cancelRun(RUN_ID, { runsDir: runsDirectory, isAlive: () => false, kill });

    expect(result).toMatchObject({ ok: false, status: 409 });
    expect(kill).not.toHaveBeenCalled();
  });

  it("returns 404 for an id that is not a run", () => {
    const result = cancelRun("../../etc", { runsDir: runsDirectory, isAlive: () => true, kill });

    expect(result).toMatchObject({ ok: false, status: 404 });
    expect(kill).not.toHaveBeenCalled();
  });
});
