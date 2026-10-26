import { describe, expect, it } from "vitest";
import { CONSOLE_SECTIONS } from "./console-sections";

describe("CONSOLE_SECTIONS", () => {
  it("lists at least one section", () => {
    expect(CONSOLE_SECTIONS.length).toBeGreaterThan(0);
  });

  it("starts every href at the site root", () => {
    for (const section of CONSOLE_SECTIONS) {
      expect(section.href.startsWith("/")).toBe(true);
    }
  });

  it("gives every section a unique href", () => {
    const hrefs = CONSOLE_SECTIONS.map((section) => section.href);
    expect(new Set(hrefs).size).toBe(hrefs.length);
  });
});
