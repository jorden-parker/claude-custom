import { listServerModels, modelServerUrl, serverBuild } from "./model-server";

const PING_TIMEOUT_MS = 2000;
const LOADING_STATUS = 503;

type Env = Readonly<Record<string, string | undefined>>;

export type ModelServerState = "up" | "loading" | "down";

export type ModelServerHealth = { state: ModelServerState; url: string; build: string | null };

export async function modelServerHealth(env: Env = process.env): Promise<ModelServerHealth> {
  const url = modelServerUrl(env);
  const healthStatus = await probeHealth(url);
  if (healthStatus === null || (healthStatus !== LOADING_STATUS && healthStatus >= 400)) {
    return { state: "down", url, build: null };
  }
  const [models, build] = await Promise.all([listServerModels(url), serverBuild(url)]);
  const loading = healthStatus === LOADING_STATUS || (models ?? []).some((model) => model.status === "loading");
  return { state: loading ? "loading" : "up", url, build };
}

async function probeHealth(url: string): Promise<number | null> {
  try {
    const response = await fetch(`${url}/health`, {
      cache: "no-store",
      signal: AbortSignal.timeout(PING_TIMEOUT_MS),
    });
    return response.status;
  } catch {
    return null;
  }
}
