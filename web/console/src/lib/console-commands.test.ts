import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
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

  it("lists doctor and review", () => {
    expect(CONSOLE_COMMANDS.map((command) => command.name)).toEqual(["doctor", "review"]);
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

  describe("review", () => {
    const review = () => findCommand("review");

    beforeEach(() => {
      vi.stubEnv("CONSOLE_PROJECT_DIR", repo);
    });

    afterEach(() => {
      vi.unstubAllEnvs();
    });

    it("builds the review argv for a configured size and PR number", () => {
      expect(review()?.argv({ size: "27b", pr: "12" }, repo)).toEqual([
        `${repo}/bin/claude-ollama`,
        "review",
        "27b",
        "12",
      ]);
    });

    it("labels review with its PR number and size", () => {
      expect(review()?.label({ size: "27b", pr: "12" })).toBe("Review PR 12 (27b)");
    });

    it("runs in the project folder the console was started from", () => {
      expect(review()?.cwd?.()).toBe(repo);
    });

    it("refuses a PR value that is not a positive number", () => {
      for (const pr of ["0", "12abc", "--post", "https://github.com/x/y/pull/1", "feature-branch"]) {
        expect(review()?.argv({ size: "27b", pr }, repo)).toBeNull();
      }
    });

    it("refuses an extra key such as post", () => {
      expect(review()?.argv({ size: "27b", pr: "12", post: "1" }, repo)).toBeNull();
    });

    it("refuses a size that is not configured", () => {
      expect(review()?.argv({ size: "35b", pr: "12" }, repo)).toBeNull();
    });

    it("refuses to run when the console has no project folder", () => {
      vi.stubEnv("CONSOLE_PROJECT_DIR", "");
      expect(review()?.argv({ size: "27b", pr: "12" }, repo)).toBeNull();
    });

    it("refuses a project folder that is not a directory", () => {
      vi.stubEnv("CONSOLE_PROJECT_DIR", path.join(repo, "ollama", "Modelfile.27b"));
      expect(review()?.argv({ size: "27b", pr: "12" }, repo)).toBeNull();
    });
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
