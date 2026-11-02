import { cleanup, render, screen } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { SidebarProvider } from "@/components/ui/sidebar";
import { ConsoleNav, isActiveSection } from "./console-nav";

vi.mock("next/navigation", () => ({
  usePathname: () => "/runs/run-42",
}));

function renderNav() {
  return render(
    <SidebarProvider>
      <ConsoleNav />
    </SidebarProvider>,
  );
}

describe("ConsoleNav", () => {
  beforeEach(() => {
    vi.stubGlobal(
      "matchMedia",
      vi.fn().mockImplementation(() => ({
        matches: false,
        addEventListener: vi.fn(),
        removeEventListener: vi.fn(),
      })),
    );
  });

  afterEach(() => {
    cleanup();
    vi.unstubAllGlobals();
  });

  it("marks the section of the current page as active", () => {
    renderNav();
    expect(
      screen.getByRole("link", { name: "Runs" }).hasAttribute("data-active"),
    ).toBe(true);
    expect(
      screen.getByRole("link", { name: "Reviews" }).hasAttribute("data-active"),
    ).toBe(false);
  });
});

describe("isActiveSection", () => {
  it.each([
    ["/", "/", true],
    ["/", "/runs", false],
    ["/runs", "/runs", true],
    ["/runs/run-42", "/runs", true],
    ["/runs-archive", "/runs", false],
    ["/runs", "/", false],
  ])("for pathname %s and href %s returns %s", (pathname, href, expected) => {
    expect(isActiveSection(pathname, href)).toBe(expected);
  });
});
