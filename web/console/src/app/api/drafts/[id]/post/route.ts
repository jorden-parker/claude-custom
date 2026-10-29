import { connection, NextResponse } from "next/server";
import {
  messageResponse,
  isJsonRequest,
  readJsonObject,
} from "@/lib/draft-responses";
import { postStoredDraft, type PostOutcome } from "@/lib/draft-post";

type RouteContext = { params: Promise<{ id: string }> };

export async function POST(request: Request, context: RouteContext) {
  await connection();
  if (!isJsonRequest(request)) {
    return messageResponse("Expected application/json", 415);
  }
  const body = await readJsonObject(request);
  if (body === null || typeof body.hash !== "string") {
    return messageResponse("Expected { hash, draft? }", 400);
  }
  const { id } = await context.params;
  return postResponse(
    await postStoredDraft(id, body.hash, body.draft === true),
  );
}

async function postResponse(outcome: PostOutcome) {
  switch (outcome.kind) {
    case "posted":
      return NextResponse.json({
        draft: outcome.draft,
        hash: outcome.hash,
        repo: outcome.repo,
      });
    case "missing":
      return messageResponse("no such draft", 404);
    case "unreadable":
      return messageResponse(outcome.reason, 422);
    case "stale":
      return messageResponse("the draft changed on disk; reload it", 409);
    case "already-posted":
      return messageResponse("this draft is already posted", 409);
    case "no-repo":
      return messageResponse(`no GitHub origin for ${outcome.project}`, 400);
    case "failed":
      return messageResponse(outcome.message, 502);
  }
}
