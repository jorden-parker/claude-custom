import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { CONSOLE_COMMANDS, findCommand } from "./console-commands";

describe("console commands", () => {
  let repo: string;
  const doctor = () => findCommand("doctor");

  beforeEach(() => {
    repo = fs.mkdtempSync(path.join(os.tmpdir(), "console-commands-"));
    fs.mkdirSync(path.join(repo, "ollama"));
    fs.writeFileSync(path.join(repo, "ollama", "settings.27b.json"), JSON.stringify({ model: "qwen-27b" }));
    fs.writeFileSync(path.join(repo, "ollama", "Modelfile.27b"), "");
  });

  afterEach(() => {
    fs.rmSync(repo, { recursive: true, force: true });
  });

  it("lists doctor as the only command", () => {
    expect(CONSOLE_COMMANDS.map((command) => command.name)).toEqual([
      "doctor",
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

  it("returns undefined for an unknown command", () => {
    expect(findCommand("pull")).toBeUndefined();
  });

  describe("benches", () => {
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
