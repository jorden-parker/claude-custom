import { describe, expect, it } from "vitest";
import type { Draft, ReviewComment } from "./draft-schema";
import {
  blankComment,
  blankSection,
  isDirty,
  lineFromInput,
  pathFromInput,
  replaceAt,
  removeAt,
  toggleDecoration,
} from "./draft-edits";

const pr = (title: string): Draft => ({
  kind: "pr",
  id: "20260101-120000-pr-x",
  project: "/work/tree",
  base: "main",
  head: "feature-x",
  title,
  sections: [{ heading: "Summary", body: "Text." }],
  created: "2026-01-01T12:00:00.000Z",
});

describe("replaceAt and removeAt", () => {
  it("replaces one item and leaves the others", () => {
    expect(replaceAt(["a", "b", "c"], 1, "B")).toEqual(["a", "B", "c"]);
  });

  it("removes one item by index", () => {
    expect(removeAt(["a", "b", "c"], 0)).toEqual(["b", "c"]);
  });
});

describe("blank items", () => {
  it("starts a comment as an issue with no decorations", () => {
    const comment: ReviewComment = blankComment();

    expect(comment).toEqual({ label: "issue", decorations: [], body: "" });
  });

  it("starts a section empty", () => {
    expect(blankSection()).toEqual({ heading: "", body: "" });
  });
});

describe("toggleDecoration", () => {
  it("adds a decoration that is not there", () => {
    expect(toggleDecoration(["security"], "blocking")).toEqual([
      "security",
      "blocking",
    ]);
  });

  it("removes a decoration that is already there", () => {
    expect(toggleDecoration(["security", "blocking"], "security")).toEqual([
      "blocking",
    ]);
  });
});

describe("pathFromInput and lineFromInput", () => {
  it("reads an empty path as no path", () => {
    expect(pathFromInput("  ")).toBeUndefined();
    expect(pathFromInput(" src/a.ts ")).toBe("src/a.ts");
  });

  it("reads an empty or non-numeric line as no line", () => {
    expect(lineFromInput("")).toBeUndefined();
    expect(lineFromInput("x")).toBeUndefined();
    expect(lineFromInput("42")).toBe(42);
  });
});

describe("isDirty", () => {
  it("is clean when the editable fields match the saved draft", () => {
    expect(isDirty(pr("Same"), pr("Same"))).toBe(false);
  });

  it("is dirty when an editable field differs", () => {
    expect(isDirty(pr("Changed"), pr("Same"))).toBe(true);
  });

  it("ignores a change to a field the editor does not own", () => {
    const changedBase = { ...pr("Same"), base: "develop" };

    expect(isDirty(changedBase, pr("Same"))).toBe(false);
  });
});
