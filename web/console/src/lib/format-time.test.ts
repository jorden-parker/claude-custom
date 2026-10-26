import { describe, expect, it } from "vitest";
import { formatLocalTime, formatRelative } from "./format-time";

const NOW = new Date(2026, 9, 21, 20, 0).getTime();

describe("formatLocalTime", () => {
  it("shows the local month, day and time", () => {
    const iso = new Date(2026, 9, 21, 18, 0).toISOString();
    expect(formatLocalTime(iso)).toBe("Oct 21, 18:00");
  });

  it("gives an empty string for a missing timestamp", () => {
    expect(formatLocalTime("")).toBe("");
  });
});

describe("formatRelative", () => {
  it("says just now under a minute", () => {
    expect(formatRelative(new Date(NOW - 30_000).toISOString(), NOW)).toBe("just now");
  });

  it("counts minutes, hours and days", () => {
    expect(formatRelative(new Date(NOW - 5 * 60_000).toISOString(), NOW)).toBe("5 min ago");
    expect(formatRelative(new Date(NOW - 2 * 3_600_000).toISOString(), NOW)).toBe("2 h ago");
    expect(formatRelative(new Date(NOW - 3 * 86_400_000).toISOString(), NOW)).toBe("3 d ago");
  });

  it("gives an empty string for a missing timestamp", () => {
    expect(formatRelative("", NOW)).toBe("");
  });
});
