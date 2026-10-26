import { cleanup, render, screen, waitFor } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { ModelsSnapshot } from "@/lib/models";
import { ModelsView } from "./models-view";

vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: vi.fn() }),
}));

function snapshotWith(ollama: "up" | "down"): ModelsSnapshot {
  return {
    ollama,
    sizes: [{ size: "27b", model: "qwen-27b", base: "qwen3.8:27b", installed: true, class: "mlx" }],
    models: [{ name: "qwen3.8:27b", class: "library", bytes: 1024, loaded: true }],
    prunable: [],
    embedding: { name: "test-embed:0.6b", installed: false },
  };
}

function serve(snapshot: ModelsSnapshot) {
  vi.spyOn(globalThis, "fetch").mockImplementation(async (url) => {
    const body = String(url) === "/api/models" ? snapshot : [];
    return new Response(JSON.stringify(body));
  });
}

describe("ModelsView", () => {
  beforeEach(() => {
    vi.restoreAllMocks();
  });

  afterEach(() => {
    cleanup();
  });

  it("shows the Ollama-not-running banner when the server is down", async () => {
    serve(snapshotWith("down"));
    render(<ModelsView />);
    expect(await screen.findByText(/Ollama is not running/)).toBeTruthy();
  });

  it("lists each configured size and each installed model", async () => {
    serve(snapshotWith("up"));
    render(<ModelsView />);
    await waitFor(() => expect(screen.getByText("qwen-27b")).toBeTruthy());
    expect(screen.getAllByText("qwen3.8:27b")).toHaveLength(2);
    expect(screen.queryByText(/Ollama is not running/)).toBeNull();
  });

  it("offers Set up for a missing embedding model", async () => {
    serve(snapshotWith("up"));
    render(<ModelsView />);
    await waitFor(() => expect(screen.getByText("test-embed:0.6b")).toBeTruthy());
    expect(screen.getByRole("button", { name: "Set up" })).toBeTruthy();
  });
});
