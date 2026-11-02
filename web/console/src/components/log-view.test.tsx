import {
  act,
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
      if (source === "launcher") {
        return launcherLog();
      }
      if (source === "incidents") {
        return Response.json({ path: "/state/incidents/s1.jsonl" });
      }
      if (source === "proxy") {
        return Response.json({ path: "/state/proxy/requests.jsonl" });
      }
      return Response.json({ path: "/var/log/ollama.log" });
    });
  });

  function receive(source: FakeEventSource, data: string) {
    source.onmessage?.({ data } as MessageEvent);
  }

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

  it("shows the incidents with a count per cause", async () => {
    render(<LogView />);
    await screen.findByText("following /var/log/ollama.log");
    fireEvent.click(screen.getByRole("tab", { name: "Incidents" }));
    expect(
      await screen.findByText("following /state/incidents/s1.jsonl"),
    ).toBeTruthy();
    const source = FakeEventSource.opened.at(-1)!;
    expect(source.url).toBe("/api/logs/events?source=incidents");
    const frame = (text: string) => JSON.stringify({ text, level: null });
    act(() => {
      receive(
        source,
        frame(
          '{"ts": "2026-11-02T14:01:30.100Z", "cause": "aborted", "detail": "error=\\"context canceled\\"", "tokens": null}',
        ),
      );
      receive(
        source,
        frame(
          '{"ts": "2026-11-02T14:02:40.000Z", "cause": "reprefilled", "detail": "prompt eval time = 9800.00 ms / 61234 tokens", "tokens": 61234}',
        ),
      );
      receive(
        source,
        frame(
          '{"ts": "2026-11-02T14:03:00.000Z", "cause": "aborted", "detail": "error=\\"context canceled\\"", "tokens": null}',
        ),
      );
    });
    const counts = screen.getByLabelText("incident counts");
    expect(counts.textContent).toBe(
      "aborted 2evicted 0truncated 0reprefilled 1compacted 0relaunched 0unknown 0",
    );
    expect(
      screen.getByText(/reprefilled prompt eval time .* \(61k tokens\)$/),
    ).toBeTruthy();
    expect(screen.getByLabelText("classifier health").textContent).toBe(
      "no health row yet",
    );
    act(() => {
      receive(
        source,
        frame(
          '{"ts": "2026-11-02T14:04:03.000Z", "cause": "reprefilled", "detail": "prompt eval time = 52000.00 ms / 65450 tokens", "tokens": 65450, "rule": "reprefilled/prompt-eval", "preceded_by": {"kind": "embed", "ts": "2026-11-02T14:04:02Z"}}',
        ),
      );
      receive(
        source,
        frame(
          '{"ts": "2026-11-02T14:05:00Z", "kind": "health", "rules": {"reprefilled/prompt-eval": 1}, "unmatched": 1, "lines": 36}',
        ),
      );
    });
    expect(
      screen.getByText(
        /reprefilled · after embed · reprefilled\/prompt-eval prompt eval time/,
      ),
    ).toBeTruthy();
    expect(screen.getByLabelText("classifier health").textContent).toBe(
      "saw 36 lines, 1 unmatched",
    );
    expect(counts.textContent).toBe(
      "aborted 2evicted 0truncated 0reprefilled 2compacted 0relaunched 0unknown 0",
    );
  });

  it("shows the proxy requests with the prefix hit rate and the ledger", async () => {
    render(<LogView />);
    await screen.findByText("following /var/log/ollama.log");
    fireEvent.click(screen.getByRole("tab", { name: "Proxy" }));
    expect(
      await screen.findByText("following /state/proxy/requests.jsonl"),
    ).toBeTruthy();
    const source = FakeEventSource.opened.at(-1)!;
    expect(source.url).toBe("/api/logs/events?source=proxy");
    const frame = (text: string) => JSON.stringify({ text, level: null });
    act(() => {
      receive(
        source,
        frame(
          '{"ts":"2026-11-02T14:02:00.000Z","request_id":"r0","sections":5,"stable_sections":0,"diverged_at":null,"offset":null,"diff":null,"prompt_bytes":3900,"ledger":{"system":900,"tools":{"read_file":300,"bash":1200},"messages":2600}}',
        ),
      );
      receive(
        source,
        frame(
          '{"ts":"2026-11-02T14:03:00.000Z","request_id":"r1","sections":5,"stable_sections":4,"diverged_at":"message:4","offset":0,"diff":"next","prompt_bytes":4000,"ledger":{"system":900,"tools":{"read_file":300,"bash":1300},"messages":2700}}',
        ),
      );
      receive(
        source,
        frame(
          '{"ts":"2026-11-02T14:04:00.000Z","request_id":"r2","sections":5,"stable_sections":0,"diverged_at":"system","offset":41,"diff":"Monday 2026-11-02.","prompt_bytes":4100,"ledger":{"system":900,"tools":{"read_file":300,"bash":1300},"messages":2800}}',
        ),
      );
    });
    expect(screen.getByLabelText("prefix hit rate").textContent).toBe(
      "50% of 2 requests stable through tools",
    );
    expect(screen.getByLabelText("average prompt bytes").textContent).toBe(
      "4000 bytes per prompt",
    );
    expect(screen.getByLabelText("diverging sections").textContent).toBe(
      "system 1message:4 1",
    );
    expect(screen.getByText(/system · 41 · Monday 2026-11-02\.$/)).toBeTruthy();
    const ledger = screen.getByLabelText("tool schema ledger");
    const names = Array.from(ledger.querySelectorAll("[data-tool]")).map(
      (row) =>
        `${row.getAttribute("data-tool")}=${row.getAttribute("data-bytes")}`,
    );
    expect(names).toEqual(["bash=1300", "read_file=300"]);
    expect(ledger.textContent).toContain("system 900");
    expect(ledger.textContent).toContain("messages 2800");
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
