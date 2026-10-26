import { runOnce } from "./run-once";

export type ServerVariable = {
  name: string;
  summary: string;
  current: string;
  set: boolean;
  recommended: string;
};

export type ServerSnapshot = {
  path: string;
  exists: boolean;
  variables: ServerVariable[];
  conflicts: string[];
};

export type SnapshotResult = { ok: true; snapshot: ServerSnapshot } | { ok: false; message: string };

const SNAPSHOT_TIMEOUT_MS = 60_000;
const SNAPSHOT_MAX_BYTES = 1024 * 1024;

export async function loadServerSnapshot(repoDir: string): Promise<SnapshotResult> {
  const result = await runOnce([`${repoDir}/bin/ollama-agent`, "-json"], {
    timeoutMs: SNAPSHOT_TIMEOUT_MS,
    maxBytes: SNAPSHOT_MAX_BYTES,
  });
  if (result.code !== 0) {
    return { ok: false, message: result.stderr.trim() || `ollama-agent -json exited ${result.code}` };
  }
  return parseSnapshot(result.stdout);
}

function parseSnapshot(text: string): SnapshotResult {
  try {
    return { ok: true, snapshot: JSON.parse(text) as ServerSnapshot };
  } catch {
    return { ok: false, message: "ollama-agent -json printed no JSON" };
  }
}
