import { cleanup, render } from "@testing-library/react";
import { afterEach, describe, expect, it } from "vitest";
import { LiveMockSheet } from "./live-mock-sheet";

describe("LiveMockSheet", () => {
  afterEach(cleanup);

  it("shows the element outline at full height and wraps it", () => {
    render(
      <LiveMockSheet
        lines={[
          "=== run 1/1 settings",
          '{"op":"add","path":"/root","value":"main"}',
        ]}
        running={false}
      />,
    );
    const outline = document.querySelector("pre")!;
    expect(outline.className).toContain("whitespace-pre-wrap");
    expect(outline.closest('[data-slot="scroll-area"]')).toBeNull();
  });
});
