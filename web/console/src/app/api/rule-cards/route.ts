import { connection, NextResponse } from "next/server";
import { listRuleCards } from "@/lib/rule-cards";
import { consoleRepoDir } from "@/lib/sizes";

export async function GET() {
  await connection();
  const result = await listRuleCards(consoleRepoDir());
  if (!result.ok) {
    return NextResponse.json({ message: result.message }, { status: 502 });
  }
  return NextResponse.json({ cards: result.cards });
}
