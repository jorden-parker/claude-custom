import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

export type HistoryEntry = {
  id: string;
  at: string;
  kind: string;
  path: string;
  source: string;
  before: string | null;
  after: string;
};

export type HistoryChange = {
  entry: HistoryEntry;
  before: string | null;
  after: string;
};

export type NewChange = {
  kind: string;
  path: string;
  before: string | null;
  after: string;
  source: string;
};

export type RestoreResult =
  | { ok: true; entry: HistoryEntry | null }
  | { ok: false; status: 404 | 409; message: string };

const ID_PATTERN = /^[0-9]{8}-[0-9]{6}-[a-z][a-z-]*-[0-9a-f]{4}$/;
const KIND_PATTERN = /^[a-z][a-z-]*$/;
const INDEX_NAME = "index.jsonl";
const FOLDER_MODE = 0o700;
const FILE_MODE = 0o600;
const DEFAULT_MODE = 0o644;

export function historyDir(): string {
  const stateDir =
    process.env.CLAUDE_CONSOLE_STATE_DIR ||
    path.join(os.homedir(), ".local/share/claude-custom/console");
  return path.join(stateDir, "history");
}

export function listHistory(): HistoryEntry[] {
  return readIndex().reverse();
}

export function loadChange(id: string): HistoryChange | null {
  if (!ID_PATTERN.test(id)) {
    return null;
  }
  const entry = readIndex().find((candidate) => candidate.id === id);
  if (!entry) {
    return null;
  }
  return {
    entry,
    before: entry.before === null ? null : readData(entry.before),
    after: readData(entry.after),
  };
}

export function recordChange(change: NewChange): HistoryEntry | null {
  if (process.env.CLAUDE_CUSTOM_HISTORY === "off") {
    return null;
  }
  if (change.before !== null && change.before === change.after) {
    return null;
  }
  if (!KIND_PATTERN.test(change.kind)) {
    throw new Error(`invalid history kind ${change.kind}`);
  }
  const folder = historyDir();
  ensureFolder(folder);
  const entry = newEntry(change, new Date());
  if (change.before !== null && entry.before !== null) {
    writeNewFile(path.join(folder, entry.before), change.before);
  }
  writeNewFile(path.join(folder, entry.after), change.after);
  appendIndex(folder, entry);
  return entry;
}

export function restoreChange(id: string): RestoreResult {
  const change = loadChange(id);
  if (change === null) {
    return { ok: false, status: 404, message: `no history entry ${id}` };
  }
  const { entry, before } = change;
  if (before === null) {
    return refused("the file didn't exist before this change, so there is no version to restore");
  }
  const problem = restoreProblem(entry.path);
  if (problem !== null) {
    return refused(problem);
  }
  const current = readCurrent(entry.path);
  const recorded = recordChange({
    kind: entry.kind,
    path: entry.path,
    before: current.bytes,
    after: before,
    source: "console-restore",
  });
  writeAtomically(entry.path, before, current.mode);
  return { ok: true, entry: recorded };
}

function refused(message: string): RestoreResult {
  return { ok: false, status: 409, message };
}

function restoreProblem(target: string): string | null {
  if (!path.isAbsolute(target)) {
    return `${target} is not an absolute path`;
  }
  if (isSymlink(target)) {
    return `${target} is a symlink; restore the file it points to instead`;
  }
  return null;
}

function readCurrent(target: string): { bytes: string | null; mode: number } {
  if (!fs.existsSync(target)) {
    return { bytes: null, mode: DEFAULT_MODE };
  }
  return {
    bytes: fs.readFileSync(target, "utf8"),
    mode: fs.statSync(target).mode & 0o777,
  };
}

function writeAtomically(target: string, data: string, mode: number): void {
  const temp = path.join(path.dirname(target), `.restore-${crypto.randomBytes(4).toString("hex")}.tmp`);
  try {
    fs.writeFileSync(temp, data, { flag: "wx", mode });
    fs.chmodSync(temp, mode);
    fs.renameSync(temp, target);
  } catch (error) {
    fs.rmSync(temp, { force: true });
    throw error;
  }
}

function readIndex(): HistoryEntry[] {
  const file = path.join(historyDir(), INDEX_NAME);
  if (!fs.existsSync(file)) {
    return [];
  }
  return fs
    .readFileSync(file, "utf8")
    .split("\n")
    .flatMap((line) => parseEntry(line));
}

function parseEntry(line: string): HistoryEntry[] {
  try {
    const value = JSON.parse(line) as Partial<HistoryEntry>;
    const valid = typeof value.id === "string" && ID_PATTERN.test(value.id) && typeof value.after === "string";
    return valid ? [value as HistoryEntry] : [];
  } catch {
    return [];
  }
}

function readData(name: string): string {
  return fs.readFileSync(path.join(historyDir(), path.basename(name)), "utf8");
}

function newEntry(change: NewChange, now: Date): HistoryEntry {
  const stamp = now.toISOString().slice(0, 19).replace(/[-:]/g, "").replace("T", "-");
  const id = `${stamp}-${change.kind}-${crypto.randomBytes(2).toString("hex")}`;
  return {
    id,
    at: now.toISOString(),
    kind: change.kind,
    path: change.path,
    source: change.source,
    before: change.before === null ? null : `${id}.before`,
    after: `${id}.after`,
  };
}

function ensureFolder(folder: string): void {
  if (isSymlink(folder)) {
    throw new Error(`refusing history folder that is a symlink: ${folder}`);
  }
  fs.mkdirSync(folder, { recursive: true, mode: FOLDER_MODE });
}

function writeNewFile(file: string, data: string): void {
  fs.writeFileSync(file, data, { flag: "wx", mode: FILE_MODE });
}

function appendIndex(folder: string, entry: HistoryEntry): void {
  const file = path.join(folder, INDEX_NAME);
  if (isSymlink(file)) {
    throw new Error(`refusing history index that is a symlink: ${file}`);
  }
  fs.appendFileSync(file, `${JSON.stringify(entry)}\n`, { mode: FILE_MODE });
}

function isSymlink(target: string): boolean {
  try {
    return fs.lstatSync(target).isSymbolicLink();
  } catch {
    return false;
  }
}
