import { connection, NextResponse } from "next/server";
import { loadResidency } from "@/lib/lease";
import { consoleRepoDir } from "@/lib/sizes";

export async function GET() {
  await connection();
  const result = await loadResidency(consoleRepoDir());
  if (!result.ok) {
    return NextResponse.json({ message: result.message }, { status: 502 });
  }
  return NextResponse.json(result.residency);
}
