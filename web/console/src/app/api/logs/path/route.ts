import { connection } from "next/server";
import { readLogPath } from "@/lib/log-path";
import { consoleRepoDir } from "@/lib/sizes";

export async function GET() {
  await connection();
  const log = await readLogPath(consoleRepoDir());
  if (!log.ok) {
    return new Response(log.message, { status: 404 });
  }
  return Response.json({ path: log.path });
}
