import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it, vi } from "vitest";
import { NewReviewFields } from "./new-review-form";
import type { ReactNode } from "react";

vi.mock("@/components/start-run-button", () => ({
  StartRunButton: ({ disabled, children }: { disabled?: boolean; children: ReactNode }) => (
    <button disabled={disabled}>{children}</button>
  ),
}));

function fieldsWith(overrides: { pr?: string; projectDir?: string | null } = {}) {
  return renderToStaticMarkup(
    <NewReviewFields
      sizes={["27b"]}
      size="27b"
      pr={overrides.pr ?? "12"}
      projectDir={overrides.projectDir === undefined ? "/work/repo" : overrides.projectDir}
      onSizeChange={() => undefined}
      onPrChange={() => undefined}
    />,
  );
}

describe("NewReviewFields", () => {
  it("disables the start button for a PR value that is not a number", () => {
    const markup = fieldsWith({ pr: "abc" });

    expect(markup).toContain("<button disabled=\"\">Start review</button>");
    expect(markup).toContain("Enter a PR number, such as 12.");
  });

  it("enables the start button for a PR number", () => {
    expect(fieldsWith({ pr: "12" })).toContain("<button>Start review</button>");
  });

  it("shows the project folder the review will run in", () => {
    expect(fieldsWith()).toContain("/work/repo");
  });

  it("disables the start button when the console has no project folder", () => {
    const markup = fieldsWith({ projectDir: null });

    expect(markup).toContain("<button disabled=\"\">Start review</button>");
    expect(markup).toContain("Start the console from a project folder");
  });
});
