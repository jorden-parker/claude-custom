import { connection, NextResponse } from "next/server";

export async function GET() {
  await connection();
  return NextResponse.json({ dir: process.env.CONSOLE_PROJECT_DIR ?? null });
}
