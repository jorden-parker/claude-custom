import { cleanup, render, screen } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { ReviewList } from "./review-list";

describe("ReviewList", () => {
  beforeEach(() => {
    vi.spyOn(globalThis, "fetch").mockImplementation(async () =>
      Response.json([]),
    );
  });

  afterEach(() => {
    cleanup();
    vi.restoreAllMocks();
  });

  it("shows a titled empty state with a short description", async () => {
    render(<ReviewList />);

    expect(await screen.findByText("No Reviews Yet")).toBeTruthy();
    expect(screen.getByText(/to start one\./)).toBeTruthy();
  });
});
