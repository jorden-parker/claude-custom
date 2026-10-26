import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { CONSOLE_COMMANDS, CONSOLE_QUERIES, findCommand, toolsReportArgv } from "./console-commands";

describe("console commands", () => {
  let repo: string;
  const doctor = () => findCommand("doctor");
  const prepare = () => findCommand("prepare");
  const prepareEmbedding = () => findCommand("prepare-embedding");
  const prune = () => findCommand("prune");
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
      "prepare",
      "prepare-embedding",
      "prune",
      "review",
      "server-set",
      "server-apply",
      "speed-check",
      "tools-set",
      "messages-bench",
      "cache-probe",
      "review-eval",
      "bench-off-run",
      "bench-off-report",
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

  it("builds the prepare-embedding argv with no parameters", () => {
    expect(prepareEmbedding()?.argv({}, repo)).toEqual([`${repo}/bin/claude-ollama`, "prepare-embedding"]);
  });

  it("labels prepare-embedding", () => {
    expect(prepareEmbedding()?.label({})).toBe("Set up embedding model");
  });

  it("refuses prepare-embedding with parameters", () => {
    expect(prepareEmbedding()?.argv({ size: "27b" }, repo)).toBeNull();
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

  describe("benches", () => {
    beforeEach(() => {
      fs.writeFileSync(path.join(repo, "ollama", "settings.27b.json"), JSON.stringify({ model: "qwen-27b" }));
    });

    const command = (name: string) => findCommand(name);
    const messagesParams = { size: "27b", thinking: "disabled", prefix: "20000" };

    it("builds the messages bench argv with the size's model", () => {
      expect(command("messages-bench")?.argv(messagesParams, repo)).toEqual([
        `${repo}/bin/messages-bench`,
        "--model",
        "qwen-27b",
        "--thinking",
        "disabled",
        "--prefix-tokens",
        "20000",
      ]);
    });

    it("labels the messages bench with its choices", () => {
      expect(command("messages-bench")?.label(messagesParams)).toBe("Messages bench 27b (disabled, 20000)");
    });

    it("refuses a messages bench with a thinking mode or prefix outside the choices", () => {
      expect(command("messages-bench")?.argv({ ...messagesParams, thinking: "fast" }, repo)).toBeNull();
      expect(command("messages-bench")?.argv({ ...messagesParams, prefix: "123" }, repo)).toBeNull();
    });

    it("refuses a messages bench for an unconfigured size or an extra key", () => {
      expect(command("messages-bench")?.argv({ ...messagesParams, size: "35b" }, repo)).toBeNull();
      expect(command("messages-bench")?.argv({ ...messagesParams, extra: "x" }, repo)).toBeNull();
    });

    it("builds the cache probe argv for a configured size", () => {
      expect(command("cache-probe")?.argv({ size: "27b" }, repo)).toEqual([`${repo}/bin/ollama-cache-probe`, "27b"]);
      expect(command("cache-probe")?.label({ size: "27b" })).toBe("Cache probe (27b)");
      expect(command("cache-probe")?.argv({ size: "35b" }, repo)).toBeNull();
    });

    it("builds the review eval argv with the size's model", () => {
      expect(command("review-eval")?.argv({ size: "27b" }, repo)).toEqual([
        `${repo}/bin/pr-review-eval`,
        "--model",
        "qwen-27b",
      ]);
      expect(command("review-eval")?.argv({ size: "27b", extra: "x" }, repo)).toBeNull();
    });

    it("builds the bench-off run argv from the fixed servers and models", () => {
      expect(command("bench-off-run")?.argv({ server: "omlx-mtp", model: "qwen3.8-27b" }, repo)).toEqual([
        `${repo}/bin/backend-bench-off`,
        "run",
        "omlx-mtp",
        "qwen3.8-27b",
      ]);
      expect(command("bench-off-run")?.label({ server: "omlx-mtp", model: "qwen3.8-27b" })).toBe(
        "Bench-off omlx-mtp qwen3.8-27b",
      );
    });

    it("refuses a bench-off run with a server or model outside the choices", () => {
      expect(command("bench-off-run")?.argv({ server: "lmstudio", model: "qwen3.8-27b" }, repo)).toBeNull();
      expect(command("bench-off-run")?.argv({ server: "omlx", model: "qwen3.8-27b;ls" }, repo)).toBeNull();
    });

    it("builds the bench-off report argv and refuses any params", () => {
      expect(command("bench-off-report")?.argv({}, repo)).toEqual([`${repo}/bin/backend-bench-off`, "report"]);
      expect(command("bench-off-report")?.argv({ extra: "x" }, repo)).toBeNull();
    });
  });
});
