import { describe, expect, it } from "vitest";
import {
  CONSOLE_SECTION_GROUPS,
  CONSOLE_SECTIONS,
  sectionsInGroup,
  sectionSummaryForTitle,
} from "./console-sections";

describe("sectionSummaryForTitle", () => {
  it("returns the summary of the section with that title", () => {
    expect(sectionSummaryForTitle("Runs")).toBe(
      "Every job the console started, live and past",
    );
  });

  it("returns undefined for an unknown title", () => {
    expect(sectionSummaryForTitle("No such page")).toBeUndefined();
  });
});

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

  it("places Profiles after Global tools", () => {
    const hrefs = CONSOLE_SECTIONS.map((section) => section.href);
    expect(hrefs.indexOf("/profiles")).toBe(hrefs.indexOf("/tools") + 1);
  });

  it("places Settings right after Profiles", () => {
    const hrefs = CONSOLE_SECTIONS.map((section) => section.href);
    expect(hrefs.indexOf("/settings")).toBe(hrefs.indexOf("/profiles") + 1);
    expect(
      CONSOLE_SECTIONS.find((section) => section.href === "/settings")?.title,
    ).toBe("Settings");
  });

  it("places Diagnose right after Logs", () => {
    const hrefs = CONSOLE_SECTIONS.map((section) => section.href);
    expect(hrefs.indexOf("/diagnose")).toBe(hrefs.indexOf("/logs") + 1);
    expect(
      CONSOLE_SECTIONS.find((section) => section.href === "/diagnose")?.title,
    ).toBe("Diagnose");
  });

  it("puts every section in a known group", () => {
    for (const section of CONSOLE_SECTIONS) {
      expect(CONSOLE_SECTION_GROUPS).toContain(section.group);
    }
  });

  it("keeps each group's sections next to each other", () => {
    const groupsInOrder = CONSOLE_SECTIONS.map((section) => section.group);
    const groupChanges = groupsInOrder.filter(
      (group, index) => index === 0 || group !== groupsInOrder[index - 1],
    );

    expect(groupChanges).toEqual([...CONSOLE_SECTION_GROUPS]);
  });
});

describe("sectionsInGroup", () => {
  it("lists the Work sections in order", () => {
    expect(sectionsInGroup("Work").map((section) => section.href)).toEqual([
      "/reviews",
      "/drafts",
      "/runs",
      "/mockups",
    ]);
  });
});
