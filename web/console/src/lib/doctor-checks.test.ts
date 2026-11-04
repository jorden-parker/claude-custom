import { describe, expect, it } from "vitest";
import { checksFromLines, doctorSummary, parseDoctorLine } from "./doctor-checks";

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
      parseDoctorLine("fail digest NAME is X, not the pinned Y (ollama rm NAME, then relaunch)"),
    ).toEqual({
      level: "fail",
      text: "digest NAME is X, not the pinned Y (ollama rm NAME, then relaunch)",
    });
  });

  it("gives null for a line that is not a check", () => {
    expect(parseDoctorLine("Usage: claude-ollama doctor [size]")).toBeNull();
    expect(parseDoctorLine("okay then")).toBeNull();
    expect(parseDoctorLine("ok")).toBeNull();
    expect(parseDoctorLine("")).toBeNull();
  });

  it("reads the outdated-models words at their level, keeping the word", () => {
    expect(parseDoctorLine("current  qwen3.8:27b-mlx")).toEqual({ level: "ok", text: "current qwen3.8:27b-mlx" });
    expect(parseDoctorLine("skipped  ./weights/Q.gguf (GGUF, pinned by file sha256)")).toEqual({
      level: "ok",
      text: "skipped ./weights/Q.gguf (GGUF, pinned by file sha256)",
    });
    expect(parseDoctorLine("unknown  qwen3:nope (no manifest at https://registry.ollama.ai)")).toEqual({
      level: "warn",
      text: "unknown qwen3:nope (no manifest at https://registry.ollama.ai)",
    });
    expect(parseDoctorLine("behind   qwen3.6:35b-mlx (registry 4a5e, pin e92a)")).toEqual({
      level: "fail",
      text: "behind qwen3.6:35b-mlx (registry 4a5e, pin e92a)",
    });
    expect(parseDoctorLine("unpinned qwen3:none (not in ollama/model-digests.json)")).toEqual({
      level: "fail",
      text: "unpinned qwen3:none (not in ollama/model-digests.json)",
    });
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
        "fail server env OLLAMA_KEEP_ALIVE=30m not set",
        "fail server env OLLAMA_MAX_LOADED_MODELS=2 not set",
        "     fix: claude-custom agent -apply",
        "behind   qwen3.6:35b-mlx (registry 4a5e, pin e92a)",
        "     fix: bin/model-upgrade 35b",
        "2 behind, 0 unpinned: run the fix lines above",
      ]),
    ).toEqual({
      checks: [
        { level: "fail", text: "server env OLLAMA_KEEP_ALIVE=30m not set" },
        { level: "fail", text: "server env OLLAMA_MAX_LOADED_MODELS=2 not set", fixes: ["claude-custom agent -apply"] },
        { level: "fail", text: "behind qwen3.6:35b-mlx (registry 4a5e, pin e92a)", fixes: ["bin/model-upgrade 35b"] },
      ],
      other: ["2 behind, 0 unpinned: run the fix lines above"],
    });
  });

  it("keeps a fix line with no check above it among the other lines", () => {
    expect(checksFromLines(["     fix: bin/model-upgrade 35b"])).toEqual({
      checks: [],
      other: ["     fix: bin/model-upgrade 35b"],
    });
  });
});
