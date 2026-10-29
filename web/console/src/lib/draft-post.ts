import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import type {
  Draft,
  PrDraft,
  ReviewComment,
  ReviewDraft,
  Section,
} from "./draft-schema";
import { draftForWrite, repoFor, saveDraft } from "./drafts";
import { runOnce, type RunOnceResult } from "./run-once";

const GH_OPTIONS = { timeoutMs: 120_000, maxBytes: 1024 * 1024 };
const TEMP_FOLDER_PREFIX = "claude-draft-";
const TEMP_FILE_MODE = 0o600;
const INLINE_SIDE = "RIGHT";

type PostResult = { ok: true; url: string } | { ok: false; message: string };
type PlacedComment = ReviewComment & { path: string; line: number };
type InlineComment = {
  path: string;
  line: number;
  side: typeof INLINE_SIDE;
  body: string;
};
type ReviewPayload = { event: string; body: string; comments: InlineComment[] };

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

function pullRequestBody(sections: Section[]): string {
  return sections
    .map((section) => `## ${section.heading}\n\n${section.body}`)
    .join("\n\n");
}

function reviewPayload(draft: ReviewDraft): ReviewPayload {
  const unplaced = draft.comments.filter((comment) => !isPlaced(comment));
  return {
    event: draft.event,
    body: [draft.summary, ...unplaced.map(renderComment)]
      .filter((part) => part.trim() !== "")
      .join("\n\n"),
    comments: draft.comments.filter(isPlaced).map((comment) => ({
      path: comment.path,
      line: comment.line,
      side: INLINE_SIDE,
      body: renderComment(comment),
    })),
  };
}

function isPlaced(comment: ReviewComment): comment is PlacedComment {
  return comment.path !== undefined && comment.line !== undefined;
}

function renderComment(comment: ReviewComment): string {
  const tags = comment.decorations.join(", ");
  const heading = tags === "" ? comment.label : `${comment.label} (${tags})`;
  return `**${heading}:** ${comment.body}`;
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
