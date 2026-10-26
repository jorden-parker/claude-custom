import { cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { FetchDomainsEditor } from "./fetch-domains-editor";

const SUGGESTED = ["docs.python.org", "pkg.go.dev", "go.dev", "developer.mozilla.org", "nodejs.org", "docs.rs"];

const stateWith = (hosts: string[], ignored: string[] = []) => ({
  path: "/home/me/.config/claude-custom/fetch-domains",
  hosts,
  ignored,
  suggested: SUGGESTED,
});

const jsonResponse = (body: unknown) => new Response(JSON.stringify(body), { status: 200 });

function stubApi(listed: string[]) {
  const saves: string[][] = [];
  vi.spyOn(globalThis, "fetch").mockImplementation(async (input, init) => {
    const url = String(input);
    if (url === "/api/history") {
      return jsonResponse({ entries: [] });
    }
    if (init?.method === "PUT") {
      const hosts = (JSON.parse(String(init.body)) as { hosts: string[] }).hosts;
      saves.push(hosts);
      return jsonResponse(stateWith(hosts));
    }
    return jsonResponse(stateWith(listed));
  });
  return saves;
}

describe("FetchDomainsEditor", () => {
  beforeEach(() => {
    vi.restoreAllMocks();
  });

  afterEach(() => {
    cleanup();
  });

  it("saves the on hosts in row order when a suggested host is switched on", async () => {
    const saves = stubApi(["go.dev"]);
    render(<FetchDomainsEditor />);

    fireEvent.click(await screen.findByRole("switch", { name: "docs.python.org" }));
    fireEvent.click(screen.getByRole("button", { name: "Save" }));

    await waitFor(() => expect(saves).toEqual([["go.dev", "docs.python.org"]]));
    expect(await screen.findByText("saved; applies to the next claude-ollama launch")).toBeTruthy();
  });

  it("shows the not-a-hostname message while typing an invalid host", async () => {
    stubApi([]);
    render(<FetchDomainsEditor />);

    fireEvent.change(await screen.findByLabelText("Add host"), { target: { value: "localhost" } });

    expect(screen.getByText("not a hostname (expected something like docs.python.org)")).toBeTruthy();
  });

  it("turns on a suggested host when it is added by typing it", async () => {
    const saves = stubApi([]);
    render(<FetchDomainsEditor />);

    fireEvent.change(await screen.findByLabelText("Add host"), { target: { value: "  NODEJS.org " } });
    fireEvent.click(screen.getByRole("button", { name: "Add" }));
    fireEvent.click(screen.getByRole("button", { name: "Save" }));

    await waitFor(() => expect(saves).toEqual([["nodejs.org"]]));
  });

  it("shows ignored lines from the file", async () => {
    vi.spyOn(globalThis, "fetch").mockImplementation(async (input) =>
      String(input) === "/api/history"
        ? jsonResponse({ entries: [] })
        : jsonResponse(stateWith(["go.dev"], ["localhost"])),
    );
    render(<FetchDomainsEditor />);

    expect(await screen.findByText("localhost")).toBeTruthy();
    expect(screen.getByText(/ignored/i)).toBeTruthy();
  });
});
