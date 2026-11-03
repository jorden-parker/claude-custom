import { cleanup, render, screen } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { DraftList } from "./draft-list";

describe("DraftList", () => {
  beforeEach(() => {
    vi.spyOn(globalThis, "fetch").mockImplementation(async () =>
      Response.json({ drafts: [] }),
    );
  });

  afterEach(() => {
    cleanup();
    vi.restoreAllMocks();
  });

  it("shows a titled empty state with a short description", async () => {
    render(<DraftList />);

    expect(await screen.findByText("No Drafts Yet")).toBeTruthy();
    expect(
      screen.getByText("/pr-draft and /pr-review-draft write them here."),
    ).toBeTruthy();
  });
});
