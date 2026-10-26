import { spawn } from "node:child_process";
import { randomBytes } from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { findCommand, type CommandParams } from "./console-commands";
import { consoleRepoDir } from "./sizes";
import { parseRunEvents } from "./run-event";
import {
  isProcessAlive,
  listRuns,
  newRunId,
  resolveRunFileIn,
  runsDir,
  runStatus,
  type RunSummary,
} from "./run-log";

const WAIT_FOR_FILE_MS = 2000;
const WAIT_STEP_MS = 50;

export type StartDeps = {
  repoDir: string;
  runsDir: string;
  now: () => Date;
  randomHex: () => string;
  spawnDetached: (command: string, args: string[]) => void;
  listRuns: () => RunSummary[];
  waitForFile: (file: string) => Promise<boolean>;
};

export type CancelDeps = {
  runsDir: string;
  isAlive: (pid: number) => boolean;
  kill: (pid: number, signal: NodeJS.Signals) => void;
};

export type StartResult =
  | { ok: true; id: string }
  | { ok: false; status: 400 | 409 | 500; message: string };

export type CancelResult =
  | { ok: true }
  | { ok: false; status: 404 | 409; message: string };

export async function startRun(
  name: string,
  params: CommandParams,
  deps: StartDeps,
): Promise<StartResult> {
  const command = findCommand(name);
  if (!command) {
    return { ok: false, status: 400, message: "Unknown command or parameters" };
  }
  const argv = command.argv(params, deps.repoDir);
  if (!argv) {
    return { ok: false, status: 400, message: "Unknown command or parameters" };
  }
  if (deps.listRuns().some((run) => run.command === name && run.status === "running")) {
    return { ok: false, status: 409, message: `${command.label(params)} is already running` };
  }
  const id = newRunId(name, deps.now(), deps.randomHex());
  const file = path.join(deps.runsDir, `${id}.jsonl`);
  deps.spawnDetached(`${deps.repoDir}/bin/console-run`, [
    "--log",
    file,
    "--id",
    id,
    "--command",
    name,
    "--label",
    command.label(params),
    "--",
    ...argv,
  ]);
  if (!(await deps.waitForFile(file))) {
    return { ok: false, status: 500, message: "The run did not start" };
  }
  return { ok: true, id };
}

export function cancelRun(id: string, deps: CancelDeps): CancelResult {
  const file = resolveRunFileIn(deps.runsDir, id);
  if (!file) {
    return { ok: false, status: 404, message: "Run not found" };
  }
  const events = parseRunEvents(fs.readFileSync(file, "utf8"));
  const pid = events.find((event) => event.kind === "start")?.pid;
  if (typeof pid !== "number" || runStatus(events, deps.isAlive) !== "running") {
    return { ok: false, status: 409, message: "Run is not running" };
  }
  deps.kill(pid, "SIGTERM");
  return { ok: true };
}

export function startDeps(): StartDeps {
  return {
    repoDir: consoleRepoDir(),
    runsDir: runsDir(),
    now: () => new Date(),
    randomHex: () => randomBytes(2).toString("hex"),
    spawnDetached: spawnRunnerDetached,
    listRuns: () => listRuns(),
    waitForFile,
  };
}

export function cancelDeps(): CancelDeps {
  return { runsDir: runsDir(), isAlive: isProcessAlive, kill: (pid, signal) => process.kill(pid, signal) };
}

function spawnRunnerDetached(command: string, args: string[]): void {
  const child = spawn(command, args, { detached: true, stdio: "ignore" });
  child.on("error", () => undefined);
  child.unref();
}

async function waitForFile(file: string): Promise<boolean> {
  const deadline = Date.now() + WAIT_FOR_FILE_MS;
  while (Date.now() < deadline) {
    if (fs.existsSync(file)) {
      return true;
    }
    await new Promise((resolve) => setTimeout(resolve, WAIT_STEP_MS));
  }
  return fs.existsSync(file);
}
