import {
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
} from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { HistoryEntry } from "@/lib/history";
import { HistoryView } from "./history-view";

const SETTINGS_ID = "20261026-093000-settings-beef";
const LAUNCH_ID = "20261026-094000-launch-agent-cafe";
const FIRST_ID = "20261026-092000-launch-agent-f00d";

const SETTINGS_ENTRY = {
  id: SETTINGS_ID,
  at: "2026-10-26T09:30:00Z",
  kind: "settings",
  path: "/home/owner/.claude/settings.json",
  source: "console",
  before: `${SETTINGS_ID}.before`,
  after: `${SETTINGS_ID}.after`,
};

const LAUNCH_ENTRY = {
  id: LAUNCH_ID,
  at: "2026-10-26T09:40:00Z",
  kind: "launch-agent",
  path: "/home/owner/Library/LaunchAgents/local.ollama.plist",
  source: "terminal",
  before: `${LAUNCH_ID}.before`,
  after: `${LAUNCH_ID}.after`,
};

const FIRST_ENTRY = {
  id: FIRST_ID,
  at: "2026-10-26T09:20:00Z",
  kind: "launch-agent",
  path: "/home/owner/Library/LaunchAgents/local.ollama.plist",
  source: "terminal",
  before: null,
  after: `${FIRST_ID}.after`,
};

const DETAILS: Record<
  string,
  { entry: HistoryEntry; before: string | null; after: string }
> = {
  [SETTINGS_ID]: {
    entry: SETTINGS_ENTRY,
    before: "{}\n",
    after: '{\n  "deny": ["WebFetch"]\n}\n',
  },
  [LAUNCH_ID]: {
    entry: LAUNCH_ENTRY,
    before: "<plist>old</plist>\n",
    after: "<plist>new</plist>\n",
  },
  [FIRST_ID]: {
    entry: FIRST_ENTRY,
    before: null,
    after: "<plist>first</plist>\n",
  },
};

const jsonResponse = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });

describe("HistoryView", () => {
  let posts: string[];

  beforeEach(() => {
    posts = [];
    vi.spyOn(globalThis, "fetch").mockImplementation(async (input, init) => {
      const url = String(input);
      if (init?.method === "POST") {
        posts.push(url);
        return jsonResponse({
          entry: {
            ...SETTINGS_ENTRY,
            id: "20261026-100000-settings-f00d",
            source: "console-restore",
          },
        });
      }
      if (url === "/api/history") {
        return jsonResponse({
          entries: [LAUNCH_ENTRY, SETTINGS_ENTRY, FIRST_ENTRY],
        });
      }
      return jsonResponse(DETAILS[url.split("/").pop() ?? ""]);
    });
  });

  afterEach(() => {
    cleanup();
    vi.restoreAllMocks();
  });

  it("shows the diff of the selected change", async () => {
    render(<HistoryView />);

    fireEvent.click(
      await screen.findByRole("button", { name: /settings.*console/ }),
    );

    expect(await screen.findByText('"deny": ["WebFetch"]')).toBeTruthy();
    expect(screen.getByText("{}")).toBeTruthy();
  });

  it("asks for confirmation before it posts a restore", async () => {
    render(<HistoryView />);
    fireEvent.click(
      await screen.findByRole("button", { name: /settings.*console/ }),
    );
    await screen.findByText('"deny": ["WebFetch"]');

    fireEvent.click(
      screen.getByRole("button", { name: "Restore this version" }),
    );

    expect(
      screen.getByText(/Restore \/home\/owner\/\.claude\/settings\.json/),
    ).toBeTruthy();
    expect(posts).toEqual([]);

    fireEvent.click(screen.getByRole("button", { name: "Confirm restore" }));

    await waitFor(() =>
      expect(posts).toEqual([`/api/history/${SETTINGS_ID}/restore`]),
    );
  });

  it("disables restore when the change had no earlier version", async () => {
    render(<HistoryView />);
    fireEvent.click(
      (await screen.findAllByRole("button", { name: /launch-agent/ }))[1],
    );
    await screen.findByText("<plist>first</plist>");

    const restore = screen.getByRole("button", {
      name: "Restore this version",
    });

    expect((restore as HTMLButtonElement).disabled).toBe(true);
  });

  it("tells a launch agent restore to reload Ollama from the Server page", async () => {
    render(<HistoryView />);
    fireEvent.click(
      (await screen.findAllByRole("button", { name: /launch-agent/ }))[0],
    );
    await screen.findByText("<plist>new</plist>");

    fireEvent.click(
      screen.getByRole("button", { name: "Restore this version" }),
    );

    expect(
      screen.getByText(/use Apply on the Server page to reload Ollama/),
    ).toBeTruthy();
  });
});
