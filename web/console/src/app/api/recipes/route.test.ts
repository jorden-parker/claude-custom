import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { GET } from "./route";

vi.mock("next/server", async (importOriginal) => ({
  ...(await importOriginal<typeof import("next/server")>()),
  connection: async () => undefined,
}));

describe("/api/recipes", () => {
  let repo: string;

  beforeEach(() => {
    repo = fs.mkdtempSync(path.join(os.tmpdir(), "recipes-route-"));
    fs.mkdirSync(path.join(repo, "ollama", "recipes"), { recursive: true });
    process.env.CLAUDE_CUSTOM_HOME = repo;
  });

  afterEach(() => {
    delete process.env.CLAUDE_CUSTOM_HOME;
    fs.rmSync(repo, { recursive: true, force: true });
  });

  it("lists each hook's recipes from ollama/recipes/*.json", async () => {
    fs.writeFileSync(
      path.join(repo, "ollama", "recipes", "tdd-guard.json"),
      JSON.stringify([
        {
          match: "edit or add the test first",
          steps: ["edit the test", "run it"],
        },
      ]),
    );
    fs.writeFileSync(
      path.join(repo, "ollama", "recipes", "bash-output-guard.json"),
      JSON.stringify([{ match: "unbounded", steps: ["add | head -50"] }]),
    );
    fs.writeFileSync(
      path.join(repo, "ollama", "recipes", "README.md"),
      "ignored",
    );

    const response = await GET();

    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({
      recipes: [
        {
          hook: "bash-output-guard",
          entries: [{ match: "unbounded", steps: ["add | head -50"] }],
        },
        {
          hook: "tdd-guard",
          entries: [
            {
              match: "edit or add the test first",
              steps: ["edit the test", "run it"],
            },
          ],
        },
      ],
    });
  });

  it("answers an empty list when the folder is missing", async () => {
    fs.rmSync(path.join(repo, "ollama", "recipes"), { recursive: true });

    const response = await GET();

    expect(await response.json()).toEqual({ recipes: [] });
  });
});
