import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import { reduceEvents } from "@/lib/review-state";
import { ReviewTranscript } from "./review-transcript";

const hostile = "<img src=x onerror=alert(1)>";
const PROMPT_BODY = "PROMPT_BODY_MARKER";

const promptEvents = (user: string, total = 1) => [
  { kind: "file_start", index: 1, total, path: "src/a.ts", chars: 10 },
  { kind: "prompt", scope: "file", index: 1, path: "src/a.ts", attempt: 1, system: "sys", user },
];

const doneEvent = { kind: "file_done", index: 1, total: 1, path: "src/a.ts", outcome: "clean", seconds: 1 };

function render(events: Parameters<typeof reduceEvents>[0]) {
  return renderToStaticMarkup(<ReviewTranscript state={reduceEvents(events)} />);
}

describe("ReviewTranscript", () => {
  it("shows an empty state for a log with no transcript", () => {
    const markup = render([]);

    expect(markup).toContain(
      "This review has no transcript. It was recorded before transcripts were logged.",
    );
  });

  it("numbers a file against the review's file total, not the transcript count", () => {
    const markup = render(promptEvents("user", 3));

    expect(markup).toContain("[1/3] src/a.ts");
  });

  it("labels the sent prompt and the model reply", () => {
    const markup = render(promptEvents("user"));

    expect(markup).toContain("Sent to model");
    expect(markup).toContain("Model reply");
  });

  it("keeps a reply with markdown syntax as literal text", () => {
    const markup = render([
      ...promptEvents("user"),
      { kind: "reply_text", scope: "file", index: 1, attempt: 1, text: "**x**" },
      doneEvent,
    ]);

    expect(markup).toContain("**x**");
    expect(markup).not.toContain("<strong>");
  });

  it("escapes HTML in a prompt", () => {
    const markup = render(promptEvents(hostile));

    expect(markup).toContain("&lt;img src=x onerror=alert(1)&gt;");
    expect(markup).not.toContain("<img");
  });

  it("renders the prompt body inside a hidden panel until it is opened", () => {
    const markup = render(promptEvents(PROMPT_BODY));
    const bodyAt = markup.indexOf(PROMPT_BODY);
    const panelOpenTag = markup.slice(markup.lastIndexOf("<div", bodyAt), bodyAt);

    expect(markup).toContain("Prompt · 18 chars");
    expect(panelOpenTag).toContain("hidden");
  });

  it("shows the caret inline at the end of the reply while it streams", () => {
    const markup = render([
      ...promptEvents("user"),
      { kind: "reply_text", scope: "file", index: 1, attempt: 1, text: "partial" },
    ]);

    expect(markup).toContain('partial<span data-slot="transcript-caret"');
  });

  it("hides the caret once the attempt is done", () => {
    const markup = render([
      ...promptEvents("user"),
      { kind: "reply_text", scope: "file", index: 1, attempt: 1, text: "partial" },
      doneEvent,
    ]);

    expect(markup).not.toContain('data-slot="transcript-caret"');
  });

  it("shows only the waiting text and caret while the reply is empty, with no empty pre", () => {
    const markup = render(promptEvents("user"));

    expect(markup).toContain('waiting for the first token<span data-slot="transcript-caret"');
    expect(markup).not.toContain("></pre>");
  });

  it("labels a second attempt as a retry", () => {
    const markup = render([
      ...promptEvents("first"),
      { kind: "prompt", scope: "file", index: 1, path: "src/a.ts", attempt: 2, system: "sys", user: "again" },
    ]);

    expect(markup).toContain("retry");
  });
});
