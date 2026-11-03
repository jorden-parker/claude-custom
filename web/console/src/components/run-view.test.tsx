import { act, cleanup, render, screen } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { FakeRunEventSource, stubResizeObserver } from "./run-stream-test-support";
import { RunView } from "./run-view";

describe("RunView", () => {
  beforeEach(() => {
    FakeRunEventSource.opened = [];
    vi.stubGlobal("EventSource", FakeRunEventSource);
    stubResizeObserver();
    vi.spyOn(globalThis, "fetch").mockImplementation(async () =>
      Response.json([]),
    );
  });

  afterEach(() => {
    cleanup();
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
  });

  it("holds the streamed lines in a log region", async () => {
    render(<RunView id="run-1" />);
    const source = FakeRunEventSource.opened[0];
    act(() => {
      source.start("doctor-free", "Check things");
      source.lines(["first line", "second line"]);
    });
    const logRegion = await screen.findByRole("log");
    expect(logRegion.textContent).toContain("first line");
    expect(logRegion.textContent).toContain("second line");
  });
});
