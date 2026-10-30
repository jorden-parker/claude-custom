import { describe, expect, it } from "vitest";
import type { ReviewDraft } from "./draft-schema";
import { pullRequestBody, reviewPayload } from "./draft-render";

const reviewDraft = (overrides: Partial<ReviewDraft>): ReviewDraft => ({
  kind: "review",
  id: "20261029-100000-review-12",
  project: "/work/tree",
  pr: 12,
  event: "COMMENT",
  summary: "Overall.",
  comments: [],
  created: "2026-10-29T10:00:00Z",
  ...overrides,
});

describe("pullRequestBody", () => {
  it("joins the sections as level-two headings with a blank line between", () => {
    expect(
      pullRequestBody([
        { heading: "Summary", body: "Adds drafts." },
        { heading: "Testing", body: "Ran it." },
      ]),
    ).toBe("## Summary\n\nAdds drafts.\n\n## Testing\n\nRan it.");
  });
});

describe("reviewPayload", () => {
  it("puts a placed comment inline on the right side", () => {
    const payload = reviewPayload(
      reviewDraft({
        comments: [
          {
            label: "issue",
            decorations: ["blocking"],
            path: "src/a.ts",
            line: 3,
            body: "Off by one.",
          },
        ],
      }),
    );

    expect(payload.comments).toEqual([
      {
        path: "src/a.ts",
        line: 3,
        side: "RIGHT",
        body: "**issue (blocking):** Off by one.",
      },
    ]);
  });

  it("joins an unplaced comment into the summary", () => {
    const payload = reviewPayload(
      reviewDraft({
        summary: "Close.",
        comments: [
          {
            label: "issue",
            decorations: ["blocking"],
            body: "Tests are missing.",
          },
        ],
      }),
    );

    expect(payload.body).toBe(
      "Close.\n\n**issue (blocking):** Tests are missing.",
    );
    expect(payload.comments).toEqual([]);
  });

  it("leaves no leading blank lines when the summary is empty", () => {
    const payload = reviewPayload(
      reviewDraft({
        summary: "",
        comments: [{ label: "praise", decorations: [], body: "Nice split." }],
      }),
    );

    expect(payload.body).toBe("**praise:** Nice split.");
  });

  it("keeps the event", () => {
    expect(reviewPayload(reviewDraft({ event: "APPROVE" })).event).toBe(
      "APPROVE",
    );
  });
});
