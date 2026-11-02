import {
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
} from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { WorkspaceList } from "./workspace-list";

type Workspace = {
  path: string;
  trusted: boolean;
  exists: boolean;
  skills: {
    name: string;
    description: string | null;
    modelInvocable: boolean;
  }[];
};

const STATE_PATH = "/home/me/.claude-ollama/.claude.json";

const jsonResponse = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status });

function stubApi(workspaces: Workspace[]) {
  const saves: { path: string; trusted: boolean }[] = [];
  vi.spyOn(globalThis, "fetch").mockImplementation(async (_input, init) => {
    if (init?.method === "PUT") {
      const save = JSON.parse(String(init.body)) as {
        path: string;
        trusted: boolean;
      };
      saves.push(save);
      if (!save.path.startsWith("/real")) {
        return jsonResponse(
          { message: `${save.path} is not a folder on this machine` },
          400,
        );
      }
      const next = workspaces.map((workspace) =>
        workspace.path === save.path
          ? { ...workspace, trusted: save.trusted }
          : workspace,
      );
      return jsonResponse({ path: STATE_PATH, workspaces: next });
    }
    return jsonResponse({ path: STATE_PATH, workspaces });
  });
  return saves;
}

describe("WorkspaceList", () => {
  beforeEach(() => {
    vi.restoreAllMocks();
  });

  afterEach(() => {
    cleanup();
  });

  it("shows each folder with its trust state and project skills", async () => {
    stubApi([
      {
        path: "/real/app",
        trusted: true,
        exists: true,
        skills: [
          { name: "deploy", description: "ship it", modelInvocable: true },
          { name: "notes", description: null, modelInvocable: false },
        ],
      },
      { path: "/real/empty", trusted: false, exists: true, skills: [] },
      { path: "/gone", trusted: true, exists: false, skills: [] },
    ]);
    render(<WorkspaceList />);

    expect(await screen.findByText("trusted")).toBeTruthy();
    expect(screen.getByText("/deploy")).toBeTruthy();
    expect(screen.getByText("/notes (user only)")).toBeTruthy();
    expect(screen.getByText("untrusted")).toBeTruthy();
    expect(
      screen.getByText("No project skills under .claude/skills"),
    ).toBeTruthy();
    expect(screen.getByText("folder missing")).toBeTruthy();
  });

  it("saves a toggle straight away", async () => {
    const saves = stubApi([
      { path: "/real/app", trusted: false, exists: true, skills: [] },
    ]);
    render(<WorkspaceList />);

    fireEvent.click(await screen.findByRole("switch", { name: "/real/app" }));

    await waitFor(() =>
      expect(saves).toEqual([{ path: "/real/app", trusted: true }]),
    );
    expect(
      await screen.findByText(
        "saved; applies to the next claude-ollama launch in that folder",
      ),
    ).toBeTruthy();
    expect(screen.getByText("trusted")).toBeTruthy();
  });

  it("trusts a typed folder and shows the server's refusal", async () => {
    const saves = stubApi([]);
    render(<WorkspaceList />);

    expect(
      await screen.findByText(
        "No folders yet. Launch claude-ollama in a project, or trust one above.",
      ),
    ).toBeTruthy();
    fireEvent.change(screen.getByLabelText("Trust a folder"), {
      target: { value: " /nowhere " },
    });
    fireEvent.click(screen.getByRole("button", { name: "Trust" }));

    await waitFor(() =>
      expect(saves).toEqual([{ path: "/nowhere", trusted: true }]),
    );
    expect(
      await screen.findByText("/nowhere is not a folder on this machine"),
    ).toBeTruthy();
  });

  it("refuses a relative path before sending it", async () => {
    stubApi([]);
    render(<WorkspaceList />);

    fireEvent.change(await screen.findByLabelText("Trust a folder"), {
      target: { value: "src/app" },
    });

    expect(
      screen.getByText("expected an absolute path (starting with /)"),
    ).toBeTruthy();
    expect(
      (screen.getByRole("button", { name: "Trust" }) as HTMLButtonElement)
        .disabled,
    ).toBe(true);
  });
});
