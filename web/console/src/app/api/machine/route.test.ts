import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { listHistory, restoreChange } from "@/lib/history";
import { GET, PUT } from "./route";

vi.mock("next/server", async (importOriginal) => ({
  ...(await importOriginal<typeof import("next/server")>()),
  connection: async () => undefined,
}));

const ORIGIN = "http://127.0.0.1:8808";

const jsonRequest = (body: unknown) =>
  new Request(`${ORIGIN}/api/machine`, {
    method: "PUT",
    headers: { "content-type": "application/json", origin: ORIGIN },
    body: JSON.stringify(body),
  });

function restoreEnv(name: string, value: string | undefined): void {
  if (value === undefined) {
    delete process.env[name];
  } else {
    process.env[name] = value;
  }
}

describe("/api/machine", () => {
  let configHome: string;
  let stateDir: string;
  let repoDir: string;
  let machineFolder: string;
  let ghReposPath: string;
  let previous: { xdg?: string; state?: string; repo?: string };

  beforeEach(() => {
    configHome = fs.mkdtempSync(
      path.join(os.tmpdir(), "machine-route-config-"),
    );
    stateDir = fs.mkdtempSync(path.join(os.tmpdir(), "machine-route-state-"));
    repoDir = fs.mkdtempSync(path.join(os.tmpdir(), "machine-route-repo-"));
    machineFolder = path.join(configHome, "claude-custom");
    ghReposPath = path.join(machineFolder, "gh-repos");
    fs.mkdirSync(path.join(repoDir, "personal"));
    fs.writeFileSync(
      path.join(repoDir, "personal", "settings.tokens.json"),
      JSON.stringify({
        permissions: { deny: ["Artifact", "Workflow", "Read(**/dist/**)"] },
      }),
    );
    previous = {
      xdg: process.env.XDG_CONFIG_HOME,
      state: process.env.CLAUDE_CONSOLE_STATE_DIR,
      repo: process.env.CLAUDE_CUSTOM_HOME,
    };
    process.env.XDG_CONFIG_HOME = configHome;
    process.env.CLAUDE_CONSOLE_STATE_DIR = stateDir;
    process.env.CLAUDE_CUSTOM_HOME = repoDir;
  });

  afterEach(() => {
    restoreEnv("XDG_CONFIG_HOME", previous.xdg);
    restoreEnv("CLAUDE_CONSOLE_STATE_DIR", previous.state);
    restoreEnv("CLAUDE_CUSTOM_HOME", previous.repo);
    fs.rmSync(configHome, { recursive: true, force: true });
    fs.rmSync(stateDir, { recursive: true, force: true });
    fs.rmSync(repoDir, { recursive: true, force: true });
  });

  it("lists the two editable files, fetch-domains and sandbox-off", async () => {
    const body = await (await GET()).json();

    expect(Object.keys(body.files)).toEqual([
      "gh-repos",
      "enabled-tools",
      "fetch-domains",
    ]);
    expect(body.dir).toBe(machineFolder);
    expect(body.sandboxOff).toEqual({
      exists: false,
      path: path.join(machineFolder, "sandbox-off"),
    });
    expect(body.knownTools).toEqual(["Artifact", "Workflow"]);
    expect(body.files["fetch-domains"]).toMatchObject({
      count: 0,
      editor: "/fetch-domains",
    });
  });

  it("answers a missing file as null text and each line with its reason", async () => {
    const empty = await (await GET()).json();
    expect(empty.files["enabled-tools"]).toMatchObject({
      text: null,
      valid: [],
      invalid: [],
    });

    fs.mkdirSync(machineFolder, { recursive: true });
    fs.writeFileSync(ghReposPath, "acme/web\nacme\n");
    const body = await (await GET()).json();

    expect(body.files["gh-repos"]).toMatchObject({
      text: "acme/web\nacme\n",
      valid: ["acme/web"],
      invalid: [{ line: "acme", reason: "expected owner/name" }],
    });
  });

  it("saves gh-repos 0600 and records one machine-gh-repos history entry", async () => {
    const response = await PUT(
      jsonRequest({ file: "gh-repos", lines: ["acme/web", "acme/api"] }),
    );

    expect(response.status).toBe(200);
    expect(await response.json()).toMatchObject({
      files: { "gh-repos": { text: "acme/web\nacme/api\n" } },
    });
    expect(fs.statSync(ghReposPath).mode & 0o777).toBe(0o600);
    const entries = listHistory();
    expect(entries).toHaveLength(1);
    expect(entries[0]).toMatchObject({
      kind: "machine-gh-repos",
      source: "console",
      before: null,
      path: ghReposPath,
    });
  });

  it("restores the text from before a save through its history entry", async () => {
    await PUT(jsonRequest({ file: "gh-repos", lines: ["acme/web"] }));
    await PUT(jsonRequest({ file: "gh-repos", lines: ["acme/api"] }));

    expect(restoreChange(listHistory()[0].id)).toMatchObject({ ok: true });
    expect(fs.readFileSync(ghReposPath, "utf8")).toBe("acme/web\n");
  });

  it("rejects a line that is not a repo with 400 naming it, and writes nothing", async () => {
    const response = await PUT(
      jsonRequest({ file: "gh-repos", lines: ["owner"] }),
    );

    expect(response.status).toBe(400);
    expect(await response.json()).toEqual({
      message: "owner: expected owner/name",
    });
    expect(fs.existsSync(ghReposPath)).toBe(false);
    expect(listHistory()).toEqual([]);
  });

  it("rejects more than 200 lines with 400", async () => {
    const lines = Array.from(
      { length: 201 },
      (_, index) => `acme/repo${index}`,
    );

    const response = await PUT(jsonRequest({ file: "gh-repos", lines }));

    expect(response.status).toBe(400);
    expect(await response.json()).toEqual({ message: "at most 200 lines" });
  });

  it.each(["fetch-domains", "sandbox-off", "../gh-repos"])(
    "refuses %s with 400, since this page does not edit it",
    async (file) => {
      const response = await PUT(jsonRequest({ file, lines: ["go.dev"] }));

      expect(response.status).toBe(400);
      expect(await response.json()).toEqual({
        message: "Expected file to be one of gh-repos, enabled-tools",
      });
      expect(listHistory()).toEqual([]);
    },
  );

  it("saves enabled-tools for a bare name the overlay denies and refuses any other name", async () => {
    expect(
      (await PUT(jsonRequest({ file: "enabled-tools", lines: ["Artifact"] })))
        .status,
    ).toBe(200);

    const refused = await PUT(
      jsonRequest({ file: "enabled-tools", lines: ["Bash"] }),
    );

    expect(refused.status).toBe(400);
    expect(await refused.json()).toEqual({
      message: "Bash: not a bare tool name in the overlay's deny list",
    });
  });

  it("rejects a body that is not declared JSON with 415", async () => {
    const response = await PUT(
      new Request(`${ORIGIN}/api/machine`, {
        method: "PUT",
        headers: { "content-type": "text/plain" },
        body: JSON.stringify({ file: "gh-repos", lines: ["acme/web"] }),
      }),
    );

    expect(response.status).toBe(415);
  });

  it("rejects a body that is not JSON, or lacks lines as a string list, with 400", async () => {
    const notJson = await PUT(
      new Request(`${ORIGIN}/api/machine`, {
        method: "PUT",
        headers: { "content-type": "application/json" },
        body: "{not json",
      }),
    );
    const linesNotList = await PUT(
      jsonRequest({ file: "gh-repos", lines: "acme/web" }),
    );

    expect(notJson.status).toBe(400);
    expect(linesNotList.status).toBe(400);
  });

  it("answers 409 and records nothing when the file is a symlink", async () => {
    const target = path.join(configHome, "elsewhere");
    fs.writeFileSync(target, "keep\n");
    fs.mkdirSync(machineFolder, { recursive: true });
    fs.symlinkSync(target, ghReposPath);

    const response = await PUT(
      jsonRequest({ file: "gh-repos", lines: ["acme/web"] }),
    );

    expect(response.status).toBe(409);
    expect(fs.readFileSync(target, "utf8")).toBe("keep\n");
    expect(listHistory()).toEqual([]);
  });
});
