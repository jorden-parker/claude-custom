import {
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
  within,
} from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { MachinePolicyEditor } from "./machine-policy-editor";

const DIR = "/home/me/.config/claude-custom";

const MACHINE = {
  dir: DIR,
  files: {
    "gh-repos": {
      path: `${DIR}/gh-repos`,
      text: "acme/web\n",
      valid: ["acme/web"],
      invalid: [],
    },
    "command-rules": {
      path: `${DIR}/command-rules`,
      text: null,
      valid: [],
      invalid: [],
    },
    "enabled-tools": {
      path: `${DIR}/enabled-tools`,
      text: "Artifact\n",
      valid: ["Artifact"],
      invalid: [],
    },
    "fetch-domains": {
      path: `${DIR}/fetch-domains`,
      count: 3,
      editor: "/fetch-domains",
    },
  },
  sandboxOff: { exists: false, path: `${DIR}/sandbox-off` },
  knownTools: ["Artifact", "Workflow"],
};

const jsonResponse = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status });

function historyEntry(id: string, kind: string) {
  return { id, at: "2026-10-30T09:00:00.000Z", kind, source: "console" };
}

function stubApi(machine: unknown = MACHINE, entries: unknown[] = []) {
  const saves: unknown[] = [];
  const restores: string[] = [];
  vi.spyOn(globalThis, "fetch").mockImplementation(async (input, init) => {
    const url = String(input);
    if (url === "/api/history" && init?.method === undefined) {
      return jsonResponse({ entries });
    }
    if (url.startsWith("/api/history/") && init?.method === "POST") {
      restores.push(url);
      return jsonResponse({ entry: null });
    }
    if (init?.method === "PUT") {
      saves.push(JSON.parse(String(init.body)));
      return jsonResponse(machine);
    }
    return jsonResponse(machine);
  });
  return { saves, restores };
}

describe("MachinePolicyEditor", () => {
  beforeEach(() => {
    vi.restoreAllMocks();
  });

  afterEach(() => {
    cleanup();
  });

  it("renders a card for each of the five files, with the sandbox-off commands", async () => {
    stubApi();
    render(<MachinePolicyEditor />);

    expect(
      await screen.findByRole("region", { name: "gh-repos" }),
    ).toBeTruthy();
    expect(screen.getByRole("region", { name: "command-rules" })).toBeTruthy();
    expect(screen.getByRole("region", { name: "enabled-tools" })).toBeTruthy();
    expect(
      within(screen.getByRole("region", { name: "fetch-domains" })).getByText(
        "3 hosts listed. Edited on its own page.",
      ),
    ).toBeTruthy();
    expect(
      screen
        .getByRole("link", { name: "Edit fetch domains" })
        .getAttribute("href"),
    ).toBe("/fetch-domains");
    const sandbox = screen.getByRole("region", { name: "sandbox-off" });
    expect(within(sandbox).getByText("off")).toBeTruthy();
    expect(
      within(sandbox).getByText(
        /touch \/home\/me\/.config\/claude-custom\/sandbox-off/,
      ),
    ).toBeTruthy();
  });

  it("shows an invalid line with the reason the launcher would give", async () => {
    stubApi({
      ...MACHINE,
      files: {
        ...MACHINE.files,
        "gh-repos": {
          ...MACHINE.files["gh-repos"],
          text: "acme\n",
          valid: [],
          invalid: [{ line: "acme", reason: "expected owner/name or owner/*" }],
        },
      },
    });
    render(<MachinePolicyEditor />);

    const card = await screen.findByRole("region", { name: "gh-repos" });
    expect(
      within(card).getByText("expected owner/name or owner/*"),
    ).toBeTruthy();
    expect(within(card).getByText("acme", { selector: "code" })).toBeTruthy();
  });

  it("saves the lines of the textarea with PUT when Save is clicked", async () => {
    const { saves } = stubApi();
    render(<MachinePolicyEditor />);

    const card = await screen.findByRole("region", { name: "gh-repos" });
    fireEvent.change(within(card).getByLabelText("Lines for gh-repos"), {
      target: { value: "acme/web\nacme/*" },
    });
    fireEvent.click(within(card).getByRole("button", { name: "Save" }));

    await waitFor(() =>
      expect(saves).toEqual([
        { file: "gh-repos", lines: ["acme/web", "acme/*"] },
      ]),
    );
    expect(
      await screen.findByText(
        "saved; applies to the next claude-ollama launch",
      ),
    ).toBeTruthy();
  });

  it("shows the server's message when a save is refused", async () => {
    vi.spyOn(globalThis, "fetch").mockImplementation(async (input, init) => {
      if (init?.method === "PUT") {
        return jsonResponse(
          { message: "owner: expected owner/name or owner/*" },
          400,
        );
      }
      if (String(input) === "/api/history") {
        return jsonResponse({ entries: [] });
      }
      return jsonResponse(MACHINE);
    });
    render(<MachinePolicyEditor />);

    const card = await screen.findByRole("region", { name: "gh-repos" });
    fireEvent.change(within(card).getByLabelText("Lines for gh-repos"), {
      target: { value: "owner" },
    });
    fireEvent.click(within(card).getByRole("button", { name: "Save" }));

    expect(
      await screen.findByText("owner: expected owner/name or owner/*"),
    ).toBeTruthy();
  });

  it("lists only the history of its own file, each with a restore button that posts to the restore route", async () => {
    const { restores } = stubApi(MACHINE, [
      historyEntry("20261030-090000-machine-gh-repos-aaaa", "machine-gh-repos"),
      historyEntry("20261030-090100-fetch-domains-bbbb", "fetch-domains"),
    ]);
    render(<MachinePolicyEditor />);

    const card = await screen.findByRole("region", { name: "gh-repos" });
    const restoreButtons = await within(card).findAllByRole("button", {
      name: "Restore before this save",
    });
    expect(restoreButtons).toHaveLength(1);
    fireEvent.click(restoreButtons[0]);

    await waitFor(() =>
      expect(restores).toEqual([
        "/api/history/20261030-090000-machine-gh-repos-aaaa/restore",
      ]),
    );
  });
});
