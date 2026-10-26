import { describe, expect, it } from "vitest";
import { doctorSummary, parseDoctorLine } from "./doctor-checks";

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
