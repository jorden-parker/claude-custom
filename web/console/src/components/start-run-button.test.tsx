import { cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { StartRunButton } from "./start-run-button";

const push = vi.fn();

vi.mock("next/navigation", () => ({
  useRouter: () => ({ push }),
}));

const createdResponse = () => new Response(JSON.stringify({ id: "run-42" }), { status: 201 });

const refusedResponse = () => new Response(JSON.stringify({ message: "Not allowed" }), { status: 409 });

describe("StartRunButton", () => {
  beforeEach(() => {
    push.mockReset();
    vi.spyOn(globalThis, "fetch").mockResolvedValue(createdResponse());
  });

  afterEach(() => {
    cleanup();
    vi.restoreAllMocks();
  });

  it("navigates to the run page when the start succeeds", async () => {
    render(
      <StartRunButton command="doctor" params={{ size: "27b" }}>
        Run doctor
      </StartRunButton>,
    );

    fireEvent.click(screen.getByRole("button", { name: "Run doctor" }));

    await waitFor(() => expect(push).toHaveBeenCalledWith("/runs/run-42"));
    expect(fetch).toHaveBeenCalledWith("/api/runs", expect.objectContaining({ method: "POST" }));
  });

  it("calls onStarted and stays on the page when stay is set", async () => {
    const onStarted = vi.fn();
    render(
      <StartRunButton command="doctor" params={{ size: "27b" }} stay onStarted={onStarted}>
        Run doctor
      </StartRunButton>,
    );

    fireEvent.click(screen.getByRole("button", { name: "Run doctor" }));

    await waitFor(() => expect(onStarted).toHaveBeenCalledWith("run-42"));
    expect(push).not.toHaveBeenCalled();
  });

  it("shows the refusal message and does not navigate when the start fails", async () => {
    vi.spyOn(globalThis, "fetch").mockResolvedValue(refusedResponse());
    const onStarted = vi.fn();
    render(
      <StartRunButton command="doctor" params={{ size: "27b" }} stay onStarted={onStarted}>
        Run doctor
      </StartRunButton>,
    );

    fireEvent.click(screen.getByRole("button", { name: "Run doctor" }));

    expect(await screen.findByText("Not allowed")).toBeTruthy();
    expect(onStarted).not.toHaveBeenCalled();
    expect(push).not.toHaveBeenCalled();
  });
});
