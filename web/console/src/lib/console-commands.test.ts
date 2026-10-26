import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { CONSOLE_COMMANDS, findCommand } from "./console-commands";

describe("console commands", () => {
  let repo: string;
  const doctor = () => findCommand("doctor");
  const serverSet = () => findCommand("server-set");
  const serverApply = () => findCommand("server-apply");
  const speedCheck = () => findCommand("speed-check");
  const agent = () => `${repo}/bin/ollama-agent`;

  beforeEach(() => {
    repo = fs.mkdtempSync(path.join(os.tmpdir(), "console-commands-"));
    fs.mkdirSync(path.join(repo, "ollama"));
    fs.writeFileSync(path.join(repo, "ollama", "settings.27b.json"), "{}");
    fs.writeFileSync(path.join(repo, "ollama", "Modelfile.27b"), "");
  });

  afterEach(() => {
    fs.rmSync(repo, { recursive: true, force: true });
  });

  it("lists every console command", () => {
    expect(CONSOLE_COMMANDS.map((command) => command.name)).toEqual([
      "doctor",
      "server-set",
      "server-apply",
      "speed-check",
    ]);
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

  it("builds one -set pair per assignment", () => {
    expect(serverSet()?.argv({ assignments: "OLLAMA_KEEP_ALIVE=1h,OLLAMA_DEBUG=1" }, repo)).toEqual([
      agent(),
      "-set",
      "OLLAMA_KEEP_ALIVE=1h",
      "-set",
      "OLLAMA_DEBUG=1",
    ]);
  });

  it("labels server-set with its assignments", () => {
    expect(serverSet()?.label({ assignments: "OLLAMA_KEEP_ALIVE=1h,OLLAMA_DEBUG=1" })).toBe(
      "Set OLLAMA_KEEP_ALIVE=1h, OLLAMA_DEBUG=1",
    );
  });

  it("refuses server-set with an invalid, read-only, duplicate or empty assignment", () => {
    for (const assignments of [
      "OLLAMA_KEEP_ALIVE=30x",
      "OLLAMA_HOST=0.0.0.0",
      "OLLAMA_ORIGINS=*",
      "OLLAMA_DEBUG=1,OLLAMA_DEBUG=0",
      "OLLAMA_DEBUG",
      "",
    ]) {
      expect(serverSet()?.argv({ assignments }, repo)).toBeNull();
    }
  });

  it("refuses server-set with more than eight assignments", () => {
    const nine = Array.from({ length: 9 }, () => "OLLAMA_DEBUG=1");
    expect(serverSet()?.argv({ assignments: nine.join(",") }, repo)).toBeNull();
  });

  it("refuses server-set with an extra key", () => {
    expect(serverSet()?.argv({ assignments: "OLLAMA_DEBUG=1", size: "27b" }, repo)).toBeNull();
  });

  it("builds the server-apply argv with no parameters", () => {
    expect(serverApply()?.argv({}, repo)).toEqual([agent(), "-apply"]);
    expect(serverApply()?.label({})).toBe("Apply server.env");
    expect(serverApply()?.argv({ size: "27b" }, repo)).toBeNull();
  });

  it("builds the speed-check argv with no parameters", () => {
    expect(speedCheck()?.argv({}, repo)).toEqual([`${repo}/bin/claude-ollama`, "speed-check"]);
    expect(speedCheck()?.label({})).toBe("Speed check");
    expect(speedCheck()?.argv({ size: "27b" }, repo)).toBeNull();
  });

  it("returns undefined for an unknown command", () => {
    expect(findCommand("pull")).toBeUndefined();
  });
});
