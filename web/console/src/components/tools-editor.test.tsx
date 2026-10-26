import { cleanup, fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { ToolsEditor } from "./tools-editor";

vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: vi.fn() }),
}));

const REPORT = {
  path: "/home/owner/.claude/settings.json",
  tools: [
    { name: "Bash", description: "Run shell commands", promptsByDefault: true, permission: "allow", disabled: false },
    { name: "WebFetch", description: "Fetch a web page", promptsByDefault: true, permission: "deny", disabled: false },
  ],
};

const jsonResponse = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

const rowFor = (name: string) => within(screen.getByRole("row", { name: new RegExp(`^${name}\\b`) }));

describe("ToolsEditor", () => {
  beforeEach(() => {
    vi.spyOn(globalThis, "fetch").mockImplementation(async (input, init) => {
      const url = String(input);
      if (url === "/api/tools") {
        return jsonResponse(REPORT);
      }
      if (url === "/api/runs" && init?.method === "POST") {
        return jsonResponse({ id: "run-7" }, 201);
      }
      return jsonResponse([]);
    });
  });

  afterEach(() => {
    cleanup();
    vi.restoreAllMocks();
  });

  it("lists each tool with its description", async () => {
    render(<ToolsEditor />);

    expect(await screen.findByText("Fetch a web page")).toBeTruthy();
    expect(screen.getByText("/home/owner/.claude/settings.json")).toBeTruthy();
  });

  it("shows the keep-out-of-context switch for allow and ask, not for deny", async () => {
    render(<ToolsEditor />);
    await screen.findByText("Fetch a web page");

    expect(rowFor("Bash").getByRole("switch")).toBeTruthy();
    expect(rowFor("WebFetch").queryByRole("switch")).toBeNull();

    fireEvent.click(rowFor("Bash").getByRole("button", { name: "deny" }));
    expect(rowFor("Bash").queryByRole("switch")).toBeNull();
  });

  it("shows the change bar when a permission changes and discards it", async () => {
    render(<ToolsEditor />);
    await screen.findByText("Fetch a web page");
    expect(screen.queryByRole("button", { name: "Discard" })).toBeNull();

    fireEvent.click(rowFor("Bash").getByRole("button", { name: "ask" }));
    expect(screen.getByText("1 change")).toBeTruthy();

    fireEvent.click(screen.getByRole("button", { name: "Discard" }));
    expect(screen.queryByText("1 change")).toBeNull();
  });

  it("saves the changed rows with the tools-set command in stay mode", async () => {
    render(<ToolsEditor />);
    await screen.findByText("Fetch a web page");

    fireEvent.click(rowFor("WebFetch").getByRole("button", { name: "ask" }));
    fireEvent.click(screen.getByRole("button", { name: "Save" }));

    await waitFor(() =>
      expect(fetch).toHaveBeenCalledWith(
        "/api/runs",
        expect.objectContaining({
          method: "POST",
          body: JSON.stringify({ command: "tools-set", params: { assignments: "WebFetch=ask" } }),
        }),
      ),
    );
  });

  it("shows the catalog error and how to fix it", async () => {
    vi.spyOn(globalThis, "fetch").mockResolvedValue(
      jsonResponse({ message: "claude-tools: no tool catalog yet; open claude-tools once and sync" }, 502),
    );
    render(<ToolsEditor />);

    expect(await screen.findByText("claude-tools: no tool catalog yet; open claude-tools once and sync")).toBeTruthy();
    expect(screen.getByText(/Open claude-tools once in a terminal/)).toBeTruthy();
  });
});
