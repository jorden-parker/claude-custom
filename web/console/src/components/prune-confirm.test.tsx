import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import type { InstalledModel } from "@/lib/model-display";
import { PruneConfirm } from "./prune-confirm";

const models: InstalledModel[] = [
  { name: "old-cc:latest", class: "orphan", bytes: 1_000_000_000, loaded: false },
  { name: "someone/model:latest", class: "third-party", bytes: 2_000_000_000, loaded: false },
];

describe("PruneConfirm", () => {
  it("lists each name with its size and the total freed", () => {
    const markup = renderToStaticMarkup(<PruneConfirm models={models} onConfirm={() => {}} onCancel={() => {}} />);

    expect(markup).toContain("old-cc:latest");
    expect(markup).toContain("someone/model:latest");
    expect(markup).toContain("free 3.0 GB");
    expect(markup).toContain("Remove these");
    expect(markup).toContain("Cancel");
  });
});
