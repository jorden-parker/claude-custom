const DEFAULT_HOST = "127.0.0.1:11434";
const PING_TIMEOUT_MS = 2000;

export async function ollamaIsUp(env: Readonly<Record<string, string | undefined>> = process.env): Promise<boolean> {
  try {
    const response = await fetch(`${ollamaBaseUrl(env)}/api/version`, {
      cache: "no-store",
      signal: AbortSignal.timeout(PING_TIMEOUT_MS),
    });
    return response.ok;
  } catch {
    return false;
  }
}

function ollamaBaseUrl(env: Readonly<Record<string, string | undefined>>): string {
  const host = (env.OLLAMA_HOST ?? "").trim() || DEFAULT_HOST;
  const withScheme = /^https?:\/\//.test(host) ? host : `http://${host}`;
  return withScheme.replace("0.0.0.0", "127.0.0.1");
}
