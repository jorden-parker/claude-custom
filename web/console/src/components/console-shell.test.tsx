import { cleanup, render, screen, within } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { ConsoleShell } from "./console-shell";

vi.mock("next/navigation", () => ({
  usePathname: () => "/runs",
}));

describe("ConsoleShell", () => {
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

  it("keeps a header with the sidebar trigger", () => {
    render(
      <ConsoleShell>
        <p>page body</p>
      </ConsoleShell>,
    );
    const headerBanner = screen.getByRole("banner");
    expect(
      within(headerBanner).getByRole("button", { name: "Toggle Sidebar" }),
    ).toBeTruthy();
  });

  it("shows the header only on phones", () => {
    render(
      <ConsoleShell>
        <p>page body</p>
      </ConsoleShell>,
    );
    expect(screen.getByRole("banner").className).toContain("md:hidden");
  });

  it("shows the brand link in the header for small screens", () => {
    render(
      <ConsoleShell>
        <p>page body</p>
      </ConsoleShell>,
    );
    const headerBanner = screen.getByRole("banner");
    const brandLink = within(headerBanner).getByRole("link", {
      name: "claude-ollama",
    });

    expect(brandLink.getAttribute("href")).toBe("/");
  });

  it("fills the page width token with padding", () => {
    render(
      <ConsoleShell>
        <p>page body</p>
      </ConsoleShell>,
    );
    const mainRegion = screen.getByText("page body").closest("main");
    expect(mainRegion).not.toBeNull();
    expect(mainRegion!.className).toContain("max-w-(--ds-page-width)");
    expect(mainRegion!.className).toContain("px-4");
  });
});
