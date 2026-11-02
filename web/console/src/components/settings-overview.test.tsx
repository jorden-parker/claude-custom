import { cleanup, render, screen, within } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { SettingsOverview } from "./settings-overview";

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
    env: { CLAUDE_OLLAMA_LEASE: "0", CLAUDE_OLLAMA_LEASE_HEARTBEAT: "60" },
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
  return within(screen.getByRole("row", { name: new RegExp(`^${key}\\b`) }));
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

    await screen.findByText("Hold an Ollama residency lease and heartbeat");
    const lease = rowFor("CLAUDE_OLLAMA_LEASE");
    expect(lease.getAllByRole("cell").map((cell) => cell.textContent)).toEqual([
      "CLAUDE_OLLAMA_LEASE",
      "Hold an Ollama residency lease and heartbeat",
      "on",
      "n/a",
      "off",
      "default",
    ]);
    expect(
      rowFor("CLAUDE_OLLAMA_LEASE_HEARTBEAT")
        .getAllByRole("cell")
        .map((cell) => cell.textContent),
    ).toEqual([
      "CLAUDE_OLLAMA_LEASE_HEARTBEAT",
      "Seconds between keep-alive heartbeats",
      "120",
      "n/a",
      "60",
      "default",
    ]);
    expect(
      rowFor("CLAUDE_CUSTOM_FRICTION")
        .getAllByRole("cell")
        .map((cell) => cell.textContent),
    ).toEqual([
      "CLAUDE_CUSTOM_FRICTION",
      "Reset a looping guard after three identical denials",
      "on",
      "default",
      "default",
      "default",
    ]);

    const headers = screen
      .getAllByRole("columnheader")
      .map((header) => header.textContent);
    expect(headers).toEqual([
      "Key",
      "Label",
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
        .getByRole("row", { name: /^CLAUDE_OLLAMA_PROXY_RECORD\b/ })
        .getAttribute("id"),
    ).toBe("CLAUDE_OLLAMA_PROXY_RECORD");
    expect(
      screen.getAllByRole("row", {
        name: /^(Prompt and context|Guards|Ollama residency|Diagnostics|Browser)$/,
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
