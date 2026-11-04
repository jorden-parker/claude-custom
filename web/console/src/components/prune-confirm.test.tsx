import {
  cleanup,
  fireEvent,
  render,
  screen,
  within,
} from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import type { WeightFile } from "@/lib/model-display";
import { PruneConfirm } from "./prune-confirm";

const files: WeightFile[] = [
  { name: "Old-Model-Q4_K_M.gguf", state: "orphan", size: null, bytes: 1_000_000_000 },
  { name: "Half-Model.gguf.part", state: "partial", size: null, bytes: 2_000_000_000 },
];

async function renderDialog(onConfirm = vi.fn(), onCancel = vi.fn()) {
  render(<PruneConfirm files={files} onConfirm={onConfirm} onCancel={onCancel} />);
  return within(await screen.findByRole("alertdialog"));
}

describe("PruneConfirm", () => {
  afterEach(() => {
    cleanup();
  });

  it("titles the dialog and states the count and the space freed", async () => {
    const dialog = await renderDialog();

    expect(dialog.getByRole("heading", { name: "Remove weight files" })).toBeTruthy();
    expect(dialog.getByText("2 files, 3.0 GB freed.")).toBeTruthy();
  });

  it("lists each name with its size", async () => {
    const dialog = await renderDialog();

    expect(dialog.getByText(/Old-Model-Q4_K_M\.gguf/)).toBeTruthy();
    expect(dialog.getByText(/Half-Model\.gguf\.part/)).toBeTruthy();
  });

  it("removes the listed names when the action is chosen", async () => {
    const onConfirm = vi.fn();
    const dialog = await renderDialog(onConfirm);

    fireEvent.click(dialog.getByRole("button", { name: "Remove weight files" }));

    expect(onConfirm).toHaveBeenCalledWith(["Old-Model-Q4_K_M.gguf", "Half-Model.gguf.part"]);
  });

  it("cancels through the Cancel button", async () => {
    const onCancel = vi.fn();
    const dialog = await renderDialog(vi.fn(), onCancel);

    fireEvent.click(dialog.getByRole("button", { name: "Cancel" }));

    expect(onCancel).toHaveBeenCalledTimes(1);
  });
});
