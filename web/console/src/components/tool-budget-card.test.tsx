import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { ProfileSummary } from "@/lib/profiles";
import type { ToolBudgetReport } from "@/lib/tool-budget";
import { ToolBudgetCard } from "./tool-budget-card";

const REPORT: ToolBudgetReport = {
  since_days: 14,
  requests: 26,
  rows: [
    {
      tool: "WebFetch",
      schema_bytes: 2048,
      requests: 26,
      session_bytes: 53248,
      calls: 0,
      bytes_per_call: null,
    },
    {
      tool: "Bash",
      schema_bytes: 1500,
      requests: 26,
      session_bytes: 39000,
      calls: 4,
      bytes_per_call: 9750,
    },
  ],
  protected: ["Bash", "Read"],
  protected_source: "built-in list in bin/tool-budget",
  suggest: {
    drop: ["WebFetch", "mcp__repo__pr_view"],
    keep: ["Bash"],
    saves_bytes: 3072,
  },
};

const NOTHING_TO_DROP: ToolBudgetReport = {
  ...REPORT,
  suggest: { drop: [], keep: ["WebFetch", "Bash"], saves_bytes: 0 },
};

const PROFILES: ProfileSummary[] = [
  {
    id: "claude-code",
    title: "Claude Code",
    kind: "claude-code",
    model: null,
    context: null,
    overrides: 0,
    env: {},
  },
  {
    id: "ollama-27b",
    title: "Ollama 27b",
    kind: "ollama",
    model: "qwen3.8-27b-cc",
    context: 65536,
    overrides: 1,
    env: {},
  },
];

const DETAIL = {
  id: "ollama-27b",
  override: { context: 32768 },
  base: { tools: [{ name: "Bash" }, { name: "WebFetch" }] },
};

const jsonResponse = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status });

function stubApi(
  report: ToolBudgetReport,
  putStatus = 200,
  putBody: unknown = { override: {} },
) {
  const puts: { url: string; body: unknown }[] = [];
  vi.spyOn(globalThis, "fetch").mockImplementation(async (input, init) => {
    const url = String(input);
    if (url === "/api/tool-budget") {
      return jsonResponse(report);
    }
    if (url === "/api/profiles") {
      return jsonResponse({ profiles: PROFILES });
    }
    if (url === "/api/profiles/ollama-27b" && init?.method === "PUT") {
      puts.push({ url, body: JSON.parse(String(init.body)) });
      return jsonResponse(putBody, putStatus);
    }
    if (url === "/api/profiles/ollama-27b") {
      return jsonResponse(DETAIL);
    }
    return jsonResponse({ message: `unexpected ${url}` }, 500);
  });
  return puts;
}

const applyButton = () =>
  screen.getByRole("button", {
    name: "Apply suggestion to Ollama 27b",
  }) as HTMLButtonElement;

function useCleanMocks() {
  beforeEach(() => {
    vi.restoreAllMocks();
  });
  afterEach(() => {
    cleanup();
  });
}

describe("ToolBudgetCard shows", () => {
  useCleanMocks();

  it("one row per tool with its bytes, calls and cost, plus the suggestion", async () => {
    stubApi(REPORT);
    render(<ToolBudgetCard />);

    expect(await screen.findByText("WebFetch")).toBeTruthy();
    expect(screen.getByText("never called")).toBeTruthy();
    expect(screen.getByText("9750 bytes per call")).toBeTruthy();
    expect(screen.getByText("Last 14 days, 26 requests")).toBeTruthy();
    expect(
      screen.getByText(
        "Drop WebFetch, mcp__repo__pr_view (saves 3.0 KiB per request)",
      ),
    ).toBeTruthy();
    expect(
      screen.getByText(
        "Protected (built-in list in bin/tool-budget): Bash, Read",
      ),
    ).toBeTruthy();
    const bar = document.querySelector(
      '[data-tool="WebFetch"] [data-share]',
    ) as HTMLElement;
    expect(bar.style.width).toBe("100%");
  });

  it("nothing to drop with the apply button off", async () => {
    stubApi(NOTHING_TO_DROP);
    render(<ToolBudgetCard />);

    expect(await screen.findByText("Nothing to drop")).toBeTruthy();
    expect(applyButton().disabled).toBe(true);
  });

  it("no apply button for the claude-code profile", async () => {
    stubApi(REPORT);
    render(<ToolBudgetCard />);

    await screen.findByText("WebFetch");
    expect(
      screen.queryByRole("button", { name: "Apply suggestion to Claude Code" }),
    ).toBeNull();
  });

  it("the load error", async () => {
    vi.spyOn(globalThis, "fetch").mockResolvedValue(
      jsonResponse({ message: "tool-budget: boom" }, 502),
    );
    render(<ToolBudgetCard />);

    expect(await screen.findByText("tool-budget: boom")).toBeTruthy();
  });
});

describe("ToolBudgetCard applies", () => {
  useCleanMocks();

  it("the suggestion to a profile after a confirm that lists the names", async () => {
    const puts = stubApi(REPORT);
    render(<ToolBudgetCard />);
    await screen.findByText("WebFetch");

    fireEvent.click(applyButton());
    expect(
      screen.getByText("Turn these tools off in Ollama 27b?"),
    ).toBeTruthy();
    expect(screen.getByText("mcp__repo__pr_view")).toBeTruthy();
    expect(puts).toEqual([]);

    fireEvent.click(screen.getByRole("button", { name: "Turn these off" }));

    expect(
      await screen.findByText(
        "Ollama 27b: turned off WebFetch; skipped mcp__repo__pr_view (not a profile tool)",
      ),
    ).toBeTruthy();
    expect(puts).toEqual([
      {
        url: "/api/profiles/ollama-27b",
        body: { context: 32768, tools: { WebFetch: "off" } },
      },
    ]);
  });

  it("nothing when the confirm is cancelled", async () => {
    const puts = stubApi(REPORT);
    render(<ToolBudgetCard />);
    await screen.findByText("WebFetch");

    fireEvent.click(applyButton());
    fireEvent.click(screen.getByRole("button", { name: "Cancel" }));

    expect(
      screen.queryByText("Turn these tools off in Ollama 27b?"),
    ).toBeNull();
    expect(puts).toEqual([]);
  });

  it("and shows the route's refusal", async () => {
    stubApi(REPORT, 409, { message: "profiles is a symlink" });
    render(<ToolBudgetCard />);
    await screen.findByText("WebFetch");

    fireEvent.click(applyButton());
    fireEvent.click(screen.getByRole("button", { name: "Turn these off" }));

    expect(await screen.findByText("profiles is a symlink")).toBeTruthy();
  });
});
