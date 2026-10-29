import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import {
  DRAFT_ID_PATTERN,
  mergeDraftEdits,
  parseDraft,
  type Draft,
  type ParseResult,
} from "./draft-schema";
import { runOnce } from "./run-once";

const DEFAULT_DRAFTS_DIR_NAME = ".claude-ollama/drafts";
const DRAFT_FILE_PATTERN = /^(.+)\.json$/;
const FILE_MODE = 0o600;
const FOLDER_MODE = 0o700;
const GIT_OPTIONS = { timeoutMs: 10_000, maxBytes: 64 * 1024 };
const GITHUB_REMOTE_PATTERN =
  /^(?:https:\/\/github\.com\/|ssh:\/\/git@github\.com\/|git@github\.com:)([A-Za-z0-9][A-Za-z0-9_.-]*)\/([A-Za-z0-9][A-Za-z0-9_.-]*?)(?:\.git)?\/?$/;

export type DraftEntry = { id: string; parsed: ParseResult };
export type StoredDraft = { text: string; hash: string; parsed: ParseResult };
export type DraftRow = {
  id: string;
  repo: string | null;
  draft: Draft | null;
  invalid: string | null;
};
export type EditOutcome =
  | { kind: "saved"; draft: Draft; hash: string }
  | { kind: "missing" }
  | { kind: "unreadable"; reason: string }
  | { kind: "stale" }
  | { kind: "invalid"; reason: string };

export function draftsDir(): string {
  return (
    process.env.CLAUDE_OLLAMA_DRAFTS_DIR ||
    path.join(os.homedir(), DEFAULT_DRAFTS_DIR_NAME)
  );
}

export function draftHash(text: string): string {
  return crypto.createHash("sha256").update(text).digest("hex");
}

export function listDrafts(): DraftEntry[] {
  return draftIdsOnDisk().flatMap((id) => {
    const stored = readStoredDraft(id);
    return stored ? [{ id, parsed: stored.parsed }] : [];
  });
}

export async function draftRows(): Promise<DraftRow[]> {
  return Promise.all(
    listDrafts().map(async ({ id, parsed }) => {
      if (!parsed.ok) {
        return { id, repo: null, draft: null, invalid: parsed.reason };
      }
      return {
        id,
        repo: await repoFor(parsed.draft.project),
        draft: parsed.draft,
        invalid: null,
      };
    }),
  );
}

export function readStoredDraft(id: string): StoredDraft | null {
  const file = draftFile(id);
  if (file === null || !fs.existsSync(file)) {
    return null;
  }
  const text = fs.readFileSync(file, "utf8");
  return { text, hash: draftHash(text), parsed: parseDraft(id, text) };
}

export function saveDraft(draft: Draft): string {
  const file = draftFile(draft.id);
  if (file === null) {
    throw new Error("not a draft id");
  }
  const text = `${JSON.stringify(draft, null, 2)}\n`;
  fs.mkdirSync(path.dirname(file), { recursive: true, mode: FOLDER_MODE });
  const temporary = `${file}.${process.pid}.${Date.now()}.tmp`;
  fs.writeFileSync(temporary, text, { mode: FILE_MODE });
  fs.renameSync(temporary, file);
  return draftHash(text);
}

export type WritableDraft =
  | { kind: "ready"; draft: Draft }
  | { kind: "missing" }
  | { kind: "unreadable"; reason: string }
  | { kind: "stale" };

export function draftForWrite(id: string, hash: string): WritableDraft {
  const stored = readStoredDraft(id);
  if (stored === null) {
    return { kind: "missing" };
  }
  if (!stored.parsed.ok) {
    return { kind: "unreadable", reason: stored.parsed.reason };
  }
  if (stored.hash !== hash) {
    return { kind: "stale" };
  }
  return { kind: "ready", draft: stored.parsed.draft };
}

export function saveEdits(
  id: string,
  hash: string,
  edits: unknown,
): EditOutcome {
  const current = draftForWrite(id, hash);
  if (current.kind !== "ready") {
    return current;
  }
  const merged = mergeDraftEdits(current.draft, edits);
  if (!merged.ok) {
    return { kind: "invalid", reason: merged.reason };
  }
  return { kind: "saved", draft: merged.draft, hash: saveDraft(merged.draft) };
}

export function deleteDraft(id: string): boolean {
  const file = draftFile(id);
  if (file === null || !fs.existsSync(file)) {
    return false;
  }
  fs.unlinkSync(file);
  return true;
}

export async function repoFor(project: string): Promise<string | null> {
  const result = await runOnce(
    ["git", "-C", project, "remote", "get-url", "origin"],
    GIT_OPTIONS,
  );
  return result.code === 0 ? githubRepoFromUrl(result.stdout.trim()) : null;
}

export function githubRepoFromUrl(url: string): string | null {
  const match = GITHUB_REMOTE_PATTERN.exec(url);
  return match ? `${match[1]}/${match[2]}` : null;
}

function draftFile(id: string): string | null {
  if (!DRAFT_ID_PATTERN.test(id)) {
    return null;
  }
  const directory = path.resolve(draftsDir());
  const file = path.resolve(directory, `${id}.json`);
  return path.dirname(file) === directory ? file : null;
}

function draftIdsOnDisk(): string[] {
  const directory = draftsDir();
  if (!fs.existsSync(directory)) {
    return [];
  }
  return fs
    .readdirSync(directory)
    .flatMap((name) => {
      const match = DRAFT_FILE_PATTERN.exec(name);
      return match && DRAFT_ID_PATTERN.test(match[1]) ? [match[1]] : [];
    })
    .sort()
    .reverse();
}
