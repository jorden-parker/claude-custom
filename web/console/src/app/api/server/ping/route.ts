import { connection, NextResponse } from "next/server";
import { ollamaIsUp } from "@/lib/ollama-health";

export async function GET() {
  await connection();
  return NextResponse.json({ up: await ollamaIsUp() });
}
