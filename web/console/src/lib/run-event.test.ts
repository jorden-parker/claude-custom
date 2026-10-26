import { describe, expect, it } from "vitest";
import { isRunEndLine, parseRunEvent, parseRunEvents } from "./run-event";

describe("parseRunEvents", () => {
  it("skips lines that are not events", () => {
    const text = `${JSON.stringify({ t: 0, kind: "line", text: "a" })}\nnot json\n\n{"no":"kind"}\n`;
    expect(parseRunEvents(text)).toEqual([{ t: 0, kind: "line", text: "a" }]);
  });
});

describe("parseRunEvent", () => {
  it("returns null for text that is not JSON", () => {
    expect(parseRunEvent("{")).toBeNull();
  });
});

describe("isRunEndLine", () => {
  it("is true only for an end event", () => {
    expect(isRunEndLine(JSON.stringify({ t: 1, kind: "end", code: 0 }))).toBe(true);
    expect(isRunEndLine(JSON.stringify({ t: 1, kind: "line", text: "end" }))).toBe(false);
  });
});
