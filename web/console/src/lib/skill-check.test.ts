import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { makeFixtureRepo, type FixtureRepo } from "./profile-fixture";
import { checkWorkspaceSkills } from "./skill-check";

function writeSkill(project: string, name: string): void {
  const dir = path.join(project, ".claude", "skills", name);
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(
    path.join(dir, "SKILL.md"),
    `---\nname: ${name}\ndescription: ${name}\n---\nbody\n`,
  );
}

function stubScript(repoDir: string, body: string): void {
  const script = path.join(repoDir, "bin", "skill-check");
  fs.mkdirSync(path.dirname(script), { recursive: true });
  fs.writeFileSync(script, `#!/usr/bin/env bash\n${body}\n`, { mode: 0o755 });
}

describe("checkWorkspaceSkills", () => {
  let fixture: FixtureRepo;
  let home: string;
  let project: string;
  const previous: Record<string, string | undefined> = {};

  beforeEach(() => {
    fixture = makeFixtureRepo();
    home = fs.mkdtempSync(path.join(os.tmpdir(), "skill-check-home-"));
    project = fs.realpathSync(
      fs.mkdtempSync(path.join(os.tmpdir(), "skill-check-project-")),
    );
    for (const [name, value] of [
      ["HOME", home],
      ["CLAUDE_CONSOLE_STATE_DIR", fixture.stateDir],
      ["CLAUDE_CUSTOM_HOME", fixture.repoDir],
    ]) {
      previous[name] = process.env[name];
      process.env[name] = value;
    }
    fs.mkdirSync(fixture.stateDir, { recursive: true });
    fs.mkdirSync(path.join(home, ".claude-ollama"));
    fs.writeFileSync(
      path.join(home, ".claude-ollama", ".claude.json"),
      JSON.stringify({
        projects: { [project]: { hasTrustDialogAccepted: true }, "/gone": {} },
      }),
    );
  });

  afterEach(() => {
    for (const [name, value] of Object.entries(previous)) {
      if (value === undefined) {
        delete process.env[name];
      } else {
        process.env[name] = value;
      }
    }
    fixture.cleanup();
    fs.rmSync(home, { recursive: true, force: true });
    fs.rmSync(project, { recursive: true, force: true });
  });

  it("runs the script in the folder with the size and names the skills Claude Code missed", async () => {
    writeSkill(project, "deploy");
    writeSkill(project, "broken");
    stubScript(
      fixture.repoDir,
      `printf '%s\\n' "$*" > "${fixture.stateDir}/argv"; echo '{"claude_version":"2.1.316 (Claude Code)","skills":["deploy","handoff"],"error":null}'`,
    );

    const result = await checkWorkspaceSkills(project, "27b");

    expect(result).toEqual({
      ok: true,
      check: {
        version: "2.1.316 (Claude Code)",
        discovered: ["deploy", "handoff"],
        missing: ["broken"],
        error: null,
      },
    });
    expect(fs.readFileSync(path.join(fixture.stateDir, "argv"), "utf8")).toBe(
      `--size 27b ${project}\n`,
    );
  });

  it("uses the first configured size by default and passes the script's error through", async () => {
    writeSkill(project, "deploy");
    stubScript(
      fixture.repoDir,
      `printf '%s\\n' "$*" > "${fixture.stateDir}/argv"; echo '{"claude_version":null,"skills":null,"error":"claude exited before its session started: model missing"}'; exit 1`,
    );

    const result = await checkWorkspaceSkills(project, undefined);

    expect(result).toEqual({
      ok: true,
      check: {
        version: null,
        discovered: [],
        missing: [],
        error: "claude exited before its session started: model missing",
      },
    });
    expect(fs.readFileSync(path.join(fixture.stateDir, "argv"), "utf8")).toBe(
      `--size 27b ${project}\n`,
    );
  });

  it("refuses a folder that is not recorded or no longer exists", async () => {
    stubScript(fixture.repoDir, "exit 0");

    expect(await checkWorkspaceSkills("/gone", undefined)).toEqual({
      ok: false,
      message: "/gone is not a recorded folder on this machine",
    });
    expect(await checkWorkspaceSkills(os.tmpdir(), undefined)).toEqual({
      ok: false,
      message: `${os.tmpdir()} is not a recorded folder on this machine`,
    });
  });

  it("refuses an untrusted folder before starting anything", async () => {
    fs.writeFileSync(
      path.join(home, ".claude-ollama", ".claude.json"),
      JSON.stringify({
        projects: { [project]: { hasTrustDialogAccepted: false } },
      }),
    );
    stubScript(fixture.repoDir, `touch "${fixture.stateDir}/started"`);

    expect(await checkWorkspaceSkills(project, undefined)).toEqual({
      ok: false,
      message: `${project} is not trusted; a print-mode session there would run the folder's own hooks`,
    });
    expect(fs.existsSync(path.join(fixture.stateDir, "started"))).toBe(false);
  });

  it("refuses a size that is not configured", async () => {
    stubScript(fixture.repoDir, "exit 0");

    expect(await checkWorkspaceSkills(project, "99b")).toEqual({
      ok: false,
      message: "Unknown size 99b",
    });
  });

  it("reports a script that printed no JSON", async () => {
    stubScript(fixture.repoDir, "echo boom >&2; exit 2");

    expect(await checkWorkspaceSkills(project, undefined)).toEqual({
      ok: false,
      message: "skill-check failed (exit 2): boom",
    });
  });
});
