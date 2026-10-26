import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { CONSOLE_COMMANDS, findCommand, toolsReportArgv } from "./console-commands";

describe("console commands", () => {
  let repo: string;
  const doctor = () => findCommand("doctor");
  const toolsSet = () => findCommand("tools-set");
  const BIN = () => `${repo}/bin/claude-tools`;

  beforeEach(() => {
    repo = fs.mkdtempSync(path.join(os.tmpdir(), "console-commands-"));
    fs.mkdirSync(path.join(repo, "ollama"));
    fs.writeFileSync(path.join(repo, "ollama", "settings.27b.json"), "{}");
    fs.writeFileSync(path.join(repo, "ollama", "Modelfile.27b"), "");
  });

  afterEach(() => {
    vi.unstubAllEnvs();
    fs.rmSync(repo, { recursive: true, force: true });
  });

  it("lists doctor and tools-set", () => {
    expect(CONSOLE_COMMANDS.map((command) => command.name)).toEqual(["doctor", "tools-set"]);
  });

  it("builds the doctor argv for a configured size", () => {
    expect(doctor()?.argv({ size: "27b" }, repo)).toEqual([`${repo}/bin/claude-ollama`, "doctor", "27b"]);
  });

  it("labels doctor with its size", () => {
    expect(doctor()?.label({ size: "27b" })).toBe("Doctor (27b)");
  });

  it("refuses a size that is not configured", () => {
    expect(doctor()?.argv({ size: "35b" }, repo)).toBeNull();
  });

  it("refuses a size that carries shell or flag text", () => {
    expect(doctor()?.argv({ size: "27b; rm -rf ~" }, repo)).toBeNull();
    expect(doctor()?.argv({ size: "--help" }, repo)).toBeNull();
  });

  it("refuses an extra key", () => {
    expect(doctor()?.argv({ size: "27b", extra: "x" }, repo)).toBeNull();
  });

  it("refuses a missing size", () => {
    expect(doctor()?.argv({}, repo)).toBeNull();
  });

  it("returns undefined for an unknown command", () => {
    expect(findCommand("pull")).toBeUndefined();
  });

  it("builds one -set per assignment with the user scope last", () => {
    expect(toolsSet()?.argv({ assignments: "WebFetch=deny;Bash=allow,off" }, repo)).toEqual([
      BIN(),
      "-set",
      "WebFetch=deny",
      "-set",
      "Bash=allow,off",
      "user",
    ]);
  });

  it("passes the settings override as the scope when CONSOLE_TOOLS_SETTINGS is set", () => {
    vi.stubEnv("CONSOLE_TOOLS_SETTINGS", "/tmp/fixture/settings.json");
    expect(toolsSet()?.argv({ assignments: "Read=ask" }, repo)).toEqual([
      BIN(),
      "-set",
      "Read=ask",
      "-settings",
      "/tmp/fixture/settings.json",
    ]);
  });

  it("labels tools-set with its number of changes", () => {
    expect(toolsSet()?.label({ assignments: "Read=ask;Bash=deny" })).toBe("Tool permissions (2 changes)");
  });

  it("accepts the forty-item limit and refuses forty-one", () => {
    const forty = Array.from({ length: 40 }, (_, index) => `Tool${index}=deny`).join(";");
    expect(toolsSet()?.argv({ assignments: forty }, repo)).not.toBeNull();
    expect(toolsSet()?.argv({ assignments: `${forty};Extra=deny` }, repo)).toBeNull();
  });

  it("refuses a name with parentheses, a scoped rule, or a name joined by a semicolon", () => {
    expect(toolsSet()?.argv({ assignments: "Bash(git log *)=deny" }, repo)).toBeNull();
    expect(toolsSet()?.argv({ assignments: "Bash;WebFetch=deny" }, repo)).toBeNull();
    expect(toolsSet()?.argv({ assignments: "Bash" }, repo)).toBeNull();
  });

  it("refuses an unknown permission or off with deny or default", () => {
    expect(toolsSet()?.argv({ assignments: "Bash=maybe" }, repo)).toBeNull();
    expect(toolsSet()?.argv({ assignments: "Bash=deny,off" }, repo)).toBeNull();
    expect(toolsSet()?.argv({ assignments: "Bash=default,off" }, repo)).toBeNull();
  });

  it("refuses an empty or missing assignments value", () => {
    expect(toolsSet()?.argv({ assignments: "" }, repo)).toBeNull();
    expect(toolsSet()?.argv({}, repo)).toBeNull();
  });

  it("builds the report argv with the user scope and the override", () => {
    expect(toolsReportArgv(repo)).toEqual([BIN(), "-json", "user"]);
    vi.stubEnv("CONSOLE_TOOLS_SETTINGS", "/tmp/fixture/settings.json");
    expect(toolsReportArgv(repo)).toEqual([BIN(), "-json", "-settings", "/tmp/fixture/settings.json"]);
  });
});
