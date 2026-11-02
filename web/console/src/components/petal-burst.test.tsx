import { cleanup, render } from "@testing-library/react";
import { afterEach, describe, expect, it } from "vitest";
import { PetalBurst } from "./petal-burst";

function petalsIn(container: HTMLElement): HTMLElement[] {
  return Array.from(container.querySelectorAll<HTMLElement>("[data-petal]"));
}

describe("PetalBurst", () => {
  afterEach(() => {
    cleanup();
  });

  it("shows petals when the run ended ok", () => {
    const { container } = render(<PetalBurst status="ok" />);
    expect(petalsIn(container).length).toBeGreaterThan(0);
  });

  it.each(["running", "failed", "cancelled", "lost"] as const)(
    "shows nothing when the run is %s",
    (status) => {
      const { container } = render(<PetalBurst status={status} />);
      expect(petalsIn(container)).toEqual([]);
    },
  );

  it("is hidden from assistive tech", () => {
    const { container } = render(<PetalBurst status="ok" />);
    expect(container.firstElementChild?.getAttribute("aria-hidden")).toBe("true");
  });

  it("falls once under a single-shot animation instead of looping", () => {
    const { container } = render(<PetalBurst status="ok" />);
    for (const petal of petalsIn(container)) {
      expect(petal.className).toContain("motion-safe:animate-petal-fall");
      expect(petal.className).not.toContain("infinite");
    }
  });
});
