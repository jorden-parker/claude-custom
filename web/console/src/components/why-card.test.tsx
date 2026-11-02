import {
  act,
  cleanup,
  fireEvent,
  render,
  screen,
} from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { FakeRunEventSource } from "./run-stream-test-support";
import { WhyCard } from "./why-card";

vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: () => undefined }),
}));

const RUN_ID = "20261102-140211-why-ab12";
const WHY_JSON = [
  "{",
  ' "verdict": "evicted",',
  ' "summary": "the model left memory twice",',
  ' "evidence": "2 evicted rows, last 14:02:11",',
  ' "fix": "OLLAMA_MAX_LOADED_MODELS=2",',
  ' "prefix": {"percent": 80, "stable": 8, "requests": 10},',
  ' "diverging": [{"section": "system", "count": 2}],',
  ' "incidents": {"evicted": 2},',
  ' "window": "last 120 minutes"',
  "}",
];

describe("WhyCard", () => {
  beforeEach(() => {
    FakeRunEventSource.opened = [];
    vi.stubGlobal("EventSource", FakeRunEventSource);
  });

  afterEach(() => {
    cleanup();
    vi.unstubAllGlobals();
  });

  it("offers a start button and an empty state without a run", () => {
    render(<WhyCard initialRunId={null} />);
    expect(
      screen.getByRole("button", { name: "Explain the last run" }),
    ).toBeTruthy();
    expect(screen.getByText("No why run yet.")).toBeTruthy();
    expect(FakeRunEventSource.opened).toHaveLength(0);
  });

  it("shows the live lines while running, then the parsed verdict, fix and prefix rate", () => {
    render(<WhyCard initialRunId={RUN_ID} />);
    const source = FakeRunEventSource.opened[0]!;
    expect(source.url).toBe(`/api/runs/${RUN_ID}/events`);
    act(() => {
      source.start("why", "Why did the last run go wrong?");
      source.lines(["reading the proxy log"]);
    });
    expect(screen.getByText("reading the proxy log")).toBeTruthy();
    expect(screen.queryByLabelText("verdict")).toBeNull();

    act(() => {
      source.lines(WHY_JSON);
      source.end();
    });
    expect(screen.getByLabelText("verdict").textContent).toBe(
      "evicted: the model left memory twice (last 120 minutes)",
    );
    expect(screen.getByLabelText("evidence").textContent).toBe(
      "2 evicted rows, last 14:02:11",
    );
    expect(screen.getByLabelText("fix").textContent).toBe(
      "OLLAMA_MAX_LOADED_MODELS=2",
    );
    expect(screen.getByLabelText("prefix hit rate").textContent).toBe(
      "80% of 10 requests stable through tools",
    );
    expect(
      screen.getByRole("link", { name: "Open run" }).getAttribute("href"),
    ).toBe(`/runs/${RUN_ID}`);
    expect(screen.queryByText("reading the proxy log")).toBeNull();

    fireEvent.click(screen.getByRole("button", { name: "Raw output" }));
    expect(screen.getByText("reading the proxy log")).toBeTruthy();
  });

  it("reports a run that printed no report", () => {
    render(<WhyCard initialRunId={RUN_ID} />);
    const source = FakeRunEventSource.opened[0]!;
    act(() => {
      source.start("why", "Why did the last run go wrong?");
      source.lines(["why: no proxy log"]);
      source.end(1);
    });
    expect(
      screen.getByText("The run printed no report (exit 1)."),
    ).toBeTruthy();
    expect(screen.getByText("why: no proxy log")).toBeTruthy();
  });
});
