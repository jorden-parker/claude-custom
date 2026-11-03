import { cleanup, render, screen, within } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { CheckCommand } from "@/lib/check-commands";
import type { RunSummary } from "@/lib/run-log";
import { CheckCards, latestRunFor } from "./check-cards";

vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: vi.fn() }),
}));

const NOW_ISO = "2026-11-02T10:00:00.000Z";

const runs: RunSummary[] = [
  {
    id: "20261102-100000-thinking-check-aaaa",
    command: "thinking-check",
    label: "Thinking check",
    status: "ok",
    startedAt: NOW_ISO,
    seconds: 12,
  },
  {
    id: "20261102-095000-qwen-doctor-bbbb",
    command: "qwen-doctor",
    label: "Qwen doctor (27b)",
    status: "failed",
    startedAt: NOW_ISO,
    seconds: 3,
  },
];

const thinkingCheck: CheckCommand = {
  command: "thinking-check",
  title: "Thinking check",
  description: "",
  needsSize: false,
};

const qwenDoctor: CheckCommand = {
  command: "qwen-doctor",
  title: "Qwen doctor",
  description: "",
  needsSize: true,
};

describe("CheckCards", () => {
  beforeEach(() => {
    vi.spyOn(globalThis, "fetch").mockImplementation(() =>
      Promise.resolve(new Response(JSON.stringify(runs), { status: 200 })),
    );
  });

  afterEach(() => {
    cleanup();
    vi.restoreAllMocks();
  });

  it("shows each check's latest run status, a link to it, or never run", async () => {
    render(<CheckCards size="27b" />);

    const thinkingCard = (await screen.findByText("Thinking check")).closest(
      '[data-slot="card"]',
    ) as HTMLElement;
    expect(await within(thinkingCard).findByText("done")).toBeTruthy();
    const link = within(thinkingCard).getByRole("link", { name: "View run" });
    expect(link.getAttribute("href")).toBe(
      "/runs/20261102-100000-thinking-check-aaaa",
    );

    const qwenCard = (await screen.findByText("Qwen doctor")).closest(
      '[data-slot="card"]',
    ) as HTMLElement;
    expect(await within(qwenCard).findByText("failed")).toBeTruthy();

    const configCard = (await screen.findByText("Config check")).closest(
      '[data-slot="card"]',
    ) as HTMLElement;
    expect(await within(configCard).findByText("Never run")).toBeTruthy();
  });
});

describe("latestRunFor", () => {
  it("returns the first run of the command", () => {
    expect(latestRunFor(runs, thinkingCheck, "27b")?.id).toBe(
      "20261102-100000-thinking-check-aaaa",
    );
  });

  it("returns the first run of a sized command for the same size only", () => {
    expect(latestRunFor(runs, qwenDoctor, "27b")?.id).toBe(
      "20261102-095000-qwen-doctor-bbbb",
    );
    expect(latestRunFor(runs, qwenDoctor, "35b")).toBeUndefined();
  });

  it("returns undefined when the command has never run", () => {
    expect(latestRunFor([], thinkingCheck, "27b")).toBeUndefined();
  });
});
