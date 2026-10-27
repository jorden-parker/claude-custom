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

export type LogPath =
  { ok: true; path: string } | { ok: false; message: string };

export type LogSource = "server" | "launcher";

export function parseLogSource(value: string | null): LogSource | null {
  if (value === null || value === "server") {
    return "server";
  }
  return value === "launcher" ? "launcher" : null;
}

export async function readLogSource(
  source: LogSource,
  repoDir: string,
): Promise<LogPath> {
  return source === "launcher" ? readLauncherLogPath() : readLogPath(repoDir);
}

function readLauncherLogPath(): LogPath {
  const launcherLog = path.join(consoleStateDir(), "launcher.log");
  return fs.existsSync(launcherLog)
    ? { ok: true, path: launcherLog }
    : { ok: false, message: NO_LAUNCHER_LOG_MESSAGE };
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
