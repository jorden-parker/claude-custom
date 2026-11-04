import { cleanup, render, screen, within } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { PROFILE_ENV_FIELDS } from "@/lib/profile-rules";
import { SettingsOverview } from "./settings-overview";

const labelOf = (key: string) =>
  PROFILE_ENV_FIELDS.find((field) => field.key === key)?.label ?? key;

const PROFILES = [
  {
    id: "claude-code",
    title: "Claude Code",
    kind: "claude-code",
    model: null,
    context: null,
    overrides: 1,
    env: {},
  },
  {
    id: "ollama-27b",
    title: "Ollama 27b",
    kind: "ollama",
    model: "qwen3.8-27b-cc",
    context: 65536,
    overrides: 2,
    env: {
      CLAUDE_OLLAMA_LEASE: "0",
      CLAUDE_OLLAMA_HANDOFF_PCT: "60",
      CLAUDE_OLLAMA_TEST_AFTER_EDIT: "0",
    },
  },
  {
    id: "ollama-35b",
    title: "Ollama 35b",
    kind: "ollama",
    model: "qwen3.6-35b-cc",
    context: 98304,
    overrides: 0,
    env: {},
  },
];

const jsonResponse = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });

function rowFor(key: string) {
  return within(document.getElementById(key)!);
}

describe("SettingsOverview", () => {
  afterEach(() => {
    cleanup();
    vi.restoreAllMocks();
  });

  it("tables every switch with its label, default and each profile's value, linking to the editors", async () => {
    vi.spyOn(globalThis, "fetch").mockResolvedValue(
      jsonResponse({ profiles: PROFILES }),
    );
    render(<SettingsOverview />);

    await screen.findByText(labelOf("CLAUDE_OLLAMA_LEASE"));
    expect(
      document.querySelector('[data-slot="table-container"] table'),
    ).not.toBeNull();
    const lease = rowFor("CLAUDE_OLLAMA_LEASE");
    expect(lease.getAllByRole("cell").map((cell) => cell.textContent)).toEqual([
      `${labelOf("CLAUDE_OLLAMA_LEASE")}CLAUDE_OLLAMA_LEASE`,
      "on",
      "n/a",
      "off",
      "default",
    ]);
    expect(
      rowFor("CLAUDE_OLLAMA_HANDOFF_PCT")
        .getAllByRole("cell")
        .map((cell) => cell.textContent),
    ).toEqual([
      `${labelOf("CLAUDE_OLLAMA_HANDOFF_PCT")}CLAUDE_OLLAMA_HANDOFF_PCT`,
      "70",
      "n/a",
      "60",
      "default",
    ]);
    expect(
      rowFor("CLAUDE_OLLAMA_TEST_AFTER_EDIT")
        .getAllByRole("cell")
        .map((cell) => cell.textContent),
    ).toEqual([
      "After each edit: suggest the test, or run itCLAUDE_OLLAMA_TEST_AFTER_EDIT",
      "suggest",
      "n/a",
      "off",
      "default",
    ]);
    expect(
      rowFor("CLAUDE_CUSTOM_FRICTION")
        .getAllByRole("cell")
        .map((cell) => cell.textContent),
    ).toEqual([
      "Reset a looping guard after three identical denialsCLAUDE_CUSTOM_FRICTION",
      "on",
      "default",
      "default",
      "default",
    ]);

    const headers = screen
      .getAllByRole("columnheader")
      .map((header) => header.textContent);
    expect(headers).toEqual([
      "Switch",
      "Default",
      "Claude Code",
      "Ollama 27b",
      "Ollama 35b",
    ]);
    expect(
      screen.getByRole("link", { name: "Ollama 27b" }).getAttribute("href"),
    ).toBe("/profiles/ollama-27b");
    expect(
      screen.getByRole("link", { name: "Claude Code" }).getAttribute("href"),
    ).toBe("/profiles/claude-code");
    expect(screen.getAllByRole("rowgroup")).toHaveLength(6);
    expect(
      screen.getByRole("link", { name: "Diagnose" }).getAttribute("href"),
    ).toBe("/diagnose");
    expect(
      screen
        .getByRole("row", { name: /CLAUDE_OLLAMA_PROXY_RECORD/ })
        .getAttribute("id"),
    ).toBe("CLAUDE_OLLAMA_PROXY_RECORD");
    const leaseKey = within(document.getElementById("CLAUDE_OLLAMA_LEASE")!)
      .getByText("CLAUDE_OLLAMA_LEASE");
    expect(leaseKey.className).toContain("font-mono");
    expect(leaseKey.className).toContain("[overflow-wrap:anywhere]");
    for (const header of screen.getAllByRole("columnheader")) {
      expect(header.className).toContain("whitespace-normal");
    }
    expect(
      screen.getAllByRole("row", {
        name: /^(Prompt and context|Guards|Model residency|Diagnostics|Browser)$/,
      }),
    ).toHaveLength(5);
  });

  it("reports a failed load", async () => {
    vi.spyOn(globalThis, "fetch").mockResolvedValue(jsonResponse({}, 500));
    render(<SettingsOverview />);
    expect(
      await screen.findByText("profiles failed with status 500"),
    ).toBeTruthy();
  });
});
