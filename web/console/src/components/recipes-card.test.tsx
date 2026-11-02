import { cleanup, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { RecipesCard } from "./recipes-card";

describe("RecipesCard", () => {
  afterEach(() => {
    cleanup();
    vi.restoreAllMocks();
  });

  it("lists each hook's match patterns and steps", async () => {
    vi.spyOn(globalThis, "fetch").mockResolvedValue(
      Response.json({
        recipes: [
          {
            hook: "tdd-guard",
            entries: [
              {
                match: "edit or add the test first",
                steps: ["edit the test", "run it"],
              },
            ],
          },
        ],
      }),
    );
    render(<RecipesCard />);

    expect(
      await screen.findByRole("heading", { level: 3, name: "tdd-guard" }),
    ).toBeTruthy();
    expect(screen.getByText("edit or add the test first")).toBeTruthy();
    expect(
      screen.getAllByRole("listitem").map((item) => item.textContent),
    ).toEqual(["edit the test", "run it"]);
    expect(fetch).toHaveBeenCalledWith("/api/recipes", { cache: "no-store" });
  });

  it("shows an empty state", async () => {
    vi.spyOn(globalThis, "fetch").mockResolvedValue(
      Response.json({ recipes: [] }),
    );
    render(<RecipesCard />);
    expect(await screen.findByText("No recovery recipes found.")).toBeTruthy();
  });
});
