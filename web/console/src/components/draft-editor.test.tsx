import {
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
} from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { Draft } from "@/lib/draft-schema";
import { DraftEditor } from "./draft-editor";

vi.mock("next/navigation", () => ({ useRouter: () => ({ push: vi.fn() }) }));

const PR_ID = "20260101-120000-pr-add-drafts";
const REVIEW_ID = "20260101-120000-review-pr-12";
const CREATED = "2026-01-01T12:00:00.000Z";
const PR_URL = "https://github.com/jorden/claude-custom/pull/9";

const prDraft = (overrides: Partial<Draft> = {}): Draft =>
  ({
    kind: "pr",
    id: PR_ID,
    project: "/work/tree",
    base: "main",
    head: "feature-x",
    title: "Add drafts",
    sections: [{ heading: "Summary", body: "Adds drafts." }],
    created: CREATED,
    ...overrides,
  }) as Draft;

const reviewDraft = (): Draft => ({
  kind: "review",
  id: REVIEW_ID,
  project: "/work/tree",
  pr: 12,
  event: "COMMENT",
  summary: "Looks good.",
  comments: [{ label: "praise", decorations: [], body: "Nice split." }],
  created: CREATED,
});

const jsonResponse = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });

type Call = { url: string; method: string; body: unknown };

function stubApi(
  initial: { draft: Draft; repo: string | null },
  replies: { save?: Response; post?: Response } = {},
) {
  const calls: Call[] = [];
  vi.spyOn(globalThis, "fetch").mockImplementation(async (input, init) => {
    const url = String(input);
    const method = init?.method ?? "GET";
    const body = init?.body ? JSON.parse(String(init.body)) : undefined;
    calls.push({ url, method, body });
    if (method === "PUT") {
      return (
        replies.save ??
        jsonResponse({
          draft: { ...initial.draft, ...body },
          hash: "saved-hash",
          repo: initial.repo,
        })
      );
    }
    if (method === "POST") {
      return (
        replies.post ??
        jsonResponse({
          draft: { ...initial.draft, posted: { url: PR_URL, at: CREATED } },
          hash: "posted-hash",
          repo: initial.repo,
        })
      );
    }
    return jsonResponse({
      draft: initial.draft,
      hash: "first-hash",
      repo: initial.repo,
    });
  });
  return calls;
}

describe("DraftEditor", () => {
  beforeEach(() => {
    vi.restoreAllMocks();
  });

  afterEach(() => {
    cleanup();
  });

  it("shows the repo the PR would be created in, with Save and Create PR disabled until a change", async () => {
    stubApi({ draft: prDraft(), repo: "jorden/claude-custom" });
    render(<DraftEditor id={PR_ID} />);

    expect(await screen.findByDisplayValue("Add drafts")).toBeTruthy();
    expect(screen.getByText("jorden/claude-custom")).toBeTruthy();
    expect(
      screen.getByRole("button", { name: "Save" }).hasAttribute("disabled"),
    ).toBe(true);
    expect(
      screen
        .getByRole("button", { name: "Create PR on GitHub" })
        .hasAttribute("disabled"),
    ).toBe(false);
  });

  it("disables Create PR while there are unsaved changes, then saves and enables it", async () => {
    const calls = stubApi({ draft: prDraft(), repo: "jorden/claude-custom" });
    render(<DraftEditor id={PR_ID} />);
    fireEvent.change(await screen.findByLabelText("Title"), {
      target: { value: "Renamed" },
    });

    expect(screen.getByText("Unsaved changes")).toBeTruthy();
    expect(
      screen
        .getByRole("button", { name: "Create PR on GitHub" })
        .hasAttribute("disabled"),
    ).toBe(true);

    fireEvent.click(screen.getByRole("button", { name: "Save" }));

    expect(await screen.findByText("saved")).toBeTruthy();
    expect(calls.find((call) => call.method === "PUT")).toMatchObject({
      url: `/api/drafts/${PR_ID}`,
      body: {
        hash: "first-hash",
        title: "Renamed",
        sections: [{ heading: "Summary", body: "Adds drafts." }],
      },
    });
    expect(
      screen
        .getByRole("button", { name: "Create PR on GitHub" })
        .hasAttribute("disabled"),
    ).toBe(false);
  });

  it("posts the saved draft with its hash and shows the posted link", async () => {
    const calls = stubApi({ draft: prDraft(), repo: "jorden/claude-custom" });
    render(<DraftEditor id={PR_ID} />);
    fireEvent.click(await screen.findByRole("checkbox", { name: "Draft PR" }));

    fireEvent.click(
      screen.getByRole("button", { name: "Create PR on GitHub" }),
    );

    expect(
      await screen.findByRole("link", { name: "View posted on GitHub" }),
    ).toBeTruthy();
    expect(calls.find((call) => call.method === "POST")).toMatchObject({
      url: `/api/drafts/${PR_ID}/post`,
      body: { hash: "first-hash", draft: true },
    });
    expect(
      screen
        .getByRole("button", { name: "Create PR on GitHub" })
        .hasAttribute("disabled"),
    ).toBe(true);
  });

  it("shows the server's message when the save is stale", async () => {
    stubApi(
      { draft: prDraft(), repo: "jorden/claude-custom" },
      {
        save: jsonResponse(
          { message: "the draft changed on disk; reload it" },
          409,
        ),
      },
    );
    render(<DraftEditor id={PR_ID} />);
    fireEvent.change(await screen.findByLabelText("Title"), {
      target: { value: "Renamed" },
    });

    fireEvent.click(screen.getByRole("button", { name: "Save" }));

    expect(
      await screen.findByText("the draft changed on disk; reload it"),
    ).toBeTruthy();
    expect(screen.getByText("Unsaved changes")).toBeTruthy();
  });

  it("starts an already-posted draft with its link and Create PR disabled", async () => {
    stubApi({
      draft: prDraft({ posted: { url: PR_URL, at: CREATED } }),
      repo: "jorden/claude-custom",
    });
    render(<DraftEditor id={PR_ID} />);

    expect(
      await screen.findByRole("link", { name: "View posted on GitHub" }),
    ).toBeTruthy();
    expect(
      screen
        .getByRole("button", { name: "Create PR on GitHub" })
        .hasAttribute("disabled"),
    ).toBe(true);
  });

  it("names the review action and disables posting when the project has no GitHub origin", async () => {
    stubApi({ draft: reviewDraft(), repo: null });
    render(<DraftEditor id={REVIEW_ID} />);

    expect(
      await screen.findByText("No GitHub origin in /work/tree"),
    ).toBeTruthy();
    expect(
      screen
        .getByRole("button", { name: "Post review" })
        .hasAttribute("disabled"),
    ).toBe(true);
  });

  it("marks a comment's label as an unsaved change", async () => {
    stubApi({ draft: reviewDraft(), repo: "jorden/claude-custom" });
    render(<DraftEditor id={REVIEW_ID} />);

    fireEvent.change(await screen.findByLabelText("Label 1"), {
      target: { value: "nitpick" },
    });

    expect(screen.getByText("Unsaved changes")).toBeTruthy();
    await waitFor(() =>
      expect(
        screen.getByRole("button", { name: "Save" }).hasAttribute("disabled"),
      ).toBe(false),
    );
  });
});
