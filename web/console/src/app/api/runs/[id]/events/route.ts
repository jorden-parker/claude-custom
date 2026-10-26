import { isRunEndLine } from "@/lib/run-event";
import { resolveRunFile } from "@/lib/run-log";
import { parseLastEventId } from "@/lib/review-stream";
import { serverSentFrame, streamLines } from "@/lib/line-tail";

type RouteContext = { params: Promise<{ id: string }> };

export async function GET(request: Request, context: RouteContext) {
  const { id } = await context.params;
  const file = resolveRunFile(id);
  if (!file) {
    return new Response("Run not found", { status: 404 });
  }
  const skipLines = parseLastEventId(request.headers.get("Last-Event-ID"));
  const stream = streamLines(file, request.signal, {
    skipLines,
    isEnd: isRunEndLine,
    frame: serverSentFrame,
  });
  return new Response(stream, {
    headers: {
      "Content-Type": "text/event-stream",
      "Cache-Control": "no-cache, no-transform",
    },
  });
}
