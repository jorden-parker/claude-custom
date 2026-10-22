import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import { reduceEvents } from "@/lib/review-state";
import { ReviewTranscript } from "./review-transcript";

const hostile = "<img src=x onerror=alert(1)>";
const PROMPT_BODY = "PROMPT_BODY_MARKER";

function transcriptOf(events: Parameters<typeof reduceEvents>[0]) {
  return reduceEvents(events).transcript;
}

const promptEvents = (user: string) => [
  { kind: "file_start", index: 1, total: 1, path: "src/a.ts", chars: 10 },
  { kind: "prompt", scope: "file", index: 1, path: "src/a.ts", attempt: 1, system: "sys", user },
];

describe("ReviewTranscript", () => {
  it("shows an empty state for a log with no transcript", () => {
    const markup = renderToStaticMarkup(<ReviewTranscript entries={[]} />);

    expect(markup).toContain(
      "This review has no transcript. It was recorded before transcripts were logged.",
    );
  });

  it("keeps a reply with markdown syntax as literal text", () => {
    const entries = transcriptOf([
      ...promptEvents("user"),
      { kind: "reply_text", scope: "file", index: 1, attempt: 1, text: "**x**" },
      { kind: "file_done", index: 1, total: 1, path: "src/a.ts", outcome: "clean", seconds: 1 },
    ]);
    const markup = renderToStaticMarkup(<ReviewTranscript entries={entries} />);

    expect(markup).toContain("**x**");
    expect(markup).not.toContain("<strong>");
  });

  it("escapes HTML in a prompt", () => {
    const entries = transcriptOf(promptEvents(hostile));
    const markup = renderToStaticMarkup(<ReviewTranscript entries={entries} />);

    expect(markup).toContain("&lt;img src=x onerror=alert(1)&gt;");
    expect(markup).not.toContain("<img");
  });

  it("renders the prompt body inside a hidden panel until it is opened", () => {
    const entries = transcriptOf(promptEvents(PROMPT_BODY));
    const markup = renderToStaticMarkup(<ReviewTranscript entries={entries} />);
    const bodyAt = markup.indexOf(PROMPT_BODY);
    const panelOpenTag = markup.slice(markup.lastIndexOf("<div", bodyAt), bodyAt);

    expect(markup).toContain("Prompt · 18 chars");
    expect(panelOpenTag).toContain("hidden");
  });

  it("shows the caret only while an attempt is not done", () => {
    const streaming = transcriptOf([
      ...promptEvents("user"),
      { kind: "reply_text", scope: "file", index: 1, attempt: 1, text: "partial" },
    ]);
    const finished = transcriptOf([
      ...promptEvents("user"),
      { kind: "file_done", index: 1, total: 1, path: "src/a.ts", outcome: "clean", seconds: 1 },
    ]);

    expect(renderToStaticMarkup(<ReviewTranscript entries={streaming} />)).toContain(
      'data-slot="transcript-caret"',
    );
    expect(renderToStaticMarkup(<ReviewTranscript entries={finished} />)).not.toContain(
      'data-slot="transcript-caret"',
    );
  });

  it("says it is waiting for the first token when the reply is still empty", () => {
    const entries = transcriptOf(promptEvents("user"));
    const markup = renderToStaticMarkup(<ReviewTranscript entries={entries} />);

    expect(markup).toContain("waiting for the first token");
  });

  it("labels a second attempt as a retry", () => {
    const entries = transcriptOf([
      ...promptEvents("first"),
      { kind: "prompt", scope: "file", index: 1, path: "src/a.ts", attempt: 2, system: "sys", user: "again" },
    ]);
    const markup = renderToStaticMarkup(<ReviewTranscript entries={entries} />);

    expect(markup).toContain("retry");
  });
});
