import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import type { ServerSnapshot } from "@/lib/server-snapshot";
import { ServerSettingsEditor } from "./server-settings-editor";

vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: vi.fn() }),
}));

function snapshotWith(conflicts: string[] = []): ServerSnapshot {
  return {
    path: "/Users/test/Library/LaunchAgents/local.llama-server.plist",
    exists: true,
    conflicts,
    variables: [
      { name: "models-max", summary: "router models-max", current: "2", set: true, recommended: "2" },
      { name: "flash-attn", summary: "flash attention", current: "off", set: true, recommended: "on" },
      { name: "n-gpu-layers", summary: "layers on the GPU", current: "99", set: true, recommended: "99" },
    ],
  };
}

const saveButton = () => screen.getByRole("button", { name: "Save and reload" });
const applyButton = () => screen.getByRole("button", { name: "Apply recommended" });
const modelsMax = () => screen.getByRole("spinbutton", { name: "models-max" });
const flashAttn = () => screen.getByRole("combobox", { name: "flash-attn" }) as HTMLSelectElement;

async function renderEditor(snapshot: ServerSnapshot) {
  vi.spyOn(globalThis, "fetch").mockResolvedValue(new Response(JSON.stringify(snapshot)));
  render(<ServerSettingsEditor />);
  await screen.findByText("Models loaded at once");
}

describe("ServerSettingsEditor", () => {
  afterEach(() => {
    cleanup();
    vi.restoreAllMocks();
  });

  it("shows each setting by its label and help, with its preset key", async () => {
    await renderEditor(snapshotWith());

    expect(screen.getByText("models-max")).toBeTruthy();
    expect(screen.getByText(/the chat model and the embedding model need 2/)).toBeTruthy();
  });

  it("offers a number input in the setting's range and a select of its choices", async () => {
    await renderEditor(snapshotWith());

    expect(modelsMax().getAttribute("min")).toBe("1");
    expect(modelsMax().getAttribute("max")).toBe("4");
    expect([...flashAttn().options].map((option) => option.value)).toEqual(["on", "off", "auto"]);
    expect(flashAttn().value).toBe("off");
  });

  it("shows a key that is not a setting as a locked row with no input", async () => {
    await renderEditor(snapshotWith());

    expect(screen.getByText("n-gpu-layers")).toBeTruthy();
    expect(screen.queryByRole("spinbutton", { name: "n-gpu-layers" })).toBeNull();
    expect(screen.queryByRole("combobox", { name: "n-gpu-layers" })).toBeNull();
  });

  it("marks a setting whose value differs from the recommendation", async () => {
    await renderEditor(snapshotWith());

    expect(screen.getAllByText("differs")).toHaveLength(1);
  });

  it("keeps Save disabled while nothing has changed", async () => {
    await renderEditor(snapshotWith());

    expect(saveButton()).toHaveProperty("disabled", true);
  });

  it("disables Save when a typed number is out of range", async () => {
    await renderEditor(snapshotWith());

    fireEvent.change(modelsMax(), { target: { value: "9" } });

    expect(saveButton()).toHaveProperty("disabled", true);
    expect(modelsMax().getAttribute("aria-invalid")).toBe("true");
  });

  it("enables Save for a valid change and counts it", async () => {
    await renderEditor(snapshotWith());

    fireEvent.change(flashAttn(), { target: { value: "auto" } });

    expect(saveButton()).toHaveProperty("disabled", false);
    expect(screen.getByText("1 change")).toBeTruthy();
  });

  it("shows each conflict and keeps both buttons usable", async () => {
    const conflict = "another llama-server is listening on 11435";
    await renderEditor(snapshotWith([conflict]));

    fireEvent.change(modelsMax(), { target: { value: "3" } });

    expect(screen.getByText(conflict)).toBeTruthy();
    expect(saveButton()).toHaveProperty("disabled", false);
    expect(applyButton()).toHaveProperty("disabled", false);
  });
});
