import {
  act,
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
} from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { RescueCard } from "./rescue-card";
import { FakeRunEventSource, stubResizeObserver } from "./run-stream-test-support";

vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: () => undefined }),
}));

const RUN_ID = "20261102-140211-rescue-ab12";
const SUMMARY = [
  "~/.claude-ollama/rescue/20261102T140211Z.md",
  "doctor: ok",
  "lease: no session holder",
  "incidents: 3 rows (evicted 2, aborted 1)",
  "proxy: 12 requests in last 120 min, prefix hit rate: 80%",
  "memory: 12 GiB free of 64 GiB",
];

describe("RescueCard", () => {
  let writeText: ReturnType<typeof vi.fn>;

  beforeEach(() => {
    FakeRunEventSource.opened = [];
    writeText = vi.fn().mockResolvedValue(undefined);
    vi.stubGlobal("EventSource", FakeRunEventSource);
    stubResizeObserver();
    vi.stubGlobal("navigator", { clipboard: { writeText } });
    vi.spyOn(globalThis, "fetch").mockImplementation(async () =>
      Response.json({
        path: "/home/x/.claude-ollama/rescue/20261102T140211Z.md",
        text: "# Rescue\n\nall fine\n",
      }),
    );
  });

  afterEach(() => {
    cleanup();
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
  });

  it("offers a size select and a start button without a run", () => {
    render(<RescueCard sizes={["27b", "35b"]} initialRunId={null} />);
    expect(screen.getByRole("combobox").textContent).toContain("27b");
    expect(
      screen.getByRole("button", { name: "Write rescue report" }),
    ).toBeTruthy();
    expect(screen.getByText("No rescue report yet.")).toBeTruthy();
  });

  it("shows the summary lines and path once the run ends, then copies and opens the report", async () => {
    render(<RescueCard sizes={["27b"]} initialRunId={RUN_ID} />);
    const source = FakeRunEventSource.opened[0]!;
    act(() => {
      source.start("rescue", "Rescue report (27b)");
      source.lines(SUMMARY);
      source.end();
    });
    expect(screen.getByLabelText("report path").textContent).toBe(SUMMARY[0]);
    expect(
      screen.getAllByRole("listitem").map((item) => item.textContent),
    ).toEqual(SUMMARY.slice(1));

    fireEvent.click(screen.getByRole("button", { name: "Copy report" }));
    await waitFor(() =>
      expect(writeText).toHaveBeenCalledWith("# Rescue\n\nall fine\n"),
    );
    expect(fetch).toHaveBeenCalledWith("/api/rescue/latest", {
      cache: "no-store",
    });
    expect(await screen.findByText("Copied.")).toBeTruthy();

    fireEvent.click(screen.getByRole("button", { name: "Open" }));
    expect(await screen.findByRole("heading", { name: "Rescue" })).toBeTruthy();
    expect(screen.getByText("all fine")).toBeTruthy();
  });

  it("reports a missing report when the copy fails", async () => {
    vi.mocked(fetch).mockResolvedValue(
      Response.json(
        { message: "No rescue report yet; run claude-ollama rescue first" },
        { status: 404 },
      ),
    );
    render(<RescueCard sizes={["27b"]} initialRunId={RUN_ID} />);
    const source = FakeRunEventSource.opened[0]!;
    act(() => {
      source.start("rescue", "Rescue report (27b)");
      source.lines(SUMMARY);
      source.end();
    });
    fireEvent.click(screen.getByRole("button", { name: "Copy report" }));
    expect(
      await screen.findByText(
        "No rescue report yet; run claude-ollama rescue first",
      ),
    ).toBeTruthy();
    expect(writeText).not.toHaveBeenCalled();
  });
});
