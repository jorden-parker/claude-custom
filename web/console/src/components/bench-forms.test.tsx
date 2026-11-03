import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it, vi } from "vitest";
import { BenchForms } from "./bench-forms";

vi.mock("next/navigation", () => ({ useRouter: () => ({ push: () => undefined }) }));

describe("BenchForms", () => {
  it("offers a card for every bench, task eval and prefix A/B included", () => {
    const markup = renderToStaticMarkup(<BenchForms sizes={["27b"]} />);
    expect(markup).toContain("Task eval");
    expect(markup).toContain("Prefix A/B");
  });
});
