import { connection, NextResponse } from "next/server";
import type { Draft } from "@/lib/draft-schema";
import {
  messageResponse,
  isJsonRequest,
  readJsonObject,
} from "@/lib/draft-responses";
import {
  deleteDraft,
  readStoredDraft,
  repoFor,
  saveEdits,
  type EditOutcome,
} from "@/lib/drafts";

type RouteContext = { params: Promise<{ id: string }> };

export async function GET(_request: Request, context: RouteContext) {
  await connection();
  const { id } = await context.params;
  const stored = readStoredDraft(id);
  if (stored === null) {
    return messageResponse("no such draft", 404);
  }
  if (!stored.parsed.ok) {
    return messageResponse(stored.parsed.reason, 422);
  }
  return savedResponse(stored.parsed.draft, stored.hash);
}

export async function PUT(request: Request, context: RouteContext) {
  if (!isJsonRequest(request)) {
    return messageResponse("Expected application/json", 415);
  }
  const body = await readJsonObject(request);
  if (body === null || typeof body.hash !== "string") {
    return messageResponse("Expected { hash, ...editable fields }", 400);
  }
  const { id } = await context.params;
  return editResponse(saveEdits(id, body.hash, body));
}

export async function DELETE(_request: Request, context: RouteContext) {
  const { id } = await context.params;
  if (!deleteDraft(id)) {
    return messageResponse("no such draft", 404);
  }
  return NextResponse.json({ deleted: id });
}

async function editResponse(outcome: EditOutcome) {
  switch (outcome.kind) {
    case "saved":
      return savedResponse(outcome.draft, outcome.hash);
    case "missing":
      return messageResponse("no such draft", 404);
    case "unreadable":
      return messageResponse(outcome.reason, 422);
    case "stale":
      return messageResponse("the draft changed on disk; reload it", 409);
    case "invalid":
      return messageResponse(outcome.reason, 400);
  }
}

async function savedResponse(draft: Draft, hash: string) {
  return NextResponse.json({ draft, hash, repo: await repoFor(draft.project) });
}
