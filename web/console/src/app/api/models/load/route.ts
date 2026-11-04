import { modelActionResponse } from "@/lib/model-action-route";

export function POST(request: Request) {
  return modelActionResponse("load", request);
}
