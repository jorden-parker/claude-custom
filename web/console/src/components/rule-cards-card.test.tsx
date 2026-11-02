import { cleanup, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { RuleCardsCard } from "./rule-cards-card";

describe("RuleCardsCard", () => {
  afterEach(() => {
    cleanup();
    vi.restoreAllMocks();
  });

  it("lists each card's id, triggers and body with a link to the Settings switch", async () => {
    vi.spyOn(globalThis, "fetch").mockResolvedValue(
      Response.json({
        cards: [
          {
            id: "bash",
            triggers: ["tool Bash"],
            body: "Bash runs in a sandbox.",
          },
          {
            id: "go",
            triggers: ["suffix .go", "command go test"],
            body: "gofmt first.",
          },
        ],
      }),
    );
    render(<RuleCardsCard />);

    expect(await screen.findByText("Bash runs in a sandbox.")).toBeTruthy();
    expect(
      screen
        .getAllByRole("heading", { level: 3 })
        .map((heading) => heading.textContent),
    ).toEqual(["bash", "go"]);
    expect(screen.getByText("suffix .go, command go test")).toBeTruthy();
    expect(fetch).toHaveBeenCalledWith("/api/rule-cards", {
      cache: "no-store",
    });
    expect(
      screen
        .getByRole("link", { name: "CLAUDE_OLLAMA_RULE_CARDS" })
        .getAttribute("href"),
    ).toBe("/settings#CLAUDE_OLLAMA_RULE_CARDS");
  });

  it("shows an empty state and a failed load", async () => {
    vi.spyOn(globalThis, "fetch").mockResolvedValueOnce(
      Response.json({ cards: [] }),
    );
    render(<RuleCardsCard />);
    expect(await screen.findByText("No rule cards found.")).toBeTruthy();
    cleanup();

    vi.spyOn(globalThis, "fetch").mockResolvedValueOnce(
      Response.json(
        { message: "rule-cards: skipping broken.md" },
        { status: 502 },
      ),
    );
    render(<RuleCardsCard />);
    expect(
      await screen.findByText("rule-cards: skipping broken.md"),
    ).toBeTruthy();
  });
});
