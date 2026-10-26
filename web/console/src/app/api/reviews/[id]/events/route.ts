import { resolveReviewFile } from "@/lib/reviews";
import { parseLastEventId, streamReviewEvents } from "@/lib/review-stream";

type RouteContext = { params: Promise<{ id: string }> };

export async function GET(request: Request, context: RouteContext) {
  const { id } = await context.params;
  const file = resolveReviewFile(id);
  if (!file) {
    return new Response("Review not found", { status: 404 });
  }
  const skipLines = parseLastEventId(request.headers.get("Last-Event-ID"));
  return new Response(streamReviewEvents(file, request.signal, skipLines), {
    headers: {
      "Content-Type": "text/event-stream",
      "Cache-Control": "no-cache, no-transform",
    },
  });
}
