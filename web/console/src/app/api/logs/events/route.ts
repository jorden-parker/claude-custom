import { logFrame } from "@/lib/log-line";
import { streamLines } from "@/lib/line-tail";
import { requestedLogPath } from "../log-request";

export async function GET(request: Request) {
  const logPath = await requestedLogPath(request);
  if (logPath instanceof Response) {
    return logPath;
  }
  const stream = streamLines(logPath, request.signal, {
    skipLines: 0,
    isEnd: () => false,
    frame: logFrame,
    startOffset: "end-64k",
  });
  return new Response(stream, {
    headers: {
      "Content-Type": "text/event-stream",
      "Cache-Control": "no-cache, no-transform",
    },
  });
}
