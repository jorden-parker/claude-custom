import { describe, expect, it } from "vitest";
import { logLevel } from "./log-line";

const LINE = (level: string) =>
  `time=2026-10-21T20:00:00.000+01:00 level=${level} source=server.go:1 msg="loaded model"`;

describe("logLevel", () => {
  it("reads each Ollama level", () => {
    expect(logLevel(LINE("ERROR"))).toBe("error");
    expect(logLevel(LINE("WARN"))).toBe("warn");
    expect(logLevel(LINE("INFO"))).toBe("info");
    expect(logLevel(LINE("DEBUG"))).toBe("debug");
  });

  it("gives null when the line has no known level", () => {
    expect(logLevel(LINE("TRACE"))).toBeNull();
    expect(logLevel("plain text without a level")).toBeNull();
    expect(logLevel("")).toBeNull();
  });
});
