import { cleanup, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { ProfileList } from "./profile-list";

const PROFILES = [
  { id: "claude-code", title: "Claude Code", kind: "claude-code", model: null, context: null, overrides: 0 },
  { id: "ollama-27b", title: "Ollama 27b", kind: "ollama", model: "qwen3.8-27b-cc", context: 65536, overrides: 3 },
];

describe("ProfileList", () => {
  afterEach(() => {
    cleanup();
    vi.restoreAllMocks();
  });

  it("links each profile to its page with its model, context and override count", async () => {
    vi.spyOn(globalThis, "fetch").mockResolvedValue(
      new Response(JSON.stringify({ profiles: PROFILES }), { headers: { "Content-Type": "application/json" } }),
    );
    render(<ProfileList />);

    const card = await screen.findByRole("link", { name: /Ollama 27b/ });
    expect(card.getAttribute("href")).toBe("/profiles/ollama-27b");
    expect(card.textContent).toContain("qwen3.8-27b-cc, context 65536");
    expect(card.textContent).toContain("3 overrides");
    expect(screen.getByRole("link", { name: /Claude Code/ }).textContent).toContain("0 overrides");
  });

  it("shows the error when the profiles cannot be listed", async () => {
    vi.spyOn(globalThis, "fetch").mockResolvedValue(new Response("{}", { status: 500 }));
    render(<ProfileList />);

    expect(await screen.findByText("profiles failed with status 500")).toBeTruthy();
  });
});
