import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { ThemeProvider } from "next-themes";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { SidebarProvider } from "@/components/ui/sidebar";
import { ThemeSwitch } from "./theme-switch";

function renderSwitch() {
  return render(
    <ThemeProvider
      attribute="class"
      defaultTheme="system"
      enableSystem
      disableTransitionOnChange
    >
      <SidebarProvider>
        <ThemeSwitch />
      </SidebarProvider>
    </ThemeProvider>,
  );
}

function themeButton(label: string) {
  return screen.getByRole("button", { name: label });
}

describe("ThemeSwitch", () => {
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

  it("cycles system, light, dark and back to system on click", () => {
    renderSwitch();
    expect(themeButton("Theme: System")).toBeTruthy();

    fireEvent.click(themeButton("Theme: System"));
    expect(themeButton("Theme: Light")).toBeTruthy();

    fireEvent.click(themeButton("Theme: Light"));
    expect(themeButton("Theme: Dark")).toBeTruthy();

    fireEvent.click(themeButton("Theme: Dark"));
    expect(themeButton("Theme: System")).toBeTruthy();
  });

  it("puts the dark class on the document once dark is chosen", () => {
    renderSwitch();

    fireEvent.click(themeButton("Theme: System"));
    fireEvent.click(themeButton("Theme: Light"));

    expect(document.documentElement.classList.contains("dark")).toBe(true);
  });
});
