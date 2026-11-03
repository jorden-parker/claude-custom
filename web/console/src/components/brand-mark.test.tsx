import { cleanup, render } from "@testing-library/react";
import { afterEach, describe, expect, it } from "vitest";
import { BrandMark } from "./brand-mark";

describe("BrandMark", () => {
  afterEach(() => {
    cleanup();
  });

  it("renders a decorative svg hidden from assistive tech", () => {
    const { container } = render(<BrandMark />);
    const mark = container.firstElementChild;

    expect(mark?.getAttribute("aria-hidden")).toBe("true");
    expect(mark?.querySelector("svg")).not.toBeNull();
  });

  it("passes a custom class through to the mark", () => {
    const { container } = render(<BrandMark className="size-8" />);

    expect(container.firstElementChild?.getAttribute("class")).toContain(
      "size-8",
    );
  });
});
