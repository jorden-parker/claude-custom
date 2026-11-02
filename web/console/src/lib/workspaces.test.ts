import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { listHistory } from "./history";
import {
  parseFrontmatter,
  projectSkills,
  readWorkspaces,
  setWorkspaceTrust,
} from "./workspaces";

function writeSkill(project: string, name: string, frontmatter: string): void {
  const dir = path.join(project, ".claude", "skills", name);
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(
    path.join(dir, "SKILL.md"),
    `---\n${frontmatter}\n---\nbody\n`,
  );
}

describe("workspaces", () => {
  let home: string;
  let project: string;
  let previous: { home?: string; state?: string };

  beforeEach(() => {
    home = fs.mkdtempSync(path.join(os.tmpdir(), "workspaces-home-"));
    project = fs.realpathSync(
      fs.mkdtempSync(path.join(os.tmpdir(), "workspaces-project-")),
    );
    previous = {
      home: process.env.HOME,
      state: process.env.CLAUDE_CONSOLE_STATE_DIR,
    };
    process.env.HOME = home;
    process.env.CLAUDE_CONSOLE_STATE_DIR = path.join(home, "state");
  });

  afterEach(() => {
    process.env.HOME = previous.home;
    if (previous.state === undefined) {
      delete process.env.CLAUDE_CONSOLE_STATE_DIR;
    } else {
      process.env.CLAUDE_CONSOLE_STATE_DIR = previous.state;
    }
    fs.rmSync(home, { recursive: true, force: true });
    fs.rmSync(project, { recursive: true, force: true });
  });

  it("lists nothing when the launcher has no session state yet", () => {
    expect(readWorkspaces()).toEqual({
      path: path.join(home, ".claude-ollama", ".claude.json"),
      workspaces: [],
    });
  });

  it("lists each recorded folder with its trust, existence and project skills", () => {
    writeSkill(project, "deploy", "name: deploy\ndescription: ship it");
    writeSkill(
      project,
      "notes",
      "name: notes\ndescription: user only\ndisable-model-invocation: true",
    );
    fs.mkdirSync(path.join(home, ".claude-ollama"));
    fs.writeFileSync(
      path.join(home, ".claude-ollama", ".claude.json"),
      JSON.stringify({
        hasCompletedOnboarding: true,
        projects: {
          [project]: { hasTrustDialogAccepted: true },
          "/gone/project": { allowedTools: [] },
        },
      }),
    );

    expect(readWorkspaces().workspaces).toEqual([
      { path: "/gone/project", trusted: false, exists: false, skills: [] },
      {
        path: project,
        trusted: true,
        exists: true,
        skills: [
          { name: "deploy", description: "ship it", modelInvocable: true },
          { name: "notes", description: "user only", modelInvocable: false },
        ],
      },
    ]);
  });

  it("trusts a folder by its real path, keeps the other keys and records the change", () => {
    fs.mkdirSync(path.join(home, ".claude-ollama"));
    fs.writeFileSync(
      path.join(home, ".claude-ollama", ".claude.json"),
      JSON.stringify({
        hasCompletedOnboarding: true,
        projects: { [project]: { allowedTools: ["Read"] } },
      }),
    );

    const result = setWorkspaceTrust(project, true);

    expect(result).toMatchObject({ ok: true });
    const saved = JSON.parse(
      fs.readFileSync(
        path.join(home, ".claude-ollama", ".claude.json"),
        "utf8",
      ),
    );
    expect(saved).toEqual({
      hasCompletedOnboarding: true,
      projects: {
        [project]: { allowedTools: ["Read"], hasTrustDialogAccepted: true },
      },
    });
    expect(listHistory().map((entry) => entry.kind)).toEqual([
      "workspace-trust",
    ]);
  });

  it("creates the session state when the launcher never ran", () => {
    const result = setWorkspaceTrust(project, true);

    expect(result).toMatchObject({
      ok: true,
      state: { workspaces: [{ path: project, trusted: true }] },
    });
  });

  it("untrusts a recorded folder even when it no longer exists", () => {
    fs.mkdirSync(path.join(home, ".claude-ollama"));
    fs.writeFileSync(
      path.join(home, ".claude-ollama", ".claude.json"),
      JSON.stringify({
        projects: { "/gone/project": { hasTrustDialogAccepted: true } },
      }),
    );

    const result = setWorkspaceTrust("/gone/project", false);

    expect(result).toMatchObject({
      ok: true,
      state: { workspaces: [{ path: "/gone/project", trusted: false }] },
    });
  });

  it("refuses a relative path and a folder that does not exist", () => {
    expect(setWorkspaceTrust("relative/path", true)).toEqual({
      ok: false,
      message: "Expected an absolute folder path",
    });
    expect(setWorkspaceTrust("/no/such/folder", true)).toEqual({
      ok: false,
      message: "/no/such/folder is not a folder on this machine",
    });
  });

  it("falls back to the folder name when a skill has no name field", () => {
    writeSkill(project, "lint", "description: tidy");

    expect(projectSkills(project)).toEqual([
      { name: "lint", description: "tidy", modelInvocable: true },
    ]);
  });

  it("parses only the frontmatter block", () => {
    expect(
      parseFrontmatter(
        "---\nname: a\ndescription: b: c\n---\nkey: not parsed\n",
      ),
    ).toEqual({
      name: "a",
      description: "b: c",
    });
    expect(parseFrontmatter("no frontmatter\n")).toEqual({});
  });
});
