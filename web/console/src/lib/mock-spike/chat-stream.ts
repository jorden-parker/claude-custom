export type ChatStreamEvent = {
  content: string;
  tokensPerSecond: number | null;
};

type CompletionChunk = {
  choices?: { delta?: { content?: string | null } }[];
  timings?: { predicted_per_second?: number };
};

const DATA_FIELD = "data:";
const DONE_MARKER = "[DONE]";

export function chatCompletionsUrl(baseUrl: string): string {
  return `${baseUrl}/v1/chat/completions`;
}

export function parseStreamLine(line: string): ChatStreamEvent | null {
  const trimmed = line.trim();
  if (!trimmed.startsWith(DATA_FIELD)) return null;
  const payload = trimmed.slice(DATA_FIELD.length).trim();
  if (payload === DONE_MARKER) return null;
  const chunk = JSON.parse(payload) as CompletionChunk;
  return {
    content: chunk.choices?.[0]?.delta?.content ?? "",
    tokensPerSecond: chunk.timings?.predicted_per_second ?? null,
  };
}

function* eventsOf(lines: string[]): Generator<ChatStreamEvent> {
  for (const line of lines) {
    const event = parseStreamLine(line);
    if (event) yield event;
  }
}

export async function* chatStreamEvents(
  body: ReadableStream<Uint8Array>,
): AsyncGenerator<ChatStreamEvent> {
  const decoder = new TextDecoder();
  const reader = body.getReader();
  let pending = "";
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    pending += decoder.decode(value, { stream: true });
    const lines = pending.split("\n");
    pending = lines.pop() ?? "";
    yield* eventsOf(lines);
  }
  yield* eventsOf([pending + decoder.decode()]);
}
