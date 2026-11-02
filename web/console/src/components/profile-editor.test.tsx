import {
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
  within,
} from "@testing-library/react";
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
    tools: [
      TOOL("Bash", "default", "Run shell commands"),
      TOOL("WebFetch", "allow", "Fetch a web page"),
    ],
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
    outputTokens: 8192,
    parameters: { temperature: 0.7 },
    mcpServers: ["code-search", "repo", "dev"],
  },
};

const jsonResponse = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });

const rowFor = (name: string) =>
  within(screen.getByRole("row", { name: new RegExp(`^${name}\\b`) }));

function mockProfileApi(
  detail: unknown,
  saveResponse: () => Response = () => jsonResponse({ override: {} }),
) {
  const fetchMock = vi
    .spyOn(globalThis, "fetch")
    .mockImplementation(async (_input, init) => {
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
    const fetchMock = mockProfileApi(CLAUDE_CODE_DETAIL, () =>
      jsonResponse({ override: { tools: { WebFetch: "deny" } } }),
    );
    render(<ProfileEditor id="claude-code" />);

    expect(await screen.findByText("Fetch a web page")).toBeTruthy();
    expect(
      rowFor("WebFetch").getByRole("cell", { name: "allow" }),
    ).toBeTruthy();
    expect(
      screen.getByRole("button", { name: "Save" }).hasAttribute("disabled"),
    ).toBe(true);

    fireEvent.click(rowFor("WebFetch").getByRole("button", { name: "deny" }));
    expect(screen.getByText("Unsaved changes")).toBeTruthy();

    fireEvent.click(screen.getByRole("button", { name: "Save" }));
    await waitFor(() =>
      expect(fetchMock).toHaveBeenCalledWith(
        "/api/profiles/claude-code",
        expect.objectContaining({
          method: "PUT",
          body: JSON.stringify({ tools: { WebFetch: "deny" } }),
        }),
      ),
    );
    expect(
      await screen.findByText("saved; applies to the next session"),
    ).toBeTruthy();
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
    mockProfileApi(CLAUDE_CODE_DETAIL, () =>
      jsonResponse({ message: "unknown tool Nope" }, 400),
    );
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

    expect(
      await screen.findByRole("switch", { name: "Sandbox enabled" }),
    ).toBeTruthy();
  });

  it("shows context and parameter fields for an Ollama profile, with the base as placeholders", async () => {
    mockProfileApi(OLLAMA_DETAIL);
    render(<ProfileEditor id="ollama-27b" />);
    await screen.findByText("Fetch a web page");

    fireEvent.click(screen.getByRole("tab", { name: "Sandbox & model" }));

    expect(
      await screen.findByRole("spinbutton", { name: "Context tokens" }),
    ).toBeTruthy();
    const outputTokens = screen.getByRole("spinbutton", {
      name: "Output tokens per reply",
    });
    expect(outputTokens.getAttribute("placeholder")).toBe("8192");
    expect(outputTokens.getAttribute("min")).toBe("1024");
    expect(outputTokens.getAttribute("max")).toBe("16384");
    expect(outputTokens.getAttribute("step")).toBe("1024");
    expect(
      screen.getByText(/decode is the slow path on a laptop/),
    ).toBeTruthy();
    expect(
      screen
        .getByRole("spinbutton", { name: "temperature" })
        .getAttribute("placeholder"),
    ).toBe("0.7");
    expect(
      screen.getByText("Sandbox is always on for Ollama profiles."),
    ).toBeTruthy();
  });

  it("offers a thinking switch for an Ollama profile that is off by default", async () => {
    mockProfileApi(OLLAMA_DETAIL);
    render(<ProfileEditor id="ollama-27b" />);
    await screen.findByText("Fetch a web page");

    fireEvent.click(screen.getByRole("tab", { name: "Sandbox & model" }));

    const thinking = (await screen.findByRole("switch", {
      name: "Thinking enabled",
    })) as HTMLInputElement;
    expect(thinking.checked).toBe(false);
    fireEvent.click(thinking);
    expect(screen.getByText("Unsaved changes")).toBeTruthy();
  });

  it("labels the env switches with their defaults and hides the handoff fields from claude-code", async () => {
    mockProfileApi(CLAUDE_CODE_DETAIL);
    render(<ProfileEditor id="claude-code" />);
    await screen.findByText("Fetch a web page");

    fireEvent.click(screen.getByRole("tab", { name: "Env" }));

    const telemetry = (await screen.findByRole("combobox", {
      name: "Session telemetry",
    })) as HTMLSelectElement;
    expect(telemetry.options[telemetry.selectedIndex].text).toBe(
      "default (on)",
    );
    expect(screen.queryByText("CLAUDE_OLLAMA_TELEMETRY")).toBeNull();
    expect(
      screen.queryByRole("combobox", {
        name: "Hand off before the context fills",
      }),
    ).toBeNull();
    expect(
      screen.queryByRole("spinbutton", { name: "Hand off at (% of context)" }),
    ).toBeNull();
  });

  it("shows claude-code only the friction guard of the harness switches, under its heading", async () => {
    mockProfileApi(CLAUDE_CODE_DETAIL);
    render(<ProfileEditor id="claude-code" />);
    await screen.findByText("Fetch a web page");

    fireEvent.click(screen.getByRole("tab", { name: "Env" }));

    await screen.findByRole("combobox", {
      name: "Reset a looping guard after three identical denials",
    });
    expect(screen.getByRole("heading", { name: "Guards" })).toBeTruthy();
    expect(
      screen.queryByRole("heading", { name: "Ollama residency" }),
    ).toBeNull();
    for (const label of [
      "Observe prompt drift through the messages proxy",
      "Hold an Ollama residency lease and heartbeat",
      "Degrade rung by rung on incident evidence",
      "Write a machine beacon at launch",
    ]) {
      expect(screen.queryByRole("combobox", { name: label })).toBeNull();
    }
    expect(
      screen.queryByRole("spinbutton", {
        name: "Seconds between keep-alive heartbeats",
      }),
    ).toBeNull();
  });

  it("groups the Ollama env fields under the settings headings in order", async () => {
    mockProfileApi(OLLAMA_DETAIL);
    render(<ProfileEditor id="ollama-27b" />);
    await screen.findByText("Fetch a web page");

    fireEvent.click(screen.getByRole("tab", { name: "Env" }));

    const lease = (await screen.findByRole("combobox", {
      name: "Hold an Ollama residency lease and heartbeat",
    })) as HTMLSelectElement;
    expect(lease.options[lease.selectedIndex].text).toBe("default (on)");
    const headings = screen
      .getAllByRole("heading", { level: 2 })
      .map((heading) => heading.textContent);
    expect(headings).toEqual([
      "Prompt and context",
      "Guards",
      "Ollama residency",
      "Diagnostics",
      "Browser",
    ]);
    const residency = screen
      .getByRole("heading", { name: "Ollama residency" })
      .closest("section");
    expect(residency).not.toBeNull();
    expect(
      within(residency as HTMLElement)
        .getAllByRole("combobox")
        .map((box) => box.getAttribute("aria-label")),
    ).toEqual([
      "Hold an Ollama residency lease and heartbeat",
      "Check memory fit before launch",
    ]);
    const heartbeat = within(residency as HTMLElement).getByRole("spinbutton", {
      name: "Seconds between keep-alive heartbeats",
    });
    expect(heartbeat.getAttribute("placeholder")).toBe("120");
    expect(heartbeat.getAttribute("min")).toBe("30");
    expect(heartbeat.getAttribute("max")).toBe("600");
    expect(screen.getByText(/so a cache miss has a cause/)).toBeTruthy();
    const record = (await screen.findByRole("combobox", {
      name: "Record every request body for replay benches",
    })) as HTMLSelectElement;
    expect(record.options[record.selectedIndex].text).toBe("default (off)");
  });

  it("saves the handoff percent as a string and removes the key when cleared", async () => {
    const fetchMock = mockProfileApi(OLLAMA_DETAIL, () =>
      jsonResponse({ override: { env: { CLAUDE_OLLAMA_HANDOFF_PCT: "60" } } }),
    );
    render(<ProfileEditor id="ollama-27b" />);
    await screen.findByText("Fetch a web page");

    fireEvent.click(screen.getByRole("tab", { name: "Env" }));
    const percent = (await screen.findByRole("spinbutton", {
      name: "Hand off at (% of context)",
    })) as HTMLInputElement;
    expect(percent.getAttribute("placeholder")).toBe("70");

    fireEvent.change(percent, { target: { value: "60" } });
    fireEvent.click(screen.getByRole("button", { name: "Save" }));
    await waitFor(() =>
      expect(fetchMock).toHaveBeenCalledWith(
        "/api/profiles/ollama-27b",
        expect.objectContaining({
          method: "PUT",
          body: JSON.stringify({ env: { CLAUDE_OLLAMA_HANDOFF_PCT: "60" } }),
        }),
      ),
    );

    fireEvent.change(percent, { target: { value: "" } });
    expect(screen.getByText("Unsaved changes")).toBeTruthy();
    fireEvent.click(screen.getByRole("button", { name: "Save" }));
    await waitFor(() =>
      expect(fetchMock).toHaveBeenCalledWith(
        "/api/profiles/ollama-27b",
        expect.objectContaining({ method: "PUT", body: JSON.stringify({}) }),
      ),
    );
  });

  it("saves the relaunch switch as 0 when turned off", async () => {
    const fetchMock = mockProfileApi(OLLAMA_DETAIL);
    render(<ProfileEditor id="ollama-27b" />);
    await screen.findByText("Fetch a web page");

    fireEvent.click(screen.getByRole("tab", { name: "Env" }));
    const relaunch = await screen.findByRole("combobox", {
      name: "Hand off before the context fills",
    });
    expect(screen.getByText(/a fresh session resumes it/)).toBeTruthy();

    fireEvent.change(relaunch, { target: { value: "0" } });
    fireEvent.click(screen.getByRole("button", { name: "Save" }));
    await waitFor(() =>
      expect(fetchMock).toHaveBeenCalledWith(
        "/api/profiles/ollama-27b",
        expect.objectContaining({
          method: "PUT",
          body: JSON.stringify({ env: { CLAUDE_OLLAMA_RELAUNCH: "0" } }),
        }),
      ),
    );
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
      base: {
        ...OLLAMA_DETAIL.base,
        tools: [
          ...OLLAMA_DETAIL.base.tools,
          TOOL("Agent", "deny", "Spawn a subagent"),
        ],
      },
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
    vi.spyOn(globalThis, "fetch").mockResolvedValue(
      jsonResponse({ message: "no tool catalog" }, 502),
    );
    render(<ProfileEditor id="claude-code" />);

    expect(await screen.findByText("no tool catalog")).toBeTruthy();
  });
});
