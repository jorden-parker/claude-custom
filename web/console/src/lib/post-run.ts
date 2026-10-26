import type { CommandParams } from "./console-commands";

export type PostRunResult = { ok: true; id: string } | { ok: false; message: string };

const DEFAULT_REASON = "The run could not start";

export async function postRun(command: string, params: CommandParams): Promise<PostRunResult> {
  const response = await fetch("/api/runs", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ command, params }),
  });
  const body = (await response.json()) as { id?: string; message?: string };
  if (response.status === 201 && body.id !== undefined) {
    return { ok: true, id: body.id };
  }
  return { ok: false, message: body.message ?? DEFAULT_REASON };
}
