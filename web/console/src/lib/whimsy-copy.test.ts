import { describe, expect, it } from "vitest";
import { emptyLineFor, subtitleFor, WHIMSY_EMPTY_LINES, WHIMSY_SUBTITLES } from "./whimsy-copy";

const PAGE_KEYS = ["Runs", "Tools", "Reviews", "Drafts", "Checks", "Logs", "Server", "Models"];

describe("subtitleFor", () => {
  it("returns the same line for the same page key every time", () => {
    expect(subtitleFor("Runs")).toBe(subtitleFor("Runs"));
  });

  it("always returns one of the subtitle lines", () => {
    for (const key of PAGE_KEYS) {
      expect(WHIMSY_SUBTITLES).toContain(subtitleFor(key));
    }
  });

  it("spreads different pages across more than one line", () => {
    const distinct = new Set(PAGE_KEYS.map(subtitleFor));
    expect(distinct.size).toBeGreaterThan(1);
  });
});

describe("emptyLineFor", () => {
  it("returns the same line for the same key every time", () => {
    expect(emptyLineFor("reviews")).toBe(emptyLineFor("reviews"));
  });

  it("always returns one of the empty-state lines", () => {
    for (const key of PAGE_KEYS) {
      expect(WHIMSY_EMPTY_LINES).toContain(emptyLineFor(key));
    }
  });

  it("accepts an empty key without failing", () => {
    expect(WHIMSY_EMPTY_LINES).toContain(emptyLineFor(""));
  });
});
