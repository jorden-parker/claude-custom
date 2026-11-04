import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { ServerSnapshot } from "@/lib/server-snapshot";
import { ServerEnvEditor } from "./server-env-editor";

vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: vi.fn() }),
}));

const APP_CONFLICT = "the Ollama app is running its own server; quit it from the menu bar";

function snapshotWith(conflicts: string[] = []): ServerSnapshot {
  return {
    path: "/Users/test/Library/LaunchAgents/local.ollama.plist",
    exists: true,
    conflicts,
    variables: [
      { name: "OLLAMA_KEEP_ALIVE", summary: "how long a model stays loaded", current: "30m", set: true, recommended: "30m" },
      { name: "OLLAMA_FLASH_ATTENTION", summary: "flash attention", current: "0", set: true, recommended: "1" },
      { name: "OLLAMA_HOST", summary: "address Ollama listens on", current: "", set: false, recommended: "" },
    ],
  };
}

const saveButton = () => screen.getByRole("button", { name: "Save and reload" });
const applyButton = () => screen.getByRole("button", { name: "Apply recommended" });
const input = (name: string) => screen.getByRole("textbox", { name });

async function renderEditor(snapshot: ServerSnapshot) {
  vi.spyOn(globalThis, "fetch").mockResolvedValue(new Response(JSON.stringify(snapshot)));
  render(<ServerEnvEditor />);
  await screen.findByText("OLLAMA_KEEP_ALIVE");
}

describe("ServerEnvEditor", () => {
  beforeEach(() => {
    vi.spyOn(globalThis, "fetch").mockResolvedValue(new Response(JSON.stringify(snapshotWith())));
  });

  afterEach(() => {
    cleanup();
    vi.restoreAllMocks();
  });

  it("shows a read-only variable as a locked row with no input", async () => {
    await renderEditor(snapshotWith());

    expect(screen.getByText("OLLAMA_HOST")).toBeTruthy();
    expect(screen.queryByRole("textbox", { name: "OLLAMA_HOST" })).toBeNull();
  });

  it("marks a variable whose value differs from the recommendation", async () => {
    await renderEditor(snapshotWith());

    expect(screen.getByText("differs")).toBeTruthy();
  });

  it("keeps Save disabled while nothing has changed", async () => {
    await renderEditor(snapshotWith());

    expect(saveButton()).toHaveProperty("disabled", true);
  });

  it("disables Save when a typed value is invalid", async () => {
    await renderEditor(snapshotWith());

    fireEvent.change(input("OLLAMA_KEEP_ALIVE"), { target: { value: "30x" } });

    expect(saveButton()).toHaveProperty("disabled", true);
    expect(input("OLLAMA_KEEP_ALIVE").getAttribute("aria-invalid")).toBe("true");
  });

  it("enables Save for a valid change and counts it", async () => {
    await renderEditor(snapshotWith());

    fireEvent.change(input("OLLAMA_KEEP_ALIVE"), { target: { value: "1h" } });

    expect(saveButton()).toHaveProperty("disabled", false);
    expect(screen.getByText("1 change")).toBeTruthy();
  });

  it("disables both buttons while the Ollama app is running", async () => {
    await renderEditor(snapshotWith([APP_CONFLICT]));

    fireEvent.change(input("OLLAMA_KEEP_ALIVE"), { target: { value: "1h" } });

    expect(screen.getByText(APP_CONFLICT)).toBeTruthy();
    expect(saveButton()).toHaveProperty("disabled", true);
    expect(applyButton()).toHaveProperty("disabled", true);
  });
});
