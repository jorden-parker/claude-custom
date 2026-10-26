import { readLogPath } from "@/lib/log-path";
import { logFrame } from "@/lib/log-line";
import { streamLines } from "@/lib/line-tail";
import { consoleRepoDir } from "@/lib/sizes";

export async function GET(request: Request) {
  const log = await readLogPath(consoleRepoDir());
  if (!log.ok) {
    return new Response(log.message, { status: 404 });
  }
  const stream = streamLines(log.path, request.signal, {
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
