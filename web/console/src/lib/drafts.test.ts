import { execFileSync } from "node:child_process";
import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import type { Draft } from "./draft-schema";
import {
  deleteDraft,
  draftHash,
  draftsDir,
  githubRepoFromUrl,
  listDrafts,
  readStoredDraft,
  repoFor,
  saveDraft,
  saveEdits,
} from "./drafts";

const PR_ID = "20260101-120000-pr-add-drafts";
const LATER_PR_ID = "20260102-090000-pr-second";
const REVIEW_ID = "20260101-120000-review-pr-12";
const CREATED = "2026-01-01T12:00:00.000Z";

const prDraft = (id = PR_ID): Draft => ({
  kind: "pr",
  id,
  project: "/work/tree",
  base: "main",
  head: "feature-x",
  title: "Add drafts",
  sections: [{ heading: "Summary", body: "Adds drafts." }],
  created: CREATED,
});

const reviewDraft = (): Draft => ({
  kind: "review",
  id: REVIEW_ID,
  project: "/work/tree",
  pr: 12,
  event: "COMMENT",
  summary: "Looks good.",
  comments: [{ label: "praise", decorations: [], body: "Nice split." }],
  created: CREATED,
});

describe("drafts store", () => {
  let draftsFolder: string;
  let previousDir: string | undefined;

  beforeEach(() => {
    draftsFolder = path.join(
      fs.mkdtempSync(path.join(os.tmpdir(), "drafts-")),
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

  function writeRaw(id: string, text: string): void {
    fs.mkdirSync(draftsFolder, { recursive: true });
    fs.writeFileSync(path.join(draftsFolder, `${id}.json`), text);
  }

  describe("links the session planted", () => {
    function outsideFile(text: string): string {
      const outside = path.join(path.dirname(draftsFolder), "outside.txt");
      fs.writeFileSync(outside, text);
      return outside;
    }

    it("never reads a draft that is a symlink", () => {
      const outside = outsideFile(JSON.stringify(prDraft()));
      fs.mkdirSync(draftsFolder, { recursive: true });
      fs.symlinkSync(outside, path.join(draftsFolder, `${PR_ID}.json`));
      expect(readStoredDraft(PR_ID)).toBeNull();
    });

    it("never writes through a drafts folder that is a symlink", () => {
      const target = path.join(path.dirname(draftsFolder), "elsewhere");
      fs.mkdirSync(target);
      fs.symlinkSync(target, draftsFolder);
      expect(() => saveDraft(prDraft())).toThrow();
      expect(fs.readdirSync(target)).toEqual([]);
    });

    it("lists nothing from a drafts folder that is a symlink", () => {
      const target = path.join(path.dirname(draftsFolder), "elsewhere");
      fs.mkdirSync(target);
      fs.writeFileSync(
        path.join(target, `${PR_ID}.json`),
        JSON.stringify(prDraft()),
      );
      fs.symlinkSync(target, draftsFolder);
      expect(listDrafts()).toEqual([]);
    });

    it("replaces a symlinked draft on save, never its target", () => {
      const outside = outsideFile("keep me");
      fs.mkdirSync(draftsFolder, { recursive: true });
      fs.symlinkSync(outside, path.join(draftsFolder, `${PR_ID}.json`));
      saveDraft(prDraft());
      expect(fs.readFileSync(outside, "utf8")).toBe("keep me");
      expect(
        fs.lstatSync(path.join(draftsFolder, `${PR_ID}.json`)).isFile(),
      ).toBe(true);
    });
  });

  describe("draftsDir", () => {
    it("uses the environment variable when it is set", () => {
      expect(draftsDir()).toBe(draftsFolder);
    });

    it("defaults to .claude-ollama/drafts in the home folder", () => {
      delete process.env.CLAUDE_OLLAMA_DRAFTS_DIR;

      expect(draftsDir()).toBe(
        path.join(os.homedir(), ".claude-ollama", "drafts"),
      );
    });
  });

  describe("listDrafts", () => {
    it("lists the newest draft first and flags an invalid one with its reason", () => {
      saveDraft(prDraft());
      saveDraft(prDraft(LATER_PR_ID));
      writeRaw("20251231-000000-pr-broken", "{not json");

      const entries = listDrafts();

      expect(entries.map((entry) => entry.id)).toEqual([
        LATER_PR_ID,
        PR_ID,
        "20251231-000000-pr-broken",
      ]);
      expect(entries[2].parsed).toEqual({ ok: false, reason: "not JSON" });
    });

    it("ignores files whose names are not draft ids", () => {
      writeRaw("notes", "{}");
      fs.writeFileSync(path.join(draftsFolder, "readme.txt"), "hello");

      expect(listDrafts()).toEqual([]);
    });

    it("answers an empty list when the folder does not exist yet", () => {
      expect(listDrafts()).toEqual([]);
    });
  });

  describe("readStoredDraft", () => {
    it("returns the text, its hash and the parsed draft", () => {
      saveDraft(prDraft());

      const stored = readStoredDraft(PR_ID);

      expect(stored).toMatchObject({
        hash: draftHash(stored?.text ?? ""),
        parsed: { ok: true },
      });
      expect(stored?.parsed).toMatchObject({
        ok: true,
        draft: { title: "Add drafts" },
      });
    });

    it("refuses ids that could escape the folder", () => {
      expect(readStoredDraft("../20260101-120000-pr-x")).toBeNull();
      expect(readStoredDraft("20260101-120000-pr-x/../../etc")).toBeNull();
    });

    it("returns null for a draft that does not exist", () => {
      expect(readStoredDraft(PR_ID)).toBeNull();
    });
  });

  describe("saveDraft", () => {
    it("round-trips the draft and writes it with mode 0600 in a 0700 folder", () => {
      saveDraft(prDraft());

      const stored = readStoredDraft(PR_ID);
      const file = path.join(draftsFolder, `${PR_ID}.json`);

      expect(stored?.parsed).toEqual({ ok: true, draft: prDraft() });
      expect(fs.statSync(file).mode & 0o777).toBe(0o600);
      expect(fs.statSync(draftsFolder).mode & 0o777).toBe(0o700);
    });

    it("leaves no temporary file behind", () => {
      saveDraft(prDraft());

      expect(fs.readdirSync(draftsFolder)).toEqual([`${PR_ID}.json`]);
    });

    it("returns the hash of the bytes it wrote", () => {
      const hash = saveDraft(prDraft());

      expect(hash).toBe(readStoredDraft(PR_ID)?.hash);
    });
  });

  describe("saveEdits", () => {
    it("replaces the editable fields and keeps the fixed ones from the file", () => {
      saveDraft(prDraft());
      const hash = readStoredDraft(PR_ID)?.hash ?? "";

      const outcome = saveEdits(PR_ID, hash, {
        title: "Renamed",
        base: "develop",
        project: "/elsewhere",
        created: "1999-01-01T00:00:00.000Z",
      });

      expect(outcome).toMatchObject({
        kind: "saved",
        draft: {
          title: "Renamed",
          base: "main",
          project: "/work/tree",
          created: CREATED,
        },
      });
      expect(readStoredDraft(PR_ID)?.parsed).toMatchObject({
        ok: true,
        draft: { title: "Renamed", base: "main" },
      });
    });

    it("answers stale when the hash differs from the file, and writes nothing", () => {
      saveDraft(prDraft());
      const before = readStoredDraft(PR_ID)?.text;

      const outcome = saveEdits(PR_ID, "0".repeat(64), { title: "Renamed" });

      expect(outcome).toEqual({ kind: "stale" });
      expect(readStoredDraft(PR_ID)?.text).toBe(before);
    });

    it("answers invalid with the reason and keeps the file", () => {
      saveDraft(prDraft());
      const hash = readStoredDraft(PR_ID)?.hash ?? "";

      const outcome = saveEdits(PR_ID, hash, { title: "" });

      expect(outcome).toEqual({
        kind: "invalid",
        reason: "title must be one line of at most 256 characters",
      });
      expect(readStoredDraft(PR_ID)?.hash).toBe(hash);
    });

    it("answers missing for a draft that does not exist", () => {
      expect(saveEdits(PR_ID, "x", { title: "x" })).toEqual({
        kind: "missing",
      });
    });

    it("answers unreadable for a file that is not a valid draft", () => {
      writeRaw(PR_ID, "{not json");
      const hash = readStoredDraft(PR_ID)?.hash ?? "";

      expect(saveEdits(PR_ID, hash, { title: "x" })).toEqual({
        kind: "unreadable",
        reason: "not JSON",
      });
    });

    it("edits the review fields of a review draft", () => {
      saveDraft(reviewDraft());
      const hash = readStoredDraft(REVIEW_ID)?.hash ?? "";

      const outcome = saveEdits(REVIEW_ID, hash, {
        event: "APPROVE",
        summary: "Ship it.",
      });

      expect(outcome).toMatchObject({
        kind: "saved",
        draft: { event: "APPROVE", summary: "Ship it.", pr: 12 },
      });
    });
  });

  describe("deleteDraft", () => {
    it("removes the draft once and reports whether it existed", () => {
      saveDraft(prDraft());

      expect(deleteDraft(PR_ID)).toBe(true);
      expect(deleteDraft(PR_ID)).toBe(false);
      expect(readStoredDraft(PR_ID)).toBeNull();
    });

    it("refuses an id that could escape the folder", () => {
      expect(deleteDraft("../escape")).toBe(false);
    });
  });
});

describe("draftHash", () => {
  it("is the sha256 of the text", () => {
    const expected = crypto.createHash("sha256").update("{}").digest("hex");

    expect(draftHash("{}")).toBe(expected);
  });

  it("changes when the text changes", () => {
    expect(draftHash("a")).not.toBe(draftHash("b"));
  });
});

describe("githubRepoFromUrl", () => {
  it.each([
    ["https://github.com/jorden/claude-custom.git", "jorden/claude-custom"],
    ["https://github.com/jorden/claude-custom", "jorden/claude-custom"],
    ["git@github.com:jorden/claude-custom.git", "jorden/claude-custom"],
    ["ssh://git@github.com/jorden/claude-custom", "jorden/claude-custom"],
  ])("reads %s as %s", (url, repo) => {
    expect(githubRepoFromUrl(url)).toBe(repo);
  });

  it.each([
    "http://github.com/jorden/claude-custom",
    "https://gitlab.com/jorden/claude-custom.git",
    "https://github.com.evil.example/jorden/claude-custom",
    "https://github.com/jorden",
    "https://github.com/jorden/../x",
    "https://github.com/-x/claude-custom",
    "/local/path/repo",
  ])("rejects %s", (url) => {
    expect(githubRepoFromUrl(url)).toBeNull();
  });
});

describe("repoFor", () => {
  let project: string;

  beforeEach(() => {
    project = fs.mkdtempSync(path.join(os.tmpdir(), "draft-repo-"));
    execFileSync("git", ["-C", project, "init", "-q"]);
  });

  afterEach(() => {
    fs.rmSync(project, { recursive: true, force: true });
  });

  it("reads owner and name from the origin remote", async () => {
    execFileSync("git", [
      "-C",
      project,
      "remote",
      "add",
      "origin",
      "git@github.com:jorden/claude-custom.git",
    ]);

    expect(await repoFor(project)).toBe("jorden/claude-custom");
  });

  it("returns null when origin is not on github.com", async () => {
    execFileSync("git", [
      "-C",
      project,
      "remote",
      "add",
      "origin",
      "https://gitlab.com/o/r.git",
    ]);

    expect(await repoFor(project)).toBeNull();
  });

  it("returns null when there is no origin", async () => {
    expect(await repoFor(project)).toBeNull();
  });
});
