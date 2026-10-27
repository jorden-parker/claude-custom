import {
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
} from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { LogView } from "./log-view";

class FakeEventSource {
  static opened: FakeEventSource[] = [];
  onmessage: ((message: MessageEvent) => void) | null = null;
  closed = false;

  constructor(readonly url: string) {
    FakeEventSource.opened.push(this);
  }

  close() {
    this.closed = true;
  }
}

describe("LogView", () => {
  let fetched: string[];
  let launcherLog: () => Response;

  beforeEach(() => {
    fetched = [];
    launcherLog = () => Response.json({ path: "/state/launcher.log" });
    FakeEventSource.opened = [];
    vi.stubGlobal("EventSource", FakeEventSource);
    vi.spyOn(globalThis, "fetch").mockImplementation(async (input) => {
      const url = String(input);
      fetched.push(url);
      const source = new URL(url, "http://127.0.0.1").searchParams.get(
        "source",
      );
      return source === "launcher"
        ? launcherLog()
        : Response.json({ path: "/var/log/ollama.log" });
    });
  });

  afterEach(() => {
    cleanup();
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
  });

  it("follows the Ollama server log first", async () => {
    render(<LogView />);
    expect(
      await screen.findByText("following /var/log/ollama.log"),
    ).toBeTruthy();
    expect(fetched).toEqual(["/api/logs/path?source=server"]);
    expect(FakeEventSource.opened.map((source) => source.url)).toEqual([
      "/api/logs/events?source=server",
    ]);
  });

  it("switches to the launcher log and stops the server stream", async () => {
    render(<LogView />);
    await screen.findByText("following /var/log/ollama.log");
    fireEvent.click(screen.getByRole("tab", { name: "Launcher" }));
    expect(
      await screen.findByText("following /state/launcher.log"),
    ).toBeTruthy();
    expect(FakeEventSource.opened[0].closed).toBe(true);
    expect(FakeEventSource.opened.at(-1)?.url).toBe(
      "/api/logs/events?source=launcher",
    );
  });

  it("shows why the launcher log is missing", async () => {
    launcherLog = () => new Response("No launcher log yet", { status: 404 });
    render(<LogView />);
    await screen.findByText("following /var/log/ollama.log");
    fireEvent.click(screen.getByRole("tab", { name: "Launcher" }));
    await waitFor(() =>
      expect(screen.getByText("No launcher log yet")).toBeTruthy(),
    );
  });
});
