import { cleanup, render } from "@testing-library/react";
import { afterEach, describe, expect, it } from "vitest";
import { MockSheet } from "./mock-sheet";
import { scoreReply } from "@/lib/mock-spike/score.ts";

const reply = [
  '{"op":"add","path":"/root","value":"main"}',
  '{"op":"add","path":"/elements/main","value":{"type":"Card","props":{"title":"Pricing","description":null},"children":[]}}',
].join("\n");

describe("MockSheet", () => {
  afterEach(cleanup);

  it("shows the element outline at full height and wraps it", () => {
    render(
      <MockSheet
        report={{
          file: "mock-spike-1.json",
          model: "m",
          preset: null,
          verdict: "sound",
          runs: [
            {
              brief: "pricing",
              run: 1,
              score: scoreReply(reply),
              spec: { root: "main", elements: {} },
            },
          ],
        }}
      />,
    );
    const outline = document.querySelector("pre")!;
    expect(outline.className).toContain("whitespace-pre-wrap");
    expect(outline.closest('[data-slot="scroll-area"]')).toBeNull();
  });
});
