import { cleanup, render } from "@testing-library/react";
import { afterEach, describe, expect, it } from "vitest";
import { GardenSprite } from "./garden-sprite";

describe("GardenSprite", () => {
  afterEach(() => {
    cleanup();
  });

  it("renders a decorative svg hidden from assistive tech", () => {
    const { container } = render(<GardenSprite />);
    const svg = container.querySelector("svg");
    expect(svg).not.toBeNull();
    expect(svg?.getAttribute("aria-hidden")).toBe("true");
  });

  it("bobs only when motion is allowed", () => {
    const { container } = render(<GardenSprite />);
    expect(container.querySelector("svg")?.getAttribute("class")).toContain(
      "motion-safe:animate-sprout-bob",
    );
  });

  it("passes a custom class through to the svg", () => {
    const { container } = render(<GardenSprite className="size-8" />);
    expect(container.querySelector("svg")?.getAttribute("class")).toContain("size-8");
  });
});
