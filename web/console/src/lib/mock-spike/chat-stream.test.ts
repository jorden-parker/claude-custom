import { describe, expect, it } from "vitest";
import {
  chatCompletionsUrl,
  chatStreamEvents,
  parseStreamLine,
} from "./chat-stream.ts";

function streamOf(...pieces: string[]): ReadableStream<Uint8Array> {
  const encoder = new TextEncoder();
  return new ReadableStream({
    start(controller) {
      for (const piece of pieces) controller.enqueue(encoder.encode(piece));
      controller.close();
    },
  });
}

async function collect(body: ReadableStream<Uint8Array>) {
  const events = [];
  for await (const event of chatStreamEvents(body)) events.push(event);
  return events;
}

const delta = (content: string) =>
  `data: ${JSON.stringify({ choices: [{ index: 0, delta: { content } }] })}`;

describe("parseStreamLine", () => {
  it("reads the delta content of a chat completion chunk", () => {
    expect(parseStreamLine(delta("hello"))).toEqual({
      content: "hello",
      tokensPerSecond: null,
    });
  });

  it("reads llama-server's decode speed from the final chunk's timings", () => {
    const final = `data: ${JSON.stringify({
      choices: [{ index: 0, delta: {}, finish_reason: "stop" }],
      timings: { predicted_n: 120, predicted_per_second: 31.5 },
    })}`;
    expect(parseStreamLine(final)).toEqual({
      content: "",
      tokensPerSecond: 31.5,
    });
  });

  it("treats a null delta content as empty", () => {
    const line = `data: ${JSON.stringify({ choices: [{ delta: { content: null } }] })}`;
    expect(parseStreamLine(line)?.content).toBe("");
  });

  it("skips the done marker, blank lines and comments", () => {
    expect(parseStreamLine("data: [DONE]")).toBeNull();
    expect(parseStreamLine("")).toBeNull();
    expect(parseStreamLine(": keep-alive")).toBeNull();
  });

  it("accepts a data field without a space after the colon", () => {
    expect(
      parseStreamLine(delta("x").replace("data: ", "data:"))?.content,
    ).toBe("x");
  });
});

describe("chatStreamEvents", () => {
  it("yields one event per data line, even when a line is split across reads", () => {
    const first = delta('{"op":');
    const second = delta('"add"}\n');
    const text = `${first}\n\n${second}\n\ndata: [DONE]\n\n`;
    const middle = Math.floor(first.length / 2);
    return collect(
      streamOf(
        text.slice(0, middle),
        text.slice(middle, first.length + 5),
        text.slice(first.length + 5),
      ),
    ).then((events) => {
      expect(events.map((event) => event.content).join("")).toBe(
        '{"op":"add"}\n',
      );
    });
  });

  it("reads a last line that has no trailing newline", async () => {
    const events = await collect(streamOf(delta("tail")));
    expect(events.map((event) => event.content)).toEqual(["tail"]);
  });
});

describe("chatCompletionsUrl", () => {
  it("names llama-server's OpenAI chat route, never Ollama's", () => {
    expect(chatCompletionsUrl("http://127.0.0.1:11435")).toBe(
      "http://127.0.0.1:11435/v1/chat/completions",
    );
  });
});
