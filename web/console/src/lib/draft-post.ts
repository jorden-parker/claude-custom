import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import type { Draft, PrDraft, ReviewDraft } from "./draft-schema";
import { pullRequestBody, reviewPayload } from "./draft-render";
import { draftForWrite, repoFor, saveDraft } from "./drafts";
import { runOnce, type RunOnceResult } from "./run-once";

const GH_OPTIONS = { timeoutMs: 120_000, maxBytes: 1024 * 1024 };
const TEMP_FOLDER_PREFIX = "claude-draft-";
const TEMP_FILE_MODE = 0o600;

type PostResult = { ok: true; url: string } | { ok: false; message: string };

export type PostOutcome =
  | { kind: "posted"; draft: Draft; hash: string; repo: string }
  | { kind: "missing" }
  | { kind: "unreadable"; reason: string }
  | { kind: "stale" }
  | { kind: "already-posted" }
  | { kind: "no-repo"; project: string }
  | { kind: "failed"; message: string };

export async function postStoredDraft(
  id: string,
  hash: string,
  asDraft: boolean,
): Promise<PostOutcome> {
  const current = draftForWrite(id, hash);
  if (current.kind !== "ready") {
    return current;
  }
  const draft = current.draft;
  if (draft.posted) {
    return { kind: "already-posted" };
  }
  const repo = await repoFor(draft.project);
  if (repo === null) {
    return { kind: "no-repo", project: draft.project };
  }
  const result = await postDraft(draft, repo, asDraft);
  if (!result.ok) {
    return { kind: "failed", message: result.message };
  }
  const posted: Draft = {
    ...draft,
    posted: { url: result.url, at: new Date().toISOString() },
  };
  return { kind: "posted", draft: posted, hash: saveDraft(posted), repo };
}

export async function postDraft(
  draft: Draft,
  repo: string,
  asDraft: boolean,
): Promise<PostResult> {
  return draft.kind === "pr"
    ? createPullRequest(draft, repo, asDraft)
    : postReview(draft, repo);
}

async function createPullRequest(
  draft: PrDraft,
  repo: string,
  asDraft: boolean,
): Promise<PostResult> {
  return withTempFile(
    "body.md",
    pullRequestBody(draft.sections),
    async (bodyFile) => {
      const result = await runOnce(
        ["gh", ...pullRequestArgs(draft, repo, bodyFile, asDraft)],
        GH_OPTIONS,
      );
      return result.code === 0 ? urlOfLastLine(result.stdout) : failure(result);
    },
  );
}

async function postReview(
  draft: ReviewDraft,
  repo: string,
): Promise<PostResult> {
  const endpoint = `repos/${repo}/pulls/${draft.pr}/reviews`;
  return withTempFile(
    "review.json",
    JSON.stringify(reviewPayload(draft)),
    async (file) => {
      const result = await runOnce(
        ["gh", "api", endpoint, "--method", "POST", "--input", file],
        GH_OPTIONS,
      );
      return result.code === 0
        ? success(reviewUrl(result.stdout, repo, draft.pr))
        : failure(result);
    },
  );
}

function pullRequestArgs(
  draft: PrDraft,
  repo: string,
  bodyFile: string,
  asDraft: boolean,
): string[] {
  const args = [
    "pr",
    "create",
    "--repo",
    repo,
    `--base=${draft.base}`,
    `--head=${draft.head}`,
    `--title=${draft.title}`,
    "--body-file",
    bodyFile,
  ];
  return asDraft ? [...args, "--draft"] : args;
}

function reviewUrl(stdout: string, repo: string, pr: number): string {
  const fallback = `https://github.com/${repo}/pull/${pr}`;
  try {
    const reported = (JSON.parse(stdout) as { html_url?: unknown }).html_url;
    return typeof reported === "string" && reported !== ""
      ? reported
      : fallback;
  } catch {
    return fallback;
  }
}

function urlOfLastLine(stdout: string): PostResult {
  const lines = stdout.trim().split("\n");
  const url = lines[lines.length - 1].trim();
  return url === ""
    ? { ok: false, message: "gh printed no URL" }
    : success(url);
}

function success(url: string): PostResult {
  return { ok: true, url };
}

function failure(result: RunOnceResult): PostResult {
  return {
    ok: false,
    message: result.stderr.trim() || `gh exited with code ${result.code}`,
  };
}

async function withTempFile<T>(
  fileName: string,
  content: string,
  handle: (file: string) => Promise<T>,
): Promise<T> {
  const folder = fs.mkdtempSync(path.join(os.tmpdir(), TEMP_FOLDER_PREFIX));
  try {
    const file = path.join(folder, fileName);
    fs.writeFileSync(file, content, { mode: TEMP_FILE_MODE });
    return await handle(file);
  } finally {
    fs.rmSync(folder, { recursive: true, force: true });
  }
}
