import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { ThemeProvider } from "next-themes";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { ThemeShortcut } from "./theme-shortcut";

function renderShortcut() {
  return render(
    <ThemeProvider attribute="class" defaultTheme="light" enableSystem>
      <ThemeShortcut />
      <input aria-label="field" />
    </ThemeProvider>,
  );
}

function isDark() {
  return document.documentElement.classList.contains("dark");
}

describe("ThemeShortcut", () => {
  beforeEach(() => {
    window.localStorage.clear();
    document.documentElement.className = "";
    vi.stubGlobal(
      "matchMedia",
      vi.fn().mockImplementation(() => ({
        matches: false,
        addEventListener: vi.fn(),
        removeEventListener: vi.fn(),
        addListener: vi.fn(),
        removeListener: vi.fn(),
      })),
    );
  });

  afterEach(() => {
    cleanup();
    vi.unstubAllGlobals();
  });

  it("switches dark on and off when d is pressed with no sidebar mounted", () => {
    renderShortcut();
    expect(isDark()).toBe(false);

    fireEvent.keyDown(document.body, { key: "d" });
    expect(isDark()).toBe(true);

    fireEvent.keyDown(document.body, { key: "d" });
    expect(isDark()).toBe(false);
  });

  it("ignores d while focus is in an input", () => {
    renderShortcut();

    fireEvent.keyDown(screen.getByLabelText("field"), { key: "d" });

    expect(isDark()).toBe(false);
  });

  it("ignores d while a modifier key is held", () => {
    renderShortcut();

    fireEvent.keyDown(document.body, { key: "d", metaKey: true });

    expect(isDark()).toBe(false);
  });
});
