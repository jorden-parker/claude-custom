import { execFile, type ExecFileException } from "node:child_process";

export type RunOnceOptions = { timeoutMs: number; maxBytes: number };
export type RunOnceResult = { code: number; stdout: string; stderr: string };

const TIMEOUT_EXIT_CODE = 124;
const SPAWN_FAILURE_EXIT_CODE = 127;

export function runOnce(
  [command, ...args]: readonly string[],
  { timeoutMs, maxBytes }: RunOnceOptions,
): Promise<RunOnceResult> {
  return new Promise((resolve) => {
    execFile(
      command,
      args,
      { timeout: timeoutMs, maxBuffer: maxBytes, env: process.env },
      (error, stdout, stderr) => {
        resolve({ code: exitCodeOf(error), stdout, stderr });
      },
    );
  });
}

function exitCodeOf(error: ExecFileException | null): number {
  if (error === null) {
    return 0;
  }
  if (typeof error.code === "number") {
    return error.code;
  }
  return error.killed ? TIMEOUT_EXIT_CODE : SPAWN_FAILURE_EXIT_CODE;
}
