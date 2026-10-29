import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { Draft, ReviewDraft } from "./draft-schema";
import { postDraft, postStoredDraft } from "./draft-post";
import { readStoredDraft, saveDraft } from "./drafts";

type FakeReply = { code: number; stdout: string; stderr: string };
type FakeCall = {
  args: string[];
  fileText: string;
  fileMode: number | null;
  fileExisted: boolean;
};

const fake = vi.hoisted(() => ({
  calls: [] as FakeCall[],
  gh: { code: 0, stdout: "", stderr: "" } as FakeReply,
  originUrl: "git@github.com:jorden/claude-custom.git",
}));

vi.mock("node:child_process", async (importOriginal) => ({
  ...(await importOriginal<typeof import("node:child_process")>()),
  execFile: (
    command: string,
    args: string[],
    _options: unknown,
    callback: (error: Error | null, stdout: string, stderr: string) => void,
  ) => {
    if (command === "git") {
      callback(null, `${fake.originUrl}\n`, "");
      return;
    }
    fake.calls.push(recordCall(args));
    const failed = fake.gh.code !== 0;
    callback(
      failed ? new Error("gh failed") : null,
      fake.gh.stdout,
      fake.gh.stderr,
    );
  },
}));

function recordCall(args: string[]): FakeCall {
  const flag = ["--input", "--body-file"].find((name) => args.includes(name));
  if (flag === undefined) {
    return { args, fileText: "", fileMode: null, fileExisted: false };
  }
  const file = args[args.indexOf(flag) + 1];
  const existed = fs.existsSync(file);
  return {
    args,
    fileText: existed ? fs.readFileSync(file, "utf8") : "",
    fileMode: existed ? fs.statSync(file).mode & 0o777 : null,
    fileExisted: existed,
  };
}

const PR_ID = "20260101-120000-pr-add-drafts";
const REVIEW_ID = "20260101-120000-review-pr-12";
const CREATED = "2026-01-01T12:00:00.000Z";
const PR_URL = "https://github.com/jorden/claude-custom/pull/9";

const prDraft = (): Draft => ({
  kind: "pr",
  id: PR_ID,
  project: "/work/tree",
  base: "main",
  head: "feature-x",
  title: "Add drafts",
  sections: [
    { heading: "Summary", body: "Adds drafts." },
    { heading: "Test plan", body: "Run the suite." },
  ],
  created: CREATED,
});

const reviewDraft = (): ReviewDraft => ({
  kind: "review",
  id: REVIEW_ID,
  project: "/work/tree",
  pr: 12,
  event: "REQUEST_CHANGES",
  summary: "Two things.",
  comments: [
    {
      label: "issue",
      decorations: ["blocking", "security"],
      path: "src/a.ts",
      line: 42,
      body: "Unchecked input.",
    },
    {
      label: "nitpick",
      decorations: [],
      path: "src/b.ts",
      line: 7,
      body: "Rename this.",
    },
    { label: "praise", decorations: [], body: "Good split overall." },
  ],
  created: CREATED,
});

function answerGh(reply: Partial<FakeReply>): void {
  fake.gh = { code: 0, stdout: "", stderr: "", ...reply };
}

describe("postDraft for a PR", () => {
  beforeEach(() => {
    fake.calls.length = 0;
    answerGh({ stdout: `Creating pull request\n${PR_URL}\n` });
  });

  it("runs gh pr create with the repo, branches and title as separate flags", async () => {
    await postDraft(prDraft(), "jorden/claude-custom", false);

    expect(fake.calls[0].args).toEqual([
      "pr",
      "create",
      "--repo",
      "jorden/claude-custom",
      "--base=main",
      "--head=feature-x",
      "--title=Add drafts",
      "--body-file",
      expect.any(String),
    ]);
  });

  it("sends the sections as level-two headings in a 0600 body file", async () => {
    await postDraft(prDraft(), "jorden/claude-custom", false);

    expect(fake.calls[0].fileText).toBe(
      "## Summary\n\nAdds drafts.\n\n## Test plan\n\nRun the suite.",
    );
    expect(fake.calls[0].fileMode).toBe(0o600);
  });

  it("removes the body file after gh returns", async () => {
    await postDraft(prDraft(), "jorden/claude-custom", false);

    expect(fake.calls[0].fileExisted).toBe(true);
    const bodyFile =
      fake.calls[0].args[fake.calls[0].args.indexOf("--body-file") + 1];
    expect(fs.existsSync(bodyFile)).toBe(false);
  });

  it("adds --draft when a draft PR is requested", async () => {
    await postDraft(prDraft(), "jorden/claude-custom", true);

    expect(fake.calls[0].args.at(-1)).toBe("--draft");
  });

  it("returns the PR URL that gh printed last", async () => {
    expect(await postDraft(prDraft(), "jorden/claude-custom", false)).toEqual({
      ok: true,
      url: PR_URL,
    });
  });

  it("returns gh's stderr when the PR is refused", async () => {
    answerGh({ code: 1, stderr: "a pull request already exists\n" });

    expect(await postDraft(prDraft(), "jorden/claude-custom", false)).toEqual({
      ok: false,
      message: "a pull request already exists",
    });
  });
});

describe("postDraft for a review", () => {
  beforeEach(() => {
    fake.calls.length = 0;
    answerGh({
      stdout: JSON.stringify({ html_url: `${PR_URL}#pullrequestreview-5` }),
    });
  });

  it("posts to the reviews endpoint of the PR", async () => {
    await postDraft(reviewDraft(), "jorden/claude-custom", false);

    expect(fake.calls[0].args.slice(0, 5)).toEqual([
      "api",
      "repos/jorden/claude-custom/pulls/12/reviews",
      "--method",
      "POST",
      "--input",
    ]);
    expect(fake.calls[0].fileMode).toBe(0o600);
  });

  it("sends the event, the summary with unplaced comments, and the placed comments inline", async () => {
    await postDraft(reviewDraft(), "jorden/claude-custom", false);

    expect(JSON.parse(fake.calls[0].fileText)).toEqual({
      event: "REQUEST_CHANGES",
      body: "Two things.\n\n**praise:** Good split overall.",
      comments: [
        {
          path: "src/a.ts",
          line: 42,
          side: "RIGHT",
          body: "**issue (blocking, security):** Unchecked input.",
        },
        {
          path: "src/b.ts",
          line: 7,
          side: "RIGHT",
          body: "**nitpick:** Rename this.",
        },
      ],
    });
  });

  it("leaves out the summary when it is empty", async () => {
    const draft: Draft = {
      ...reviewDraft(),
      summary: "",
      comments: [{ label: "praise", decorations: [], body: "Nice." }],
    };

    await postDraft(draft, "jorden/claude-custom", false);

    expect(JSON.parse(fake.calls[0].fileText).body).toBe("**praise:** Nice.");
  });

  it("returns the html_url of the review that GitHub answered with", async () => {
    expect(
      await postDraft(reviewDraft(), "jorden/claude-custom", false),
    ).toEqual({
      ok: true,
      url: `${PR_URL}#pullrequestreview-5`,
    });
  });

  it("falls back to the PR page when the answer has no review URL", async () => {
    answerGh({ stdout: "{}" });

    expect(
      await postDraft(reviewDraft(), "jorden/claude-custom", false),
    ).toEqual({
      ok: true,
      url: "https://github.com/jorden/claude-custom/pull/12",
    });
  });

  it("returns gh's stderr when GitHub refuses the review", async () => {
    answerGh({ code: 1, stderr: "HTTP 422: Unprocessable Entity\n" });

    expect(
      await postDraft(reviewDraft(), "jorden/claude-custom", false),
    ).toEqual({
      ok: false,
      message: "HTTP 422: Unprocessable Entity",
    });
  });
});

describe("postStoredDraft", () => {
  let draftsFolder: string;
  let previousDir: string | undefined;

  beforeEach(() => {
    fake.calls.length = 0;
    fake.originUrl = "git@github.com:jorden/claude-custom.git";
    answerGh({ stdout: `${PR_URL}\n` });
    draftsFolder = path.join(
      fs.mkdtempSync(path.join(os.tmpdir(), "draft-post-")),
      "drafts",
    );
    previousDir = process.env.CLAUDE_OLLAMA_DRAFTS_DIR;
    process.env.CLAUDE_OLLAMA_DRAFTS_DIR = draftsFolder;
  });

  afterEach(() => {
    if (previousDir === undefined) {
      delete process.env.CLAUDE_OLLAMA_DRAFTS_DIR;
    } else {
      process.env.CLAUDE_OLLAMA_DRAFTS_DIR = previousDir;
    }
    fs.rmSync(path.dirname(draftsFolder), { recursive: true, force: true });
  });

  function hashOf(id: string): string {
    return readStoredDraft(id)?.hash ?? "";
  }

  it("creates the PR and records posted in the draft on disk", async () => {
    saveDraft(prDraft());

    const outcome = await postStoredDraft(PR_ID, hashOf(PR_ID), false);

    expect(outcome).toMatchObject({
      kind: "posted",
      repo: "jorden/claude-custom",
    });
    expect(readStoredDraft(PR_ID)?.parsed).toMatchObject({
      ok: true,
      draft: { posted: { url: PR_URL } },
    });
  });

  it("answers stale when the hash does not match, and calls nothing", async () => {
    saveDraft(prDraft());

    expect(await postStoredDraft(PR_ID, "0".repeat(64), false)).toEqual({
      kind: "stale",
    });
    expect(fake.calls).toHaveLength(0);
  });

  it("answers already-posted for a draft that has a posted record", async () => {
    saveDraft({ ...prDraft(), posted: { url: PR_URL, at: CREATED } });

    expect(await postStoredDraft(PR_ID, hashOf(PR_ID), false)).toEqual({
      kind: "already-posted",
    });
    expect(fake.calls).toHaveLength(0);
  });

  it("answers no-repo when origin is not a GitHub remote", async () => {
    fake.originUrl = "https://gitlab.com/o/r.git";
    saveDraft(prDraft());

    expect(await postStoredDraft(PR_ID, hashOf(PR_ID), false)).toEqual({
      kind: "no-repo",
      project: "/work/tree",
    });
    expect(fake.calls).toHaveLength(0);
  });

  it("answers failed with gh's message and leaves the draft unposted", async () => {
    answerGh({ code: 1, stderr: "not logged in\n" });
    saveDraft(prDraft());

    expect(await postStoredDraft(PR_ID, hashOf(PR_ID), false)).toEqual({
      kind: "failed",
      message: "not logged in",
    });
    expect(readStoredDraft(PR_ID)?.parsed).toMatchObject({
      ok: true,
      draft: { posted: undefined },
    });
  });

  it("answers missing for a draft that does not exist", async () => {
    expect(await postStoredDraft(PR_ID, "x", false)).toEqual({
      kind: "missing",
    });
  });

  it("answers unreadable for a file that is not a valid draft", async () => {
    fs.mkdirSync(draftsFolder, { recursive: true });
    fs.writeFileSync(path.join(draftsFolder, `${PR_ID}.json`), "{not json");

    expect(await postStoredDraft(PR_ID, hashOf(PR_ID), false)).toEqual({
      kind: "unreadable",
      reason: "not JSON",
    });
  });

  it("records the review's own URL on a posted review", async () => {
    answerGh({ stdout: JSON.stringify({ html_url: `${PR_URL}#r` }) });
    saveDraft(reviewDraft());

    const outcome = await postStoredDraft(REVIEW_ID, hashOf(REVIEW_ID), false);

    expect(outcome).toMatchObject({
      kind: "posted",
      draft: { posted: { url: `${PR_URL}#r` } },
    });
  });
});
