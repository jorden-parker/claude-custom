import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { GET } from "./route";

const READ_TIMEOUT_MS = 5000;

function withTimeout<T>(promise: Promise<T>): Promise<T> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  const timeout = new Promise<never>((_, reject) => {
    timer = setTimeout(() => reject(new Error("timed out waiting for stream data")), READ_TIMEOUT_MS);
  });
  return Promise.race([promise, timeout]).finally(() => clearTimeout(timer));
}

async function readUntil(reader: ReadableStreamDefaultReader<Uint8Array>, isDone: (text: string) => boolean) {
  const decoder = new TextDecoder();
  let text = "";
  while (!isDone(text)) {
    const chunk = await withTimeout(reader.read());
    if (chunk.done) {
      break;
    }
    text += decoder.decode(chunk.value, { stream: true });
  }
  return text;
}

function launcherPrinting(logFile: string): string {
  return `#!/bin/sh\nif [ "$1" = logs ] && [ "$2" = --path ]; then echo '${logFile}'; exit 0; fi\necho 'no Ollama log found' >&2\nexit 1\n`;
}

describe("GET /api/logs/events", () => {
  let repo: string;
  let logFile: string;

  beforeEach(() => {
    repo = fs.mkdtempSync(path.join(os.tmpdir(), "logs-events-"));
    fs.mkdirSync(path.join(repo, "bin"));
    logFile = path.join(repo, "server.log");
    fs.writeFileSync(path.join(repo, "bin", "claude-ollama"), launcherPrinting(logFile), { mode: 0o755 });
    process.env.CLAUDE_CUSTOM_HOME = repo;
  });

  afterEach(() => {
    delete process.env.CLAUDE_CUSTOM_HOME;
    fs.rmSync(repo, { recursive: true, force: true });
  });

  it("answers 404 with the launcher's message when there is no log", async () => {
    fs.writeFileSync(path.join(repo, "bin", "claude-ollama"), "#!/bin/sh\necho 'no Ollama log found' >&2\nexit 1\n", {
      mode: 0o755,
    });
    const response = await GET(new Request("http://127.0.0.1/api/logs/events"));
    expect(response.status).toBe(404);
    expect(await response.text()).toBe("no Ollama log found");
  });

  it("streams the log's lines, then tails a line appended later", async () => {
    fs.writeFileSync(logFile, "time=1 level=INFO msg=a\ntime=2 level=INFO msg=b\ntime=3 level=WARN msg=c\n");
    const controller = new AbortController();
    const response = await GET(new Request("http://127.0.0.1/api/logs/events", { signal: controller.signal }));
    expect(response.headers.get("Content-Type")).toBe("text/event-stream");
    const reader = response.body!.getReader();

    const replayed = await readUntil(reader, (text) => text.includes("msg=c"));
    expect(replayed).toContain('"level":"warn"');

    fs.appendFileSync(logFile, "time=4 level=ERROR msg=d\n");
    const tail = await readUntil(reader, (text) => text.includes("msg=d"));
    expect(tail).toContain('"level":"error"');
    controller.abort();
  });
});
