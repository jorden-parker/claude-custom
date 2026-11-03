import { cleanup, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it } from "vitest";
import { SectionCard } from "./section-card";

const section = {
  href: "/runs",
  title: "Runs",
  summary: "Every job",
  group: "Work",
} as const;

describe("SectionCard", () => {
  afterEach(() => {
    cleanup();
  });

  it("stretches the link to the full height of its grid row", () => {
    render(<SectionCard section={section} />);

    expect(screen.getByRole("link").getAttribute("class")).toContain("h-full");
  });

  it("stretches the card to the full height of its link", () => {
    const { container } = render(<SectionCard section={section} />);
    const card = container.querySelector('[data-slot="card"]');

    expect(card?.getAttribute("class")).toContain("h-full");
  });

  it("reserves two summary lines and clamps longer text", () => {
    render(<SectionCard section={section} />);
    const summary = screen.getByText("Every job");

    expect(summary.getAttribute("class")).toContain("line-clamp-2");
    expect(summary.getAttribute("class")).toContain("min-h-10");
    expect(summary.getAttribute("title")).toBe("Every job");
  });
});
