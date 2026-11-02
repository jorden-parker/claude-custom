import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { listHistory } from "./history";
import {
  listProfiles,
  profileFilePath,
  profileIds,
  profileKind,
  profileProblem,
  readOverride,
  saveOverride,
  sizeOfProfile,
} from "./profiles";

describe("profiles", () => {
  let configHome: string;
  let stateDir: string;
  let repoDir: string;
  let previous: Record<string, string | undefined>;

  beforeEach(() => {
    configHome = fs.mkdtempSync(path.join(os.tmpdir(), "profiles-config-"));
    stateDir = fs.mkdtempSync(path.join(os.tmpdir(), "profiles-state-"));
    repoDir = fs.mkdtempSync(path.join(os.tmpdir(), "profiles-repo-"));
    previous = {
      XDG_CONFIG_HOME: process.env.XDG_CONFIG_HOME,
      CLAUDE_CONSOLE_STATE_DIR: process.env.CLAUDE_CONSOLE_STATE_DIR,
      CLAUDE_CUSTOM_HOME: process.env.CLAUDE_CUSTOM_HOME,
      CLAUDE_CUSTOM_HISTORY: process.env.CLAUDE_CUSTOM_HISTORY,
    };
    process.env.XDG_CONFIG_HOME = configHome;
    process.env.CLAUDE_CONSOLE_STATE_DIR = stateDir;
    process.env.CLAUDE_CUSTOM_HOME = repoDir;
    delete process.env.CLAUDE_CUSTOM_HISTORY;
    writeSizes();
  });

  afterEach(() => {
    for (const [name, value] of Object.entries(previous)) {
      restoreEnv(name, value);
    }
    for (const folder of [configHome, stateDir, repoDir]) {
      fs.rmSync(folder, { recursive: true, force: true });
    }
  });

  function writeSizes(): void {
    fs.mkdirSync(path.join(repoDir, "ollama"), { recursive: true });
    fs.writeFileSync(
      path.join(repoDir, "ollama", "sizes.json"),
      JSON.stringify({
        "27b": { base: "qwen3.8:27b-mlx", model: "qwen3.8-27b-cc", context: 65536, parameters: { temperature: 0.7 } },
      }),
    );
    fs.writeFileSync(path.join(repoDir, "ollama", "settings.27b.json"), JSON.stringify({ model: "qwen3.8-27b-cc" }));
    fs.writeFileSync(path.join(repoDir, "ollama", "Modelfile.27b"), "FROM qwen3.8:27b-mlx\n");
  }

  it("lists claude-code and one profile per configured size", () => {
    expect(profileIds()).toEqual(["claude-code", "ollama-27b"]);
    expect(profileKind("claude-code")).toBe("claude-code");
    expect(profileKind("ollama-27b")).toBe("ollama");
    expect(sizeOfProfile("ollama-27b")).toBe("27b");
    expect(sizeOfProfile("claude-code")).toBeNull();
  });

  it("summarises each profile with its model, context and override count", () => {
    saveOverride("ollama-27b", { context: 32768, env: { CLAUDE_OLLAMA_CMUX: "0" } });

    expect(listProfiles()).toEqual([
      { id: "claude-code", title: "Claude Code", kind: "claude-code", model: null, context: null, overrides: 0 },
      {
        id: "ollama-27b",
        title: "Ollama 27b",
        kind: "ollama",
        model: "qwen3.8-27b-cc",
        context: 65536,
        overrides: 2,
      },
    ]);
  });

  it("reads an empty object when no override file exists", () => {
    expect(readOverride("claude-code")).toEqual({});
  });

  it("writes the override as a 0600 file in a 0700 folder and reads it back", () => {
    saveOverride("claude-code", { sandbox: false, tools: { WebFetch: "deny" } });

    const target = profileFilePath("claude-code");
    expect(target).toBe(path.join(configHome, "claude-custom", "profiles", "claude-code.json"));
    expect(fs.statSync(target).mode & 0o777).toBe(0o600);
    expect(fs.statSync(path.dirname(target)).mode & 0o777).toBe(0o700);
    expect(readOverride("claude-code")).toEqual({ sandbox: false, tools: { WebFetch: "deny" } });
  });

  it("deletes the file when the override is empty (Reset to defaults)", () => {
    saveOverride("claude-code", { sandbox: false });
    saveOverride("claude-code", {});

    expect(fs.existsSync(profileFilePath("claude-code"))).toBe(false);
    expect(readOverride("claude-code")).toEqual({});
  });

  it("refuses to write through a symlinked override file", () => {
    const elsewhere = path.join(configHome, "elsewhere.json");
    fs.writeFileSync(elsewhere, "{}\n");
    fs.mkdirSync(path.dirname(profileFilePath("claude-code")), { recursive: true });
    fs.symlinkSync(elsewhere, profileFilePath("claude-code"));

    expect(profileProblem("claude-code")).toContain("is a symlink");
    expect(() => saveOverride("claude-code", { sandbox: false })).toThrow("is a symlink");
    expect(fs.readFileSync(elsewhere, "utf8")).toBe("{}\n");
  });

  it("refuses when the profiles folder is a symlink", () => {
    const elsewhere = path.join(configHome, "elsewhere");
    fs.mkdirSync(elsewhere);
    fs.mkdirSync(path.join(configHome, "claude-custom"), { recursive: true });
    fs.symlinkSync(elsewhere, path.join(configHome, "claude-custom", "profiles"));

    expect(profileProblem("claude-code")).toContain("is a symlink");
  });

  it("records each change in history and none for a no-op save", () => {
    saveOverride("claude-code", { sandbox: false });
    saveOverride("claude-code", { sandbox: false });

    const entries = listHistory();
    expect(entries).toHaveLength(1);
    expect(entries[0].kind).toBe("profile");
    expect(entries[0].path).toBe(profileFilePath("claude-code"));
  });
});

function restoreEnv(name: string, value: string | undefined): void {
  if (value === undefined) {
    delete process.env[name];
  } else {
    process.env[name] = value;
  }
}
