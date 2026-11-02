import { describe, expect, it } from "vitest";
import { liveCellsFrom } from "./live.ts";

const root = '{"op":"add","path":"/root","value":"main"}';
const card =
  '{"op":"add","path":"/elements/main","value":{"type":"Card","props":{"title":"Pricing","description":null},"children":[]}}';

describe("liveCellsFrom", () => {
  it("opens a cell per run marker and compiles the patches that follow", () => {
    const cells = liveCellsFrom([
      "mock-spike: m at http://x, 2 runs",
      "=== run 1/2 pricing",
      root,
      "thinking aloud",
      card,
      "run 1/2 pricing: patches 2/3 lines",
      "=== run 2/2 pricing",
      root,
    ]);
    expect(cells.map((cell) => [cell.label, cell.patches])).toEqual([
      ["1/2 pricing", 2],
      ["2/2 pricing", 1],
    ]);
    expect(cells[0].spec.elements?.main.type).toBe("Card");
    expect(cells[1].spec.root).toBe("main");
  });

  it("ignores patch lines before the first marker", () => {
    expect(liveCellsFrom([root, card])).toEqual([]);
  });

  it("always carries an elements map, even when only the root has arrived", () => {
    expect(liveCellsFrom(["=== run 1/1 settings", root])[0].spec).toEqual({
      root: "main",
      elements: {},
    });
  });

  it("gives an empty spec to a cell with no patches yet", () => {
    expect(liveCellsFrom(["=== run 1/1 settings"])).toEqual([
      { label: "1/1 settings", patches: 0, spec: { root: "", elements: {} } },
    ]);
  });
});
