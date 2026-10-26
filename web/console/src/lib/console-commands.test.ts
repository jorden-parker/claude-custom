import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { CONSOLE_COMMANDS, CONSOLE_QUERIES, findCommand, toolsReportArgv } from "./console-commands";

describe("console commands", () => {
  let repo: string;
  const doctor = () => findCommand("doctor");
  const serverSet = () => findCommand("server-set");
  const serverApply = () => findCommand("server-apply");
  const speedCheck = () => findCommand("speed-check");
  const agent = () => `${repo}/bin/ollama-agent`;
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

  it("lists every console command", () => {
    expect(CONSOLE_COMMANDS.map((command) => command.name)).toEqual([
      "doctor",
      "review",
      "server-set",
      "server-apply",
      "speed-check",
      "tools-set",
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
    expect(
      serverSet()?.label({
        assignments: "OLLAMA_KEEP_ALIVE=1h,OLLAMA_DEBUG=1",
      }),
    ).toBe("Set OLLAMA_KEEP_ALIVE=1h, OLLAMA_DEBUG=1");
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
