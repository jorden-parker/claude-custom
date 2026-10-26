import { connection, NextResponse } from "next/server";
import { consoleRepoDir } from "@/lib/sizes";
import { loadServerSnapshot } from "@/lib/server-snapshot";

export async function GET() {
  await connection();
  const result = await loadServerSnapshot(consoleRepoDir());
  if (!result.ok) {
    return NextResponse.json({ message: result.message }, { status: 502 });
  }
  return NextResponse.json(result.snapshot);
}
