import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { CONSOLE_COMMANDS, CONSOLE_QUERIES, findCommand } from "./console-commands";

describe("console commands", () => {
  let repo: string;
  const doctor = () => findCommand("doctor");

  beforeEach(() => {
    repo = fs.mkdtempSync(path.join(os.tmpdir(), "console-commands-"));
    fs.mkdirSync(path.join(repo, "ollama"));
    fs.writeFileSync(path.join(repo, "ollama", "settings.27b.json"), "{}");
    fs.writeFileSync(path.join(repo, "ollama", "Modelfile.27b"), "");
  });

  afterEach(() => {
    fs.rmSync(repo, { recursive: true, force: true });
  });

  it("lists doctor as the only command", () => {
    expect(CONSOLE_COMMANDS.map((command) => command.name)).toEqual(["doctor"]);
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
});

describe("console queries", () => {
  let repo: string;

  beforeEach(() => {
    repo = fs.mkdtempSync(path.join(os.tmpdir(), "console-queries-"));
    fs.mkdirSync(path.join(repo, "ollama"));
    fs.writeFileSync(path.join(repo, "ollama", "settings.27b.json"), "{}");
    fs.writeFileSync(path.join(repo, "ollama", "Modelfile.27b"), "");
  });

  afterEach(() => {
    fs.rmSync(repo, { recursive: true, force: true });
  });

  it("builds the print-config argv for a configured size", () => {
    expect(CONSOLE_QUERIES.printConfig.argv({ size: "27b" }, repo)).toEqual([
      `${repo}/bin/claude-ollama`,
      "--print-config",
      "27b",
    ]);
  });

  it("refuses a print-config size that is not configured", () => {
    expect(CONSOLE_QUERIES.printConfig.argv({ size: "35b" }, repo)).toBeNull();
    expect(CONSOLE_QUERIES.printConfig.argv({ size: "27b --help" }, repo)).toBeNull();
  });

  it("refuses print-config with an extra key or no size", () => {
    expect(CONSOLE_QUERIES.printConfig.argv({ size: "27b", extra: "x" }, repo)).toBeNull();
    expect(CONSOLE_QUERIES.printConfig.argv({}, repo)).toBeNull();
  });

  it("builds the logs path argv with no parameters", () => {
    expect(CONSOLE_QUERIES.logPath.argv({}, repo)).toEqual([`${repo}/bin/claude-ollama`, "logs", "--path"]);
  });

  it("refuses any parameter for the logs path query", () => {
    expect(CONSOLE_QUERIES.logPath.argv({ path: "/etc/passwd" }, repo)).toBeNull();
  });
});
