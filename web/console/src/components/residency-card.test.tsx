import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { Residency } from "@/lib/lease";
import { ResidencyCard } from "./residency-card";

const FIT_LINE =
  "model 16.0 GiB + kv 8.0 GiB + embedding 0.6 GiB = 24.6 GiB of 24.2 GiB free";

const jsonResponse = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status });

function residencyOn(rung: string | null): Residency {
  return {
    holders: [
      {
        state: "live",
        name: "session",
        pid: 4242,
        model: "qwen3.8-27b-cc",
        rung,
      },
      {
        state: "live",
        name: "embedding",
        pid: 4300,
        model: "qwen3-embedding:0.6b",
        rung: null,
      },
    ],
    rung,
    fit: FIT_LINE,
  };
}

function stubApi(
  residency: Residency,
  promoteStatus = 200,
  promoteBody: unknown = { ok: true, pid: 4242 },
) {
  const promotions: unknown[] = [];
  vi.spyOn(globalThis, "fetch").mockImplementation(async (input, init) => {
    const url = String(input);
    if (url === "/api/lease/promote" && init?.method === "POST") {
      promotions.push(JSON.parse(String(init.body)));
      return jsonResponse(promoteBody, promoteStatus);
    }
    return jsonResponse(residency);
  });
  return promotions;
}

const promoteButton = () =>
  screen.getByRole("button", { name: "Promote back up" }) as HTMLButtonElement;

function useCleanMocks() {
  beforeEach(() => {
    vi.restoreAllMocks();
  });

  afterEach(() => {
    cleanup();
  });
}

describe("ResidencyCard shows", () => {
  useCleanMocks();

  it("the holders, the rung and the fit line", async () => {
    stubApi(residencyOn("embeddings-off"));
    render(<ResidencyCard />);

    expect(await screen.findByText("session")).toBeTruthy();
    expect(screen.getByText("pid 4242 · qwen3.8-27b-cc")).toBeTruthy();
    expect(screen.getByText("embedding")).toBeTruthy();
    expect(screen.getByText("Rung: embeddings-off")).toBeTruthy();
    expect(screen.getByText(`Fit: ${FIT_LINE}`)).toBeTruthy();
  });

  it("when no session holds a lease", async () => {
    stubApi({ holders: [], rung: null, fit: null });
    render(<ResidencyCard />);

    expect(await screen.findByText("No lease holders")).toBeTruthy();
    expect(screen.getByText("Rung: none")).toBeTruthy();
    expect(screen.getByText("Fit: not measured yet")).toBeTruthy();
    expect(promoteButton().disabled).toBe(true);
  });

  it("the load error", async () => {
    vi.spyOn(globalThis, "fetch").mockResolvedValue(
      jsonResponse({ message: "ollama lease: lock held" }, 502),
    );
    render(<ResidencyCard />);

    expect(await screen.findByText("ollama lease: lock held")).toBeTruthy();
  });
});

describe("ResidencyCard promotes", () => {
  useCleanMocks();

  it("nothing while the session is on no rung", async () => {
    stubApi(residencyOn(null));
    render(<ResidencyCard />);

    await screen.findByText("session");
    expect(promoteButton().disabled).toBe(true);
  });

  it("the current rung through the promote route", async () => {
    const promotions = stubApi(residencyOn("context-down"));
    render(<ResidencyCard />);
    await screen.findByText("session");

    fireEvent.click(promoteButton());

    expect(
      await screen.findByText(
        "Promotion queued: context-down recovers at the next handoff relaunch (pid 4242)",
      ),
    ).toBeTruthy();
    expect(promotions).toEqual([{ rung: "context-down" }]);
  });

  it("and shows the route's refusal", async () => {
    stubApi(residencyOn("context-down"), 409, {
      message: "The session is on the no rung, not context-down",
    });
    render(<ResidencyCard />);
    await screen.findByText("session");

    fireEvent.click(promoteButton());

    expect(
      await screen.findByText(
        "The session is on the no rung, not context-down",
      ),
    ).toBeTruthy();
  });
});
