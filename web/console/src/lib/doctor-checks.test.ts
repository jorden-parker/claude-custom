import { describe, expect, it } from "vitest";
import { checksFromLines, doctorSummary, parseDoctorLine, parseOutdatedLine } from "./doctor-checks";

describe("parseDoctorLine", () => {
  it("reads an ok check", () => {
    expect(parseDoctorLine("ok   jq on PATH")).toEqual({ level: "ok", text: "jq on PATH" });
  });

  it("reads a warn check", () => {
    expect(parseDoctorLine("warn context mismatch on 27b")).toEqual({
      level: "warn",
      text: "context mismatch on 27b",
    });
  });

  it("reads a fail check with its own parentheses", () => {
    expect(
      parseDoctorLine("fail weights NAME sha256 is X, not the pinned Y (claude-ollama prepare 27b)"),
    ).toEqual({
      level: "fail",
      text: "weights NAME sha256 is X, not the pinned Y (claude-ollama prepare 27b)",
    });
  });

  it("gives null for a line that is not a check", () => {
    expect(parseDoctorLine("Usage: claude-ollama doctor [size]")).toBeNull();
    expect(parseDoctorLine("okay then")).toBeNull();
    expect(parseDoctorLine("ok")).toBeNull();
    expect(parseDoctorLine("")).toBeNull();
  });
});

describe("parseOutdatedLine", () => {
  it("reads a current size as ok", () => {
    expect(parseOutdatedLine("current  27b")).toEqual({ level: "ok", text: "27b current" });
  });

  it("reads a behind size as a failure, keeping its old and new revisions", () => {
    expect(parseOutdatedLine("behind   35b (a483e9e → 5d1c0f2)")).toEqual({
      level: "fail",
      text: "35b behind (a483e9e → 5d1c0f2)",
    });
  });

  it("reads an unknown size as a warning, keeping its reason", () => {
    expect(parseOutdatedLine("unknown  27b (no revision at https://huggingface.co)")).toEqual({
      level: "warn",
      text: "27b unknown (no revision at https://huggingface.co)",
    });
  });

  it("gives null for a line that is not an outdated line", () => {
    expect(parseOutdatedLine("Checking current revisions")).toBeNull();
    expect(parseOutdatedLine("behind 27b")).toBeNull();
    expect(parseOutdatedLine("27b current")).toBeNull();
    expect(parseOutdatedLine("")).toBeNull();
  });
});

describe("doctorSummary", () => {
  it("counts the checks at each level", () => {
    expect(
      doctorSummary([
        { level: "ok", text: "jq on PATH" },
        { level: "ok", text: "server reachable" },
        { level: "warn", text: "context mismatch" },
      ]),
    ).toEqual({ ok: 2, warn: 1, fail: 0 });
  });

  it("gives zero counts for no checks", () => {
    expect(doctorSummary([])).toEqual({ ok: 0, warn: 0, fail: 0 });
  });
});

describe("checksFromLines", () => {
  it("splits check lines from the other lines, keeping both in order", () => {
    expect(checksFromLines(["ok   jq on PATH", "Checking models...", "fail digest NAME is X"])).toEqual({
      checks: [
        { level: "ok", text: "jq on PATH" },
        { level: "fail", text: "digest NAME is X" },
      ],
      other: ["Checking models..."],
    });
  });

  it("gives empty lists for no lines", () => {
    expect(checksFromLines([])).toEqual({ checks: [], other: [] });
  });

  it("attaches indented fix lines to the check above them", () => {
    expect(
      checksFromLines([
        "fail server setting cache-ram = 8192 not set",
        "fail server setting models-max = 2 not set",
        "     fix: claude-custom agent -apply",
        "current  27b",
        "behind   35b (a483e9e → 5d1c0f2)",
        "     fix: bin/model-upgrade 35b",
        "1 behind: run the fix lines above",
      ]),
    ).toEqual({
      checks: [
        { level: "fail", text: "server setting cache-ram = 8192 not set" },
        { level: "fail", text: "server setting models-max = 2 not set", fixes: ["claude-custom agent -apply"] },
        { level: "ok", text: "27b current" },
        { level: "fail", text: "35b behind (a483e9e → 5d1c0f2)", fixes: ["bin/model-upgrade 35b"] },
      ],
      other: ["1 behind: run the fix lines above"],
    });
  });

  it("keeps a fix line with no check above it among the other lines", () => {
    expect(checksFromLines(["     fix: bin/model-upgrade 35b"])).toEqual({
      checks: [],
      other: ["     fix: bin/model-upgrade 35b"],
    });
  });
});
