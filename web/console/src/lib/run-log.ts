import fs from "node:fs";
import os from "node:os";
import path from "node:path";

export type RunStatus = "running" | "ok" | "failed" | "cancelled" | "lost";

export type RunEvent = { kind: string; t?: number } & Record<string, unknown>;

export type RunSummary = {
  id: string;
  command: string;
  label: string;
  status: RunStatus;
  startedAt: string;
  seconds: number | null;
};

const RUN_ID_PATTERN = /^[0-9]{8}-[0-9]{6}-[a-z][a-z-]*-[0-9a-f]{4}$/;
const RUN_FILE_SUFFIX = ".jsonl";

export function runsDir(): string {
  const stateDir =
    process.env.CLAUDE_CONSOLE_STATE_DIR ||
    path.join(os.homedir(), ".local/share/claude-custom/console");
  return path.join(stateDir, "runs");
}

export function isRunId(id: string): boolean {
  return RUN_ID_PATTERN.test(id);
}

export function newRunId(command: string, now: Date, randomHex: string): string {
  const stamp = now.toISOString().slice(0, 19).replace(/[-:]/g, "").replace("T", "-");
  return `${stamp}-${command}-${randomHex}`;
}

export function resolveRunFile(id: string): string | null {
  return resolveRunFileIn(runsDir(), id);
}

export function resolveRunFileIn(directory: string, id: string): string | null {
  if (!isRunId(id)) {
    return null;
  }
  const file = path.resolve(directory, `${id}${RUN_FILE_SUFFIX}`);
  if (path.dirname(file) !== path.resolve(directory)) {
    return null;
  }
  return fs.existsSync(file) ? file : null;
}

export function isRunEndLine(line: string): boolean {
  return parseRunEvent(line)?.kind === "end";
}

export function parseRunEvents(text: string): RunEvent[] {
  return text
    .split("\n")
    .map(parseRunEvent)
    .filter((event): event is RunEvent => event !== null);
}

function parseRunEvent(line: string): RunEvent | null {
  try {
    const value: unknown = JSON.parse(line);
    return isRunEvent(value) ? value : null;
  } catch {
    return null;
  }
}

function isRunEvent(value: unknown): value is RunEvent {
  return (
    typeof value === "object" &&
    value !== null &&
    typeof (value as { kind?: unknown }).kind === "string"
  );
}

export function runStatus(events: RunEvent[], isAlive: (pid: number) => boolean): RunStatus {
  const end = events.find((event) => event.kind === "end");
  if (end) {
    if (end.cancelled === true) {
      return "cancelled";
    }
    return end.code === 0 ? "ok" : "failed";
  }
  const pid = events.find((event) => event.kind === "start")?.pid;
  return typeof pid === "number" && isAlive(pid) ? "running" : "lost";
}

export function isProcessAlive(pid: number): boolean {
  try {
    process.kill(pid, 0);
    return true;
  } catch (error) {
    return (error as NodeJS.ErrnoException).code === "EPERM";
  }
}

export function listRuns(
  directory: string = runsDir(),
  isAlive: (pid: number) => boolean = isProcessAlive,
): RunSummary[] {
  if (!fs.existsSync(directory)) {
    return [];
  }
  return fs
    .readdirSync(directory)
    .filter((name) => name.endsWith(RUN_FILE_SUFFIX) && isRunId(name.slice(0, -RUN_FILE_SUFFIX.length)))
    .sort()
    .reverse()
    .map((name) => summarizeRun(path.join(directory, name), name.slice(0, -RUN_FILE_SUFFIX.length), isAlive));
}

function summarizeRun(
  file: string,
  id: string,
  isAlive: (pid: number) => boolean,
): RunSummary {
  const events = parseRunEvents(fs.readFileSync(file, "utf8"));
  const start = events.find((event) => event.kind === "start");
  const last = events.at(-1);
  return {
    id,
    command: textField(start, "command"),
    label: textField(start, "label"),
    status: runStatus(events, isAlive),
    startedAt: textField(start, "started_at"),
    seconds: typeof last?.t === "number" ? last.t : null,
  };
}

function textField(event: RunEvent | undefined, field: string): string {
  const value = event?.[field];
  return typeof value === "string" ? value : "";
}
