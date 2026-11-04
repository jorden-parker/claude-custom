import { cleanup, fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { ModelsSnapshot } from "@/lib/models";
import { ModelsView } from "./models-view";

vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: vi.fn() }),
}));

const SERVER_URL = "http://127.0.0.1:11435";

function snapshotWith(server: "up" | "down"): ModelsSnapshot {
  return {
    server,
    serverUrl: SERVER_URL,
    sizes: [
      { size: "27b", model: "qwen3.8-27b-cc", file: "Qwen3.8-27B-UD-Q4_K_XL.gguf", state: "pinned" },
      { size: "35b", model: "qwen3.6-35b-cc", file: "Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf", state: null },
    ],
    presets:
      server === "up"
        ? [
            { id: "qwen3.8-27b-cc", aliases: [], status: "loaded", bytes: 17_000_000_000 },
            { id: "qwen3.8-27b-cc@think", aliases: [], status: "unloaded", bytes: null },
            { id: "qwen3-embedding-0.6b", aliases: ["qwen3-embedding:0.6b"], status: "loading", bytes: null },
          ]
        : [],
    files: [
      { name: "Qwen3.8-27B-UD-Q4_K_XL.gguf", state: "pinned", size: "27b", bytes: 17_000_000_000 },
      { name: "Old-Model-Q4_K_M.gguf", state: "orphan", size: null, bytes: 1_000_000_000 },
    ],
    prunable: ["Old-Model-Q4_K_M.gguf"],
    embedding: { model: "qwen3-embedding:0.6b", file: "Qwen3-Embedding-0.6B-Q8_0.gguf", state: null, status: "loading" },
  };
}

type Posted = { url: string; body: unknown };

function serve(snapshot: ModelsSnapshot, actionStatus = 200) {
  const posted: Posted[] = [];
  vi.spyOn(globalThis, "fetch").mockImplementation(async (url, init) => {
    if (init?.method === "POST") {
      posted.push({ url: String(url), body: JSON.parse(String(init.body)) });
      const body = actionStatus === 200 ? { ok: true } : { message: "model is not running" };
      return new Response(JSON.stringify(body), { status: actionStatus });
    }
    const body = String(url) === "/api/models" ? snapshot : [];
    return new Response(JSON.stringify(body));
  });
  return posted;
}

function presetRow(id: string) {
  const cell = screen.getAllByText(id).find((element) => element.closest("section")?.querySelector("h2")?.textContent === "On the server");
  return within(cell!.closest("tr")!);
}

describe("ModelsView", () => {
  beforeEach(() => {
    vi.restoreAllMocks();
  });

  afterEach(() => {
    cleanup();
  });

  it("names the server URL in a banner when the server is down", async () => {
    serve(snapshotWith("down"));
    render(<ModelsView />);
    expect(await screen.findByText(/The model server at http:\/\/127\.0\.0\.1:11435 is not running/)).toBeTruthy();
  });

  it("lists each size with its weights file and each file on disk", async () => {
    serve(snapshotWith("up"));
    render(<ModelsView />);
    await screen.findByText("Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf");
    expect(document.querySelector('[data-slot="table-container"] table')).not.toBeNull();
    expect(screen.getAllByText("Qwen3.8-27B-UD-Q4_K_XL.gguf")).toHaveLength(2);
    expect(screen.getByRole("button", { name: "Prepare" })).toBeTruthy();
    expect(screen.getByRole("button", { name: "Remove 1 unused file" })).toBeTruthy();
    expect(screen.queryByText(/is not running/)).toBeNull();
  });

  it("offers Set up for a missing embedding file", async () => {
    serve(snapshotWith("up"));
    render(<ModelsView />);
    await screen.findByText("Qwen3-Embedding-0.6B-Q8_0.gguf");
    expect(screen.getByRole("button", { name: "Set up" })).toBeTruthy();
  });

  it("loads an unloaded preset and unloads a loaded one through the model routes", async () => {
    const posted = serve(snapshotWith("up"));
    render(<ModelsView />);
    await screen.findByText("qwen3.8-27b-cc@think");

    fireEvent.click(presetRow("qwen3.8-27b-cc@think").getByRole("button", { name: "Load" }));
    fireEvent.click(presetRow("qwen3.8-27b-cc").getByRole("button", { name: "Unload" }));

    await waitFor(() => expect(posted).toHaveLength(2));
    expect(posted).toEqual([
      { url: "/api/models/load", body: { model: "qwen3.8-27b-cc@think" } },
      { url: "/api/models/unload", body: { model: "qwen3.8-27b-cc" } },
    ]);
    expect(presetRow("qwen3.8-27b-cc").getByText("17.0 GB")).toBeTruthy();
    expect(presetRow("qwen3-embedding-0.6b").queryByRole("button")).toBeNull();
  });

  it("shows the message of a failed load or unload", async () => {
    serve(snapshotWith("up"), 502);
    render(<ModelsView />);
    await screen.findByText("qwen3.8-27b-cc@think");

    fireEvent.click(presetRow("qwen3.8-27b-cc").getByRole("button", { name: "Unload" }));

    expect(await screen.findByText("model is not running")).toBeTruthy();
  });
});
