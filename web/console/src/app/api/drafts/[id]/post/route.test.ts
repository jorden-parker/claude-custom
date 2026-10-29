import { execFileSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { Draft } from "@/lib/draft-schema";
import { runOnce } from "@/lib/run-once";
import { readStoredDraft, saveDraft } from "@/lib/drafts";
import { POST } from "./route";

vi.mock("next/server", async (importOriginal) => ({
  ...(await importOriginal<typeof import("next/server")>()),
  connection: async () => undefined,
}));

vi.mock("@/lib/run-once", () => ({ runOnce: vi.fn() }));

const PR_ID = "20260101-120000-pr-add-drafts";
const CREATED = "2026-01-01T12:00:00.000Z";
const PR_URL = "https://github.com/jorden/claude-custom/pull/9";

function prDraft(project: string, overrides: Partial<Draft> = {}): Draft {
  return {
    kind: "pr",
    id: PR_ID,
    project,
    base: "main",
    head: "feature-x",
    title: "Add drafts",
    sections: [{ heading: "Summary", body: "Adds drafts." }],
    created: CREATED,
    ...overrides,
  } as Draft;
}

const context = { params: Promise.resolve({ id: PR_ID }) };

const postRequest = (body: unknown, contentType = "application/json") =>
  new Request(`http://127.0.0.1:8808/api/drafts/${PR_ID}/post`, {
    method: "POST",
    headers: { "content-type": contentType, origin: "http://127.0.0.1:8808" },
    body: JSON.stringify(body),
  });

const runOnceMock = vi.mocked(runOnce);

function answer(stdout: string, stderr = "", code = 0): void {
  runOnceMock.mockImplementation(async (argv) =>
    argv[0] === "git"
      ? {
          code: 0,
          stdout: "git@github.com:jorden/claude-custom.git\n",
          stderr: "",
        }
      : { code, stdout, stderr },
  );
}

describe("/api/drafts/[id]/post", () => {
  let draftsFolder: string;
  let project: string;
  let previousDir: string | undefined;

  beforeEach(() => {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), "drafts-post-route-"));
    draftsFolder = path.join(root, "drafts");
    project = path.join(root, "tree");
    fs.mkdirSync(project);
    execFileSync("git", ["-C", project, "init", "-q"]);
    previousDir = process.env.CLAUDE_OLLAMA_DRAFTS_DIR;
    process.env.CLAUDE_OLLAMA_DRAFTS_DIR = draftsFolder;
    runOnceMock.mockReset();
    answer(`${PR_URL}\n`);
  });

  afterEach(() => {
    if (previousDir === undefined) {
      delete process.env.CLAUDE_OLLAMA_DRAFTS_DIR;
    } else {
      process.env.CLAUDE_OLLAMA_DRAFTS_DIR = previousDir;
    }
    fs.rmSync(path.dirname(draftsFolder), { recursive: true, force: true });
  });

  it("creates the PR, records posted on disk, and answers the draft with its repo", async () => {
    saveDraft(prDraft(project));
    const hash = readStoredDraft(PR_ID)?.hash;

    const response = await POST(postRequest({ hash }), context);
    const body = await response.json();

    expect(response.status).toBe(200);
    expect(body).toMatchObject({
      draft: { posted: { url: PR_URL } },
      repo: "jorden/claude-custom",
    });
    expect(readStoredDraft(PR_ID)?.parsed).toMatchObject({
      ok: true,
      draft: { posted: { url: PR_URL } },
    });
    expect(body.hash).toBe(readStoredDraft(PR_ID)?.hash);
  });

  it("passes --draft to gh when the body asks for a draft PR", async () => {
    saveDraft(prDraft(project));

    await POST(
      postRequest({ hash: readStoredDraft(PR_ID)?.hash, draft: true }),
      context,
    );

    const ghCall = runOnceMock.mock.calls.find(([argv]) => argv[0] === "gh");
    expect(ghCall?.[0].at(-1)).toBe("--draft");
  });

  it("answers 409 when the hash is stale, and runs nothing", async () => {
    saveDraft(prDraft(project));

    const response = await POST(postRequest({ hash: "0".repeat(64) }), context);

    expect(response.status).toBe(409);
    expect(runOnceMock).not.toHaveBeenCalled();
  });

  it("answers 409 when the draft is already posted", async () => {
    saveDraft(prDraft(project, { posted: { url: PR_URL, at: CREATED } }));

    const response = await POST(
      postRequest({ hash: readStoredDraft(PR_ID)?.hash }),
      context,
    );

    expect(response.status).toBe(409);
    expect(await response.json()).toEqual({
      message: "this draft is already posted",
    });
    expect(runOnceMock).not.toHaveBeenCalled();
  });

  it("answers 400 when the project has no GitHub origin", async () => {
    saveDraft(prDraft(project));
    runOnceMock.mockImplementation(async () => ({
      code: 1,
      stdout: "",
      stderr: "no remote",
    }));

    const response = await POST(
      postRequest({ hash: readStoredDraft(PR_ID)?.hash }),
      context,
    );

    expect(response.status).toBe(400);
  });

  it("answers 502 with gh's stderr when gh fails, and leaves the draft unposted", async () => {
    saveDraft(prDraft(project));
    answer("", "a pull request already exists\n", 1);

    const response = await POST(
      postRequest({ hash: readStoredDraft(PR_ID)?.hash }),
      context,
    );

    expect(response.status).toBe(502);
    expect(await response.json()).toEqual({
      message: "a pull request already exists",
    });
    expect(readStoredDraft(PR_ID)?.parsed).toMatchObject({
      ok: true,
      draft: { posted: undefined },
    });
  });

  it("answers 415 for a body that is not declared JSON", async () => {
    saveDraft(prDraft(project));

    const response = await POST(
      postRequest({ hash: "x" }, "text/plain"),
      context,
    );

    expect(response.status).toBe(415);
  });

  it("answers 400 when the hash is missing", async () => {
    saveDraft(prDraft(project));

    const response = await POST(postRequest({ draft: true }), context);

    expect(response.status).toBe(400);
  });

  it("answers 404 for a draft that does not exist", async () => {
    const response = await POST(postRequest({ hash: "x" }), context);

    expect(response.status).toBe(404);
  });
});
