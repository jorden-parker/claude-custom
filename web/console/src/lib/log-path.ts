import fs from "node:fs";
import path from "node:path";
import { CONSOLE_QUERIES } from "./console-commands";
import { runOnce } from "./run-once";
import { consoleStateDir } from "./state-dir";

const LOG_PATH_TIMEOUT_MS = 5_000;
const LOG_PATH_MAX_BYTES = 4096;
const NO_LOG_MESSAGE = "No Ollama log found";
const NO_LAUNCHER_LOG_MESSAGE =
  "No launcher log yet; it starts with the next claude-ollama launch";
const NO_INCIDENTS_MESSAGE =
  "No incidents file yet; the next claude-ollama launch starts the watcher";

export type LogPath =
  { ok: true; path: string } | { ok: false; message: string };

const LOG_SOURCES = ["server", "launcher", "incidents"] as const;

export type LogSource = (typeof LOG_SOURCES)[number];

export function parseLogSource(value: string | null): LogSource | null {
  if (value === null) {
    return "server";
  }
  const source = LOG_SOURCES.find((candidate) => candidate === value);
  return source ?? null;
}

export async function readLogSource(
  source: LogSource,
  repoDir: string,
): Promise<LogPath> {
  if (source === "launcher") {
    return readLauncherLogPath();
  }
  if (source === "incidents") {
    return readIncidentsPath();
  }
  return readLogPath(repoDir);
}

function readLauncherLogPath(): LogPath {
  const launcherLog = path.join(consoleStateDir(), "launcher.log");
  return fs.existsSync(launcherLog)
    ? { ok: true, path: launcherLog }
    : { ok: false, message: NO_LAUNCHER_LOG_MESSAGE };
}

function readIncidentsPath(): LogPath {
  const incidentsDir = path.join(consoleStateDir(), "incidents");
  const current = readCurrentIncidentsFile(incidentsDir);
  if (current === null || !fs.existsSync(current)) {
    return { ok: false, message: NO_INCIDENTS_MESSAGE };
  }
  return { ok: true, path: current };
}

function readCurrentIncidentsFile(incidentsDir: string): string | null {
  let named: string;
  try {
    named = fs.readFileSync(path.join(incidentsDir, "current"), "utf8").trim();
  } catch {
    return null;
  }
  const resolved = path.resolve(incidentsDir, named);
  const insideIncidents =
    path.dirname(resolved) === path.resolve(incidentsDir) &&
    resolved.endsWith(".jsonl");
  return insideIncidents ? resolved : null;
}

export async function readLogPath(repoDir: string): Promise<LogPath> {
  const argv = CONSOLE_QUERIES.logPath.argv({}, repoDir);
  if (argv === null) {
    return { ok: false, message: NO_LOG_MESSAGE };
  }
  const result = await runOnce(argv, {
    timeoutMs: LOG_PATH_TIMEOUT_MS,
    maxBytes: LOG_PATH_MAX_BYTES,
  });
  const path = result.stdout.trim();
  if (result.code !== 0 || path === "") {
    return { ok: false, message: result.stderr.trim() || NO_LOG_MESSAGE };
  }
  return { ok: true, path };
}
