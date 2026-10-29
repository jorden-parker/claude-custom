import { describe, expect, it } from "vitest";
import {
  editableFieldsOf,
  kindOfDraftId,
  mergeDraftEdits,
  parseDraft,
  type Draft,
} from "./draft-schema";

const PR_ID = "20260101-120000-pr-add-drafts";
const REVIEW_ID = "20260101-120000-review-pr-12";
const CREATED = "2026-01-01T12:00:00.000Z";

const prDraft = (overrides: Record<string, unknown> = {}) => ({
  kind: "pr",
  id: PR_ID,
  project: "/work/tree",
  base: "main",
  head: "feature-x",
  title: "Add drafts",
  sections: [{ heading: "Summary", body: "Adds drafts." }],
  created: CREATED,
  ...overrides,
});

const reviewDraft = (overrides: Record<string, unknown> = {}) => ({
  kind: "review",
  id: REVIEW_ID,
  project: "/work/tree",
  pr: 12,
  event: "COMMENT",
  summary: "Looks good.",
  comments: [
    {
      label: "issue",
      decorations: ["blocking"],
      path: "src/a.ts",
      line: 42,
      body: "Off by one.",
    },
    { label: "praise", decorations: [], body: "Nice split." },
  ],
  created: CREATED,
  ...overrides,
});

function reasonFor(text: string, id = PR_ID): string {
  const result = parseDraft(id, text);
  if (result.ok) {
    throw new Error("expected the draft to be invalid");
  }
  return result.reason;
}

describe("draft ids", () => {
  it("reads the kind from the id", () => {
    expect(kindOfDraftId(PR_ID)).toBe("pr");
    expect(kindOfDraftId(REVIEW_ID)).toBe("review");
  });

  it("returns no kind for an id outside the pattern", () => {
    expect(kindOfDraftId("../etc-pr-x")).toBeNull();
    expect(kindOfDraftId("20260101-120000-other-x")).toBeNull();
  });
});

describe("parseDraft", () => {
  it("accepts a PR draft and keeps its sections", () => {
    const result = parseDraft(PR_ID, JSON.stringify(prDraft()));

    expect(result).toEqual({
      ok: true,
      draft: expect.objectContaining({ kind: "pr", title: "Add drafts" }),
    });
  });

  it("accepts a review draft with inline and unplaced comments", () => {
    const result = parseDraft(REVIEW_ID, JSON.stringify(reviewDraft()));

    expect(result.ok).toBe(true);
  });

  it("keeps the posted record when it is present", () => {
    const posted = { url: "https://github.com/o/r/pull/3", at: CREATED };

    const result = parseDraft(PR_ID, JSON.stringify(prDraft({ posted })));

    expect(result).toMatchObject({ ok: true, draft: { posted } });
  });

  it.each([
    "javascript:alert(1)",
    "http://github.com/o/r/pull/3",
    "https://github.com.evil.example/o/r/pull/3",
  ])("rejects a posted url that is not https on github.com: %s", (url) => {
    const posted = { url, at: CREATED };

    expect(reasonFor(JSON.stringify(prDraft({ posted })))).toBe(
      "posted url must be an https://github.com/ link",
    );
  });

  it("names the problem when the text is not JSON", () => {
    expect(reasonFor("{not json")).toBe("not JSON");
  });

  it("rejects an id that does not match the file name", () => {
    expect(
      reasonFor(JSON.stringify(prDraft({ id: "20260101-120000-pr-other" }))),
    ).toBe("id does not match the file name");
  });

  it("rejects a kind that does not match the id", () => {
    expect(reasonFor(JSON.stringify(prDraft({ kind: "review" })))).toBe(
      "kind is not pr",
    );
  });

  it("rejects a project that is not an absolute path", () => {
    expect(
      reasonFor(JSON.stringify(prDraft({ project: "work/tree" }))),
    ).toMatch(/^project must be/);
  });

  it("rejects a created time that is not ISO", () => {
    expect(reasonFor(JSON.stringify(prDraft({ created: "yesterday" })))).toBe(
      "created must be an ISO time",
    );
  });

  it("rejects a title with a line break", () => {
    expect(reasonFor(JSON.stringify(prDraft({ title: "two\nlines" })))).toMatch(
      /^title must be/,
    );
  });

  it("rejects a title over 256 characters", () => {
    expect(
      reasonFor(JSON.stringify(prDraft({ title: "x".repeat(257) }))),
    ).toMatch(/^title must be/);
  });

  it("rejects an empty title", () => {
    expect(reasonFor(JSON.stringify(prDraft({ title: "   " })))).toMatch(
      /^title must be/,
    );
  });

  it("rejects a heading over 200 characters", () => {
    const sections = [{ heading: "h".repeat(201), body: "" }];

    expect(reasonFor(JSON.stringify(prDraft({ sections })))).toMatch(
      /^heading must be/,
    );
  });

  it("rejects a section body over 20000 characters", () => {
    const sections = [{ heading: "Summary", body: "b".repeat(20001) }];

    expect(reasonFor(JSON.stringify(prDraft({ sections })))).toMatch(
      /^section body must be/,
    );
  });

  it("rejects more than 30 sections", () => {
    const sections = Array.from({ length: 31 }, (_, index) => ({
      heading: `H${index}`,
      body: "",
    }));

    expect(reasonFor(JSON.stringify(prDraft({ sections })))).toMatch(
      /^sections must be/,
    );
  });

  it("rejects a branch name that starts with a dash", () => {
    expect(
      reasonFor(JSON.stringify(prDraft({ head: "--upload-pack=x" }))),
    ).toMatch(/^head must be/);
  });

  it("rejects a PR number that is not a positive integer", () => {
    expect(
      reasonFor(JSON.stringify(reviewDraft({ pr: 0 })), REVIEW_ID),
    ).toMatch(/^pr must be/);
    expect(
      reasonFor(JSON.stringify(reviewDraft({ pr: "12" })), REVIEW_ID),
    ).toMatch(/^pr must be/);
  });

  it("rejects an event outside the three review events", () => {
    expect(
      reasonFor(JSON.stringify(reviewDraft({ event: "MERGE" })), REVIEW_ID),
    ).toMatch(/^event must be/);
  });

  it("rejects more than 30 comments", () => {
    const comments = Array.from({ length: 31 }, () => ({
      label: "todo",
      body: "x",
    }));

    expect(
      reasonFor(JSON.stringify(reviewDraft({ comments })), REVIEW_ID),
    ).toMatch(/^comments must be/);
  });

  it("rejects a label outside the list", () => {
    const comments = [{ label: "rant", body: "x" }];

    expect(
      reasonFor(JSON.stringify(reviewDraft({ comments })), REVIEW_ID),
    ).toMatch(/^label must be/);
  });

  it("rejects a decoration outside the list", () => {
    const comments = [{ label: "issue", decorations: ["urgent"], body: "x" }];

    expect(
      reasonFor(JSON.stringify(reviewDraft({ comments })), REVIEW_ID),
    ).toMatch(/^decoration must be/);
  });

  it("rejects a line without a path", () => {
    const comments = [{ label: "issue", body: "x", line: 4 }];

    expect(
      reasonFor(JSON.stringify(reviewDraft({ comments })), REVIEW_ID),
    ).toBe("line needs a path");
  });

  it("rejects a line that is not a positive integer", () => {
    const comments = [{ label: "issue", body: "x", path: "a.ts", line: -1 }];

    expect(
      reasonFor(JSON.stringify(reviewDraft({ comments })), REVIEW_ID),
    ).toMatch(/^line must be/);
  });
});

describe("mergeDraftEdits", () => {
  const current = parseDraft(
    PR_ID,
    JSON.stringify(prDraft({ posted: undefined })),
  );

  it("replaces only the editable fields of a PR", () => {
    if (!current.ok) {
      throw new Error(current.reason);
    }

    const result = mergeDraftEdits(current.draft, {
      title: "Renamed",
      sections: [{ heading: "Why", body: "Because." }],
      base: "develop",
      id: "20260101-120000-pr-other",
      project: "/elsewhere",
    });

    expect(result).toEqual({
      ok: true,
      draft: expect.objectContaining({
        id: PR_ID,
        project: "/work/tree",
        base: "main",
        head: "feature-x",
        title: "Renamed",
        sections: [{ heading: "Why", body: "Because." }],
      }),
    });
  });

  it("keeps the current value of an editable field the edit leaves out", () => {
    if (!current.ok) {
      throw new Error(current.reason);
    }

    const result = mergeDraftEdits(current.draft, {});

    expect(result).toMatchObject({ ok: true, draft: { title: "Add drafts" } });
  });

  it("returns the reason when the edit is invalid", () => {
    if (!current.ok) {
      throw new Error(current.reason);
    }

    expect(mergeDraftEdits(current.draft, { title: "" })).toEqual({
      ok: false,
      reason: "title must be one line of at most 256 characters",
    });
  });

  it("edits the review fields of a review draft", () => {
    const review = parseDraft(REVIEW_ID, JSON.stringify(reviewDraft()));
    if (!review.ok) {
      throw new Error(review.reason);
    }

    const result = mergeDraftEdits(review.draft, {
      event: "APPROVE",
      summary: "Ship it.",
      pr: 99,
    });

    expect(result).toMatchObject({
      ok: true,
      draft: { event: "APPROVE", summary: "Ship it.", pr: 12 },
    });
  });
});

describe("editableFieldsOf", () => {
  it("lists the title and sections of a PR", () => {
    const draft = parseDraft(PR_ID, JSON.stringify(prDraft()));
    if (!draft.ok) {
      throw new Error(draft.reason);
    }

    expect(editableFieldsOf(draft.draft as Draft)).toEqual({
      title: "Add drafts",
      sections: [{ heading: "Summary", body: "Adds drafts." }],
    });
  });
});
