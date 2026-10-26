import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { GET } from "./route";

const STUB_LAUNCHER = `#!/bin/sh
if [ "$1" = "--print-config" ] && [ "$2" = "27b" ]; then
  printf 'size: 27b\\ncommand: claude --tools Bash,Read\\n'
  exit 0
fi
echo "stub refused: $*" >&2
exit 3
`;

function request(query: string) {
  return new Request(`http://127.0.0.1/api/config${query}`);
}

describe("GET /api/config", () => {
  let repo: string;

  beforeEach(() => {
    repo = fs.mkdtempSync(path.join(os.tmpdir(), "config-route-"));
    fs.mkdirSync(path.join(repo, "ollama"));
    fs.mkdirSync(path.join(repo, "bin"));
    fs.writeFileSync(path.join(repo, "ollama", "settings.27b.json"), "{}");
    fs.writeFileSync(path.join(repo, "ollama", "Modelfile.27b"), "");
    fs.writeFileSync(path.join(repo, "bin", "claude-ollama"), STUB_LAUNCHER, { mode: 0o755 });
    process.env.CLAUDE_CUSTOM_HOME = repo;
  });

  afterEach(() => {
    delete process.env.CLAUDE_CUSTOM_HOME;
    fs.rmSync(repo, { recursive: true, force: true });
  });

  it("refuses a size that is not configured", async () => {
    const response = await GET(request("?size=35b"));
    expect(response.status).toBe(400);
  });

  it("refuses a request with no size", async () => {
    const response = await GET(request(""));
    expect(response.status).toBe(400);
  });

  it("returns the resolved settings as key and value entries", async () => {
    const response = await GET(request("?size=27b"));
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({
      code: 0,
      entries: [
        { key: "size", value: "27b" },
        { key: "command", value: "claude --tools Bash,Read" },
      ],
      stderr: "",
    });
  });

  it("reports a non-zero exit with its code and stderr", async () => {
    fs.writeFileSync(path.join(repo, "bin", "claude-ollama"), "#!/bin/sh\necho 'no config' >&2\nexit 3\n", {
      mode: 0o755,
    });
    const response = await GET(request("?size=27b"));
    expect(await response.json()).toEqual({ code: 3, entries: [], stderr: "no config\n" });
  });
});
