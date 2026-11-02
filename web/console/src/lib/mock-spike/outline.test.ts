import { describe, expect, it } from "vitest";
import { specOutline } from "./outline.ts";

describe("specOutline", () => {
  it("lists elements depth first with their props", () => {
    const spec = {
      root: "main",
      elements: {
        main: {
          type: "Stack",
          props: { direction: "vertical", gap: null },
          children: ["title", "cta"],
        },
        title: {
          type: "Heading",
          props: { text: "Pricing", level: "1" },
          children: [],
        },
        cta: {
          type: "Button",
          props: { label: "Buy", variant: "primary" },
          children: [],
        },
      },
    };
    expect(specOutline(spec)).toEqual([
      'Stack direction="vertical" gap=null',
      '  Heading text="Pricing" level="1"',
      '  Button label="Buy" variant="primary"',
    ]);
  });

  it("skips missing children and never loops on a cycle", () => {
    const spec = {
      root: "a",
      elements: {
        a: { type: "Stack", props: {}, children: ["b", "missing"] },
        b: { type: "Stack", props: {}, children: ["a"] },
      },
    };
    expect(specOutline(spec)).toEqual(["Stack", "  Stack"]);
  });

  it("returns nothing when the root is missing", () => {
    expect(specOutline({ root: "", elements: {} })).toEqual([]);
  });
});
