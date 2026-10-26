import { connection, NextResponse } from "next/server";
import { toolsReportArgv } from "@/lib/console-commands";
import { consoleRepoDir } from "@/lib/sizes";
import { runOnce } from "@/lib/run-once";

const TOOLS_TIMEOUT_MS = 60_000;
const TOOLS_MAX_BYTES = 5_000_000;

export async function GET() {
  await connection();
  const result = await runOnce(toolsReportArgv(consoleRepoDir()), {
    timeoutMs: TOOLS_TIMEOUT_MS,
    maxBytes: TOOLS_MAX_BYTES,
  });
  if (result.code !== 0) {
    return NextResponse.json({ message: result.stderr.trim() || "claude-tools failed" }, { status: 502 });
  }
  try {
    return NextResponse.json(JSON.parse(result.stdout));
  } catch {
    return NextResponse.json({ message: "claude-tools printed no report" }, { status: 502 });
  }
}
