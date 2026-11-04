import { spawn } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const STUB_SERVER = fileURLToPath(
  new URL("../../../../shared/testing/stub-llama-server.py", import.meta.url),
);
const PORT_POLL_MS = 20;
const PORT_DEADLINE_MS = 5000;

export type StubRequest = { method: string; path: string; body: unknown };

export type StubLlama = {
  url: string;
  requests: () => StubRequest[];
  state: () => Record<string, unknown>;
  stop: () => Promise<void>;
};

export const STUB_MODELS = {
  "qwen3.8-27b-cc": { size: 17_000_000_000, n_ctx: 65536 },
  "qwen3.8-27b-cc@think": { size: 17_000_000_000, n_ctx: 65536 },
  "qwen3-embedding-0.6b": { aliases: ["qwen3-embedding:0.6b"], size: 640_000_000, n_ctx: 8192 },
};

export async function startStubLlama(state: Record<string, unknown>): Promise<StubLlama> {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "stub-llama-"));
  const statePath = path.join(dir, "state.json");
  const logPath = path.join(dir, "requests.jsonl");
  const portPath = path.join(dir, "port");
  fs.writeFileSync(statePath, JSON.stringify(state));
  const child = spawn("python3", [STUB_SERVER, "--port-file", portPath, "--state", statePath, "--log", logPath], {
    stdio: "ignore",
  });
  const port = await waitForPort(portPath);
  return {
    url: `http://127.0.0.1:${port}`,
    requests: () => readRequests(logPath),
    state: () => JSON.parse(fs.readFileSync(statePath, "utf8")) as Record<string, unknown>,
    stop: async () => {
      const exited = new Promise((resolve) => child.once("exit", resolve));
      child.kill();
      await exited;
      fs.rmSync(dir, { recursive: true, force: true });
    },
  };
}

export async function closedPortUrl(): Promise<string> {
  const stub = await startStubLlama({});
  await stub.stop();
  return stub.url;
}

async function waitForPort(portPath: string): Promise<string> {
  const deadline = Date.now() + PORT_DEADLINE_MS;
  while (Date.now() < deadline) {
    const port = readTextOrEmpty(portPath).trim();
    if (port !== "") {
      return port;
    }
    await new Promise((resolve) => setTimeout(resolve, PORT_POLL_MS));
  }
  throw new Error("the stub llama-server never wrote its port");
}

function readTextOrEmpty(file: string): string {
  try {
    return fs.readFileSync(file, "utf8");
  } catch {
    return "";
  }
}

function readRequests(logPath: string): StubRequest[] {
  return readTextOrEmpty(logPath)
    .split("\n")
    .filter((line) => line !== "")
    .map((line) => JSON.parse(line) as StubRequest);
}
