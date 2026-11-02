import { connection, NextResponse } from "next/server";
import { listProfiles } from "@/lib/profiles";

export async function GET() {
  await connection();
  return NextResponse.json({ profiles: listProfiles() });
}
