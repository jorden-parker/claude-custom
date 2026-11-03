import fs from "node:fs";
import path from "node:path";
import { runOnce } from "./run-once";
import type { LeaseHolder, Residency } from "./residency";
import { consoleStateDir } from "./state-dir";

export type ResidencyResult =
  { ok: true; residency: Residency } | { ok: false; message: string };

export type PromoteResult =
  { ok: true; pid: number; rung: string } | { ok: false; message: string };

const HOLDERS_TIMEOUT_MS = 10_000;
const HOLDERS_MAX_BYTES = 64 * 1024;
const LAUNCHER_LOG_MAX_BYTES = 1024 * 1024;
const FIT_PREFIX = "claude-ollama: memory fit: ";
const SESSION_HOLDER = "session";
const RELAUNCH_TIMEOUT_MS = 10_000;
const RELAUNCH_MAX_BYTES = 16 * 1024;
const PYTHON = "python3";
const PROMOTE_REASON = "promoted from the console";
const HOLDER_LINE =
  /^(live|stale) (\S+) pid (\d+) model (\S+)(?: rung (\S+))?$/;

export function parseHolders(text: string): LeaseHolder[] {
  return text
    .split("\n")
    .map(parseHolderLine)
    .filter((holder): holder is LeaseHolder => holder !== null);
}

function parseHolderLine(line: string): LeaseHolder | null {
  const match = HOLDER_LINE.exec(line.trim());
  if (match === null) {
    return null;
  }
  const [, state, name, pid, model, rung] = match;
  return {
    state: state as LeaseHolder["state"],
    name,
    pid: Number(pid),
    model: dashAsNull(model),
    rung: dashAsNull(rung),
  };
}

function dashAsNull(value: string | undefined): string | null {
  return value === undefined || value === "-" ? null : value;
}

export function sessionRung(holders: LeaseHolder[]): string | null {
  return liveSession(holders)?.rung ?? null;
}

function liveSession(holders: LeaseHolder[]): LeaseHolder | undefined {
  return holders.find(
    (holder) => holder.state === "live" && holder.name === SESSION_HOLDER,
  );
}

export function latestFitLine(log: string): string | null {
  const fitLines = log
    .split("\n")
    .filter((line) => line.startsWith(FIT_PREFIX));
  const newest = fitLines.at(-1);
  return newest === undefined ? null : newest.slice(FIT_PREFIX.length);
}

export async function loadResidency(repoDir: string): Promise<ResidencyResult> {
  const result = await runOnce([`${repoDir}/bin/ollama-lease`, "holders"], {
    timeoutMs: HOLDERS_TIMEOUT_MS,
    maxBytes: HOLDERS_MAX_BYTES,
  });
  if (result.code !== 0) {
    return {
      ok: false,
      message:
        result.stderr.trim() || `ollama-lease holders exited ${result.code}`,
    };
  }
  const holders = parseHolders(result.stdout);
  return {
    ok: true,
    residency: {
      holders,
      rung: sessionRung(holders),
      fit: latestFitLine(readLauncherLogTail()),
    },
  };
}

function readLauncherLogTail(): string {
  const launcherLog = path.join(consoleStateDir(), "launcher.log");
  let handle: number;
  try {
    handle = fs.openSync(launcherLog, "r");
  } catch {
    return "";
  }
  try {
    const size = fs.fstatSync(handle).size;
    const length = Math.min(size, LAUNCHER_LOG_MAX_BYTES);
    const buffer = Buffer.alloc(length);
    fs.readSync(handle, buffer, 0, length, size - length);
    return buffer.toString("utf8");
  } finally {
    fs.closeSync(handle);
  }
}

export async function promoteSession(
  repoDir: string,
  holders: LeaseHolder[],
  rung: string,
): Promise<PromoteResult> {
  const session = liveSession(holders);
  if (session === undefined) {
    return { ok: false, message: "No live session lease to promote" };
  }
  if (session.rung !== rung) {
    return {
      ok: false,
      message: `The session is on the ${session.rung ?? "no"} rung, not ${rung}`,
    };
  }
  const result = await runOnce(
    [
      PYTHON,
      path.join(repoDir, "shared", "relaunch_dir.py"),
      "request",
      "ladder-up",
      "--pid",
      String(session.pid),
      JSON.stringify({ rung, reason: PROMOTE_REASON }),
    ],
    { timeoutMs: RELAUNCH_TIMEOUT_MS, maxBytes: RELAUNCH_MAX_BYTES },
  );
  if (result.code !== 0) {
    const reason =
      result.stderr.trim() || `relaunch_dir.py exited ${result.code}`;
    return { ok: false, message: `${reason}; that session cannot relaunch` };
  }
  return { ok: true, pid: session.pid, rung };
}
