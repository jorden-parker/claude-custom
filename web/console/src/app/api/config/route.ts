import { NextResponse } from "next/server";
import { CONSOLE_QUERIES } from "@/lib/console-commands";
import { parsePrintConfig } from "@/lib/print-config";
import { runOnce } from "@/lib/run-once";
import { consoleRepoDir } from "@/lib/sizes";

const CONFIG_TIMEOUT_MS = 10_000;
const CONFIG_MAX_BYTES = 1024 * 1024;

export async function GET(request: Request) {
  const size = new URL(request.url).searchParams.get("size") ?? "";
  const argv = CONSOLE_QUERIES.printConfig.argv({ size }, consoleRepoDir());
  if (argv === null) {
    return NextResponse.json({ message: "Unknown size" }, { status: 400 });
  }
  const result = await runOnce(argv, { timeoutMs: CONFIG_TIMEOUT_MS, maxBytes: CONFIG_MAX_BYTES });
  return NextResponse.json({
    code: result.code,
    entries: result.code === 0 ? parsePrintConfig(result.stdout) : [],
    stderr: result.stderr,
  });
}
