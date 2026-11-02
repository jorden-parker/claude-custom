import { describe, expect, it } from "vitest";
import { mockSystemPrompt } from "./catalog.ts";
import { DESIGN_RULES } from "./design-rules.ts";

describe("mockSystemPrompt", () => {
  it("carries every design rule and the chosen preset's style paragraph", () => {
    const prompt = mockSystemPrompt("brutalist");
    for (const rule of DESIGN_RULES) {
      expect(prompt).toContain(rule);
    }
    expect(prompt).toContain("Style, Brutalist:");
    expect(prompt).not.toContain("Style, Calm SaaS:");
  });

  it("falls back to the default preset", () => {
    expect(mockSystemPrompt()).toContain("Style, Calm SaaS:");
    expect(mockSystemPrompt("nope")).toContain("Style, Calm SaaS:");
  });
});
