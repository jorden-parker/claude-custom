import { parseLogSource, readLogSource } from "@/lib/log-path";
import { consoleRepoDir } from "@/lib/sizes";

export async function requestedLogPath(
  request: Request,
): Promise<string | Response> {
  const source = parseLogSource(
    new URL(request.url).searchParams.get("source"),
  );
  if (source === null) {
    return new Response("Unknown log source", { status: 400 });
  }
  const log = await readLogSource(source, consoleRepoDir());
  return log.ok ? log.path : new Response(log.message, { status: 404 });
}
