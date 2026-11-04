const DEFAULT_MODEL_SERVER_URL = "http://127.0.0.1:11435";
const PROBE_TIMEOUT_MS = 3000;
const ACTION_TIMEOUT_MS = 30_000;
const CACHE_SOURCE = "cache";
const MODEL_STATUSES = ["unloaded", "loading", "loaded"] as const;

type Env = Readonly<Record<string, string | undefined>>;

export type ServerModelStatus = (typeof MODEL_STATUSES)[number];

export type ServerModel = {
  id: string;
  aliases: string[];
  status: ServerModelStatus;
  bytes: number | null;
};

export type ModelAction = "load" | "unload";

export type ActionResult = { ok: true } | { ok: false; message: string };

export function modelServerUrl(env: Env = process.env): string {
  const configured = (env.LLAMA_SERVER_URL ?? "").trim();
  return (configured || DEFAULT_MODEL_SERVER_URL).replace(/\/+$/, "");
}

export async function listServerModels(baseUrl: string): Promise<ServerModel[] | null> {
  return parseServerModels(await getJson(baseUrl, "/models"));
}

export async function serverBuild(baseUrl: string): Promise<string | null> {
  const props = await getJson(baseUrl, "/props");
  return isRecord(props) && typeof props.build_info === "string" ? props.build_info : null;
}

export function parseServerModels(body: unknown): ServerModel[] | null {
  if (!isRecord(body) || !Array.isArray(body.data)) {
    return null;
  }
  return body.data.flatMap((entry: unknown) => {
    const model = serverModelOf(entry);
    return model === null ? [] : [model];
  });
}

export function findServerModel(models: readonly ServerModel[], name: string): ServerModel | undefined {
  return models.find((model) => model.id === name || model.aliases.includes(name));
}

export async function changeModel(baseUrl: string, action: ModelAction, id: string): Promise<ActionResult> {
  let response: Response;
  try {
    response = await fetch(`${baseUrl}/models/${action}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ model: id }),
      cache: "no-store",
      signal: AbortSignal.timeout(ACTION_TIMEOUT_MS),
    });
  } catch {
    return { ok: false, message: `the model server at ${baseUrl} did not answer` };
  }
  if (response.ok) {
    return { ok: true };
  }
  return { ok: false, message: await errorMessage(response, action) };
}

async function errorMessage(response: Response, action: ModelAction): Promise<string> {
  const body: unknown = await response.json().catch(() => null);
  const error = isRecord(body) ? body.error : null;
  if (isRecord(error) && typeof error.message === "string") {
    return error.message;
  }
  return `${action} failed with status ${response.status}`;
}

function serverModelOf(entry: unknown): ServerModel | null {
  if (!isRecord(entry) || typeof entry.id !== "string" || entry.source === CACHE_SOURCE) {
    return null;
  }
  const status = statusOf(entry.status);
  if (status === null) {
    return null;
  }
  return {
    id: entry.id,
    aliases: Array.isArray(entry.aliases) ? entry.aliases.filter((alias) => typeof alias === "string") : [],
    status,
    bytes: isRecord(entry.meta) && typeof entry.meta.size === "number" ? entry.meta.size : null,
  };
}

function statusOf(status: unknown): ServerModelStatus | null {
  const value = isRecord(status) ? status.value : null;
  return MODEL_STATUSES.find((known) => known === value) ?? null;
}

async function getJson(baseUrl: string, route: string): Promise<unknown> {
  try {
    const response = await fetch(`${baseUrl}${route}`, {
      cache: "no-store",
      signal: AbortSignal.timeout(PROBE_TIMEOUT_MS),
    });
    return response.ok ? await response.json() : null;
  } catch {
    return null;
  }
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}
