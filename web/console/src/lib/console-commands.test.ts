import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { CONSOLE_COMMANDS, findCommand } from "./console-commands";

describe("console commands", () => {
  let repo: string;
  const doctor = () => findCommand("doctor");
  const prepare = () => findCommand("prepare");
  const prune = () => findCommand("prune");

  beforeEach(() => {
    repo = fs.mkdtempSync(path.join(os.tmpdir(), "console-commands-"));
    fs.mkdirSync(path.join(repo, "ollama"));
    fs.writeFileSync(path.join(repo, "ollama", "settings.27b.json"), "{}");
    fs.writeFileSync(path.join(repo, "ollama", "Modelfile.27b"), "");
  });

  afterEach(() => {
    fs.rmSync(repo, { recursive: true, force: true });
  });

  it("lists the commands the console may start", () => {
    expect(CONSOLE_COMMANDS.map((command) => command.name)).toEqual(["doctor", "prepare", "prune"]);
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

  it("builds the prepare argv for a configured size", () => {
    expect(prepare()?.argv({ size: "27b" }, repo)).toEqual([`${repo}/bin/claude-ollama`, "prepare", "27b"]);
  });

  it("labels prepare with its size", () => {
    expect(prepare()?.label({ size: "27b" })).toBe("Prepare 27b");
  });

  it("refuses to prepare a size that is not configured", () => {
    expect(prepare()?.argv({ size: "35b" }, repo)).toBeNull();
    expect(prepare()?.argv({ size: "27b; rm -rf ~" }, repo)).toBeNull();
  });

  it("builds the prune argv with --yes and --only before each name", () => {
    expect(prune()?.argv({ names: "ollama.com/x:latest,qwen3-old:7b" }, repo)).toEqual([
      `${repo}/bin/ollama-models`,
      "prune",
      "--yes",
      "--only",
      "ollama.com/x:latest",
      "qwen3-old:7b",
    ]);
  });

  it("labels prune with the number of models", () => {
    expect(prune()?.label({ names: "a,b,c" })).toBe("Prune 3 models");
    expect(prune()?.label({ names: "a" })).toBe("Prune 1 model");
  });

  it("refuses prune names that could be read as flags, spaces or shell text", () => {
    expect(prune()?.argv({ names: "-rf" }, repo)).toBeNull();
    expect(prune()?.argv({ names: "a,--yes" }, repo)).toBeNull();
    expect(prune()?.argv({ names: "bad name" }, repo)).toBeNull();
    expect(prune()?.argv({ names: "a;rm" }, repo)).toBeNull();
  });

  it("refuses an empty prune list and more than 50 names", () => {
    expect(prune()?.argv({ names: "" }, repo)).toBeNull();
    const fiftyOne = Array.from({ length: 51 }, (_, index) => `m${index}`).join(",");
    expect(prune()?.argv({ names: fiftyOne }, repo)).toBeNull();
  });

  it("returns undefined for an unknown command", () => {
    expect(findCommand("pull")).toBeUndefined();
  });
});
