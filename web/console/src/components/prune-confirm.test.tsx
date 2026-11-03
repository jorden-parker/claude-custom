import {
  cleanup,
  fireEvent,
  render,
  screen,
  within,
} from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import type { InstalledModel } from "@/lib/model-display";
import { PruneConfirm } from "./prune-confirm";

const models: InstalledModel[] = [
  { name: "old-cc:latest", class: "orphan", bytes: 1_000_000_000, loaded: false },
  { name: "someone/model:latest", class: "third-party", bytes: 2_000_000_000, loaded: false },
];

async function renderDialog(onConfirm = vi.fn(), onCancel = vi.fn()) {
  render(<PruneConfirm models={models} onConfirm={onConfirm} onCancel={onCancel} />);
  return within(await screen.findByRole("alertdialog"));
}

describe("PruneConfirm", () => {
  afterEach(() => {
    cleanup();
  });

  it("titles the dialog and states the count and the space freed", async () => {
    const dialog = await renderDialog();

    expect(dialog.getByRole("heading", { name: "Remove Models" })).toBeTruthy();
    expect(dialog.getByText("2 models, 3.0 GB freed.")).toBeTruthy();
  });

  it("lists each name with its size", async () => {
    const dialog = await renderDialog();

    expect(dialog.getByText(/old-cc:latest/)).toBeTruthy();
    expect(dialog.getByText(/someone\/model:latest/)).toBeTruthy();
  });

  it("removes the listed names when the action is chosen", async () => {
    const onConfirm = vi.fn();
    const dialog = await renderDialog(onConfirm);

    fireEvent.click(dialog.getByRole("button", { name: "Remove Models" }));

    expect(onConfirm).toHaveBeenCalledWith(["old-cc:latest", "someone/model:latest"]);
  });

  it("cancels through the Cancel button", async () => {
    const onCancel = vi.fn();
    const dialog = await renderDialog(vi.fn(), onCancel);

    fireEvent.click(dialog.getByRole("button", { name: "Cancel" }));

    expect(onCancel).toHaveBeenCalledTimes(1);
  });
});
