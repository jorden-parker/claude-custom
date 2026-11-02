import { cleanup, fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { ProfileEditor } from "./profile-editor";

const TOOL = (name: string, permission: string, description: string) => ({
  name,
  description,
  promptsByDefault: true,
  permission,
  disabled: false,
});

const CLAUDE_CODE_DETAIL = {
  id: "claude-code",
  title: "Claude Code",
  kind: "claude-code",
  model: null,
  context: null,
  overrides: 0,
  override: {},
  base: {
    settingsPath: "/repo/personal/settings.tokens.json",
    tools: [TOOL("Bash", "default", "Run shell commands"), TOOL("WebFetch", "allow", "Fetch a web page")],
    context: null,
    parameters: {},
    hooks: [{ event: "Stop", matcher: "*", command: "stop-verify.py" }],
    mcpServers: [],
  },
};

const OLLAMA_DETAIL = {
  ...CLAUDE_CODE_DETAIL,
  id: "ollama-27b",
  title: "Ollama 27b",
  kind: "ollama",
  model: "qwen3.8-27b-cc",
  context: 65536,
  base: {
    ...CLAUDE_CODE_DETAIL.base,
    settingsPath: "/repo/ollama/settings.27b.json",
    context: 65536,
    parameters: { temperature: 0.7 },
    mcpServers: ["code-search", "repo", "dev"],
  },
};

const jsonResponse = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

const rowFor = (name: string) => within(screen.getByRole("row", { name: new RegExp(`^${name}\\b`) }));

function mockProfileApi(detail: unknown, saveResponse: () => Response = () => jsonResponse({ override: {} })) {
  const fetchMock = vi.spyOn(globalThis, "fetch").mockImplementation(async (_input, init) => {
    if (init?.method === "PUT") {
      return saveResponse();
    }
    return jsonResponse(detail);
  });
  return fetchMock;
}

describe("ProfileEditor", () => {
  beforeEach(() => {
    vi.restoreAllMocks();
  });

  afterEach(() => {
    cleanup();
    vi.restoreAllMocks();
  });

  it("shows each tool with its default and saves the one you changed", async () => {
    const fetchMock = mockProfileApi(CLAUDE_CODE_DETAIL, () => jsonResponse({ override: { tools: { WebFetch: "deny" } } }));
    render(<ProfileEditor id="claude-code" />);

    expect(await screen.findByText("Fetch a web page")).toBeTruthy();
    expect(rowFor("WebFetch").getByRole("cell", { name: "allow" })).toBeTruthy();
    expect(screen.getByRole("button", { name: "Save" }).hasAttribute("disabled")).toBe(true);

    fireEvent.click(rowFor("WebFetch").getByRole("button", { name: "deny" }));
    expect(screen.getByText("Unsaved changes")).toBeTruthy();

    fireEvent.click(screen.getByRole("button", { name: "Save" }));
    await waitFor(() =>
      expect(fetchMock).toHaveBeenCalledWith(
        "/api/profiles/claude-code",
        expect.objectContaining({ method: "PUT", body: JSON.stringify({ tools: { WebFetch: "deny" } }) }),
      ),
    );
    expect(await screen.findByText("saved; applies to the next session")).toBeTruthy();
  });

  it("resets to defaults by saving an empty override", async () => {
    const fetchMock = mockProfileApi(CLAUDE_CODE_DETAIL);
    render(<ProfileEditor id="claude-code" />);
    await screen.findByText("Fetch a web page");

    fireEvent.click(screen.getByRole("button", { name: "Reset to defaults" }));

    await waitFor(() =>
      expect(fetchMock).toHaveBeenCalledWith(
        "/api/profiles/claude-code",
        expect.objectContaining({ method: "PUT", body: "{}" }),
      ),
    );
  });

  it("shows the server's message when a save is refused", async () => {
    mockProfileApi(CLAUDE_CODE_DETAIL, () => jsonResponse({ message: "unknown tool Nope" }, 400));
    render(<ProfileEditor id="claude-code" />);
    await screen.findByText("Fetch a web page");

    fireEvent.click(rowFor("Bash").getByRole("button", { name: "ask" }));
    fireEvent.click(screen.getByRole("button", { name: "Save" }));

    expect(await screen.findByText("unknown tool Nope")).toBeTruthy();
  });

  it("offers the sandbox switch for claude-code only", async () => {
    mockProfileApi(CLAUDE_CODE_DETAIL);
    render(<ProfileEditor id="claude-code" />);
    await screen.findByText("Fetch a web page");

    fireEvent.click(screen.getByRole("tab", { name: "Sandbox & model" }));

    expect(await screen.findByRole("switch", { name: "Sandbox enabled" })).toBeTruthy();
  });

  it("shows context and parameter fields for an Ollama profile, with the base as placeholders", async () => {
    mockProfileApi(OLLAMA_DETAIL);
    render(<ProfileEditor id="ollama-27b" />);
    await screen.findByText("Fetch a web page");

    fireEvent.click(screen.getByRole("tab", { name: "Sandbox & model" }));

    expect(await screen.findByRole("spinbutton", { name: "Context tokens" })).toBeTruthy();
    expect(screen.getByRole("spinbutton", { name: "temperature" }).getAttribute("placeholder")).toBe("0.7");
    expect(screen.getByText("Sandbox is always on for Ollama profiles.")).toBeTruthy();
  });

  it("offers a thinking switch for an Ollama profile that is off by default", async () => {
    mockProfileApi(OLLAMA_DETAIL);
    render(<ProfileEditor id="ollama-27b" />);
    await screen.findByText("Fetch a web page");

    fireEvent.click(screen.getByRole("tab", { name: "Sandbox & model" }));

    const thinking = (await screen.findByRole("switch", { name: "Thinking enabled" })) as HTMLInputElement;
    expect(thinking.checked).toBe(false);
    fireEvent.click(thinking);
    expect(screen.getByText("Unsaved changes")).toBeTruthy();
  });

  it("lists the hooks read-only and toggles the Ollama MCP servers", async () => {
    mockProfileApi(OLLAMA_DETAIL);
    render(<ProfileEditor id="ollama-27b" />);
    await screen.findByText("Fetch a web page");

    fireEvent.click(screen.getByRole("tab", { name: "MCP & hooks" }));

    expect(await screen.findByText("stop-verify.py")).toBeTruthy();
    fireEvent.click(screen.getByRole("switch", { name: "MCP dev" }));
    expect(screen.getByText("Unsaved changes")).toBeTruthy();
  });

  it("offers only default and off for Agent on an Ollama profile", async () => {
    mockProfileApi({
      ...OLLAMA_DETAIL,
      base: { ...OLLAMA_DETAIL.base, tools: [...OLLAMA_DETAIL.base.tools, TOOL("Agent", "deny", "Spawn a subagent")] },
    });
    render(<ProfileEditor id="ollama-27b" />);
    await screen.findByText("Spawn a subagent");

    const agentStates = rowFor("Agent")
      .getAllByRole("button")
      .map((button) => button.textContent);
    expect(agentStates).toEqual(["default", "off"]);
    expect(rowFor("Bash").getByRole("button", { name: "allow" })).toBeTruthy();
  });

  it("shows the load error when the profile cannot be read", async () => {
    vi.spyOn(globalThis, "fetch").mockResolvedValue(jsonResponse({ message: "no tool catalog" }, 502));
    render(<ProfileEditor id="claude-code" />);

    expect(await screen.findByText("no tool catalog")).toBeTruthy();
  });
});
