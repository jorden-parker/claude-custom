import { cleanup, render, screen } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { RunList } from "./run-list";

describe("RunList", () => {
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
    render(<RunList />);

    expect(await screen.findByText("No Runs Yet")).toBeTruthy();
    expect(screen.getByText("Start one above.")).toBeTruthy();
  });
});
