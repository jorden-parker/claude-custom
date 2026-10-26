import { CONSOLE_QUERIES } from "./console-commands";
import { runOnce } from "./run-once";

const LOG_PATH_TIMEOUT_MS = 5_000;
const LOG_PATH_MAX_BYTES = 4096;
const NO_LOG_MESSAGE = "No Ollama log found";

export type LogPath = { ok: true; path: string } | { ok: false; message: string };

export async function readLogPath(repoDir: string): Promise<LogPath> {
  const argv = CONSOLE_QUERIES.logPath.argv({}, repoDir);
  if (argv === null) {
    return { ok: false, message: NO_LOG_MESSAGE };
  }
  const result = await runOnce(argv, { timeoutMs: LOG_PATH_TIMEOUT_MS, maxBytes: LOG_PATH_MAX_BYTES });
  const path = result.stdout.trim();
  if (result.code !== 0 || path === "") {
    return { ok: false, message: result.stderr.trim() || NO_LOG_MESSAGE };
  }
  return { ok: true, path };
}
