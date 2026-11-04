import { NextResponse } from "next/server";
import { changeModel, findServerModel, listServerModels, modelServerUrl, type ModelAction } from "./model-server";

const JSON_CONTENT_TYPE = "application/json";

export async function modelActionResponse(action: ModelAction, request: Request): Promise<NextResponse> {
  if (!request.headers.get("content-type")?.startsWith(JSON_CONTENT_TYPE)) {
    return failure("Expected application/json", 415);
  }
  const id = await readModelId(request);
  if (id === null) {
    return failure("Expected { model: string }", 400);
  }
  const serverUrl = modelServerUrl();
  const listed = await listServerModels(serverUrl);
  if (listed === null) {
    return failure(`the model server at ${serverUrl} did not answer`, 502);
  }
  if (findServerModel(listed, id) === undefined) {
    return failure(`${id} is not a model the server lists`, 404);
  }
  const result = await changeModel(serverUrl, action, id);
  return result.ok ? NextResponse.json({ ok: true }) : failure(result.message, 502);
}

async function readModelId(request: Request): Promise<string | null> {
  const body: unknown = await request.json().catch(() => null);
  const model = typeof body === "object" && body !== null && "model" in body ? body.model : null;
  return typeof model === "string" && model !== "" ? model : null;
}

function failure(message: string, status: number): NextResponse {
  return NextResponse.json({ message }, { status });
}
