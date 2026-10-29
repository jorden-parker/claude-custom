import { execFileSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { Draft } from "@/lib/draft-schema";
import { draftHash, readStoredDraft, saveDraft } from "@/lib/drafts";
import { DELETE, GET, PUT } from "./route";

vi.mock("next/server", async (importOriginal) => ({
  ...(await importOriginal<typeof import("next/server")>()),
  connection: async () => undefined,
}));

const PR_ID = "20260101-120000-pr-add-drafts";
const CREATED = "2026-01-01T12:00:00.000Z";
const ORIGIN = "git@github.com:jorden/claude-custom.git";

function prDraft(project: string): Draft {
  return {
    kind: "pr",
    id: PR_ID,
    project,
    base: "main",
    head: "feature-x",
    title: "Add drafts",
    sections: [{ heading: "Summary", body: "Adds drafts." }],
    created: CREATED,
  };
}

const context = (id: string) => ({ params: Promise.resolve({ id }) });

const jsonRequest = (method: string, body: unknown) =>
  new Request(`http://127.0.0.1:8808/api/drafts/${PR_ID}`, {
    method,
    headers: {
      "content-type": "application/json",
      origin: "http://127.0.0.1:8808",
    },
    body: JSON.stringify(body),
  });

describe("/api/drafts/[id]", () => {
  let draftsFolder: string;
  let project: string;
  let previousDir: string | undefined;

  beforeEach(() => {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), "drafts-route-"));
    draftsFolder = path.join(root, "drafts");
    project = path.join(root, "tree");
    fs.mkdirSync(project);
    execFileSync("git", ["-C", project, "init", "-q"]);
    execFileSync("git", ["-C", project, "remote", "add", "origin", ORIGIN]);
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

  describe("GET", () => {
    it("answers the draft, its hash and the repo it would post to", async () => {
      saveDraft(prDraft(project));

      const response = await GET(
        new Request("http://127.0.0.1:8808/"),
        context(PR_ID),
      );
      const body = await response.json();

      expect(response.status).toBe(200);
      expect(body).toMatchObject({
        draft: { title: "Add drafts" },
        repo: "jorden/claude-custom",
      });
      expect(body.hash).toBe(readStoredDraft(PR_ID)?.hash);
    });

    it("answers 404 for a draft that does not exist", async () => {
      const response = await GET(
        new Request("http://127.0.0.1:8808/"),
        context(PR_ID),
      );

      expect(response.status).toBe(404);
    });

    it("answers 404 for an id that is not a draft id", async () => {
      const response = await GET(
        new Request("http://127.0.0.1:8808/"),
        context("../escape"),
      );

      expect(response.status).toBe(404);
    });

    it("answers 422 with the reason for a file that is not a valid draft", async () => {
      fs.mkdirSync(draftsFolder, { recursive: true });
      fs.writeFileSync(path.join(draftsFolder, `${PR_ID}.json`), "{not json");

      const response = await GET(
        new Request("http://127.0.0.1:8808/"),
        context(PR_ID),
      );

      expect(response.status).toBe(422);
      expect(await response.json()).toEqual({ message: "not JSON" });
    });
  });

  describe("PUT", () => {
    it("saves the editable fields and answers the new hash", async () => {
      saveDraft(prDraft(project));
      const hash = readStoredDraft(PR_ID)?.hash;

      const response = await PUT(
        jsonRequest("PUT", { hash, title: "Renamed", base: "develop" }),
        context(PR_ID),
      );
      const body = await response.json();

      expect(response.status).toBe(200);
      expect(body).toMatchObject({ draft: { title: "Renamed", base: "main" } });
      expect(body.hash).toBe(
        draftHash(
          fs.readFileSync(path.join(draftsFolder, `${PR_ID}.json`), "utf8"),
        ),
      );
    });

    it("answers 409 when the hash differs from the file", async () => {
      saveDraft(prDraft(project));

      const response = await PUT(
        jsonRequest("PUT", { hash: "0".repeat(64), title: "Renamed" }),
        context(PR_ID),
      );

      expect(response.status).toBe(409);
      expect(readStoredDraft(PR_ID)?.parsed).toMatchObject({
        ok: true,
        draft: { title: "Add drafts" },
      });
    });

    it("answers 400 naming the problem for an invalid edit, and keeps the file", async () => {
      saveDraft(prDraft(project));
      const hash = readStoredDraft(PR_ID)?.hash;

      const response = await PUT(
        jsonRequest("PUT", { hash, title: "" }),
        context(PR_ID),
      );

      expect(response.status).toBe(400);
      expect(await response.json()).toEqual({
        message: "title must be one line of at most 256 characters",
      });
      expect(readStoredDraft(PR_ID)?.hash).toBe(hash);
    });

    it("answers 415 for a body that is not declared JSON", async () => {
      const response = await PUT(
        new Request(`http://127.0.0.1:8808/api/drafts/${PR_ID}`, {
          method: "PUT",
          headers: { "content-type": "text/plain" },
          body: JSON.stringify({ hash: "x", title: "y" }),
        }),
        context(PR_ID),
      );

      expect(response.status).toBe(415);
    });

    it("answers 400 when the hash is missing", async () => {
      saveDraft(prDraft(project));

      const response = await PUT(
        jsonRequest("PUT", { title: "Renamed" }),
        context(PR_ID),
      );

      expect(response.status).toBe(400);
    });

    it("answers 404 for a draft that does not exist", async () => {
      const response = await PUT(
        jsonRequest("PUT", { hash: "x", title: "y" }),
        context(PR_ID),
      );

      expect(response.status).toBe(404);
    });
  });

  describe("DELETE", () => {
    it("removes the draft, then answers 404", async () => {
      saveDraft(prDraft(project));

      expect(
        (await DELETE(new Request("http://127.0.0.1:8808/"), context(PR_ID)))
          .status,
      ).toBe(200);
      expect(
        (await DELETE(new Request("http://127.0.0.1:8808/"), context(PR_ID)))
          .status,
      ).toBe(404);
    });
  });
});
