import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const TOOL_REPORT = {
  path: "personal/settings.tokens.json",
  tools: [
    { name: "Bash", description: "Run shell commands", promptsByDefault: true, permission: "default", disabled: false },
    { name: "WebFetch", description: "Fetch a web page", promptsByDefault: true, permission: "allow", disabled: false },
    { name: "Agent", description: "Spawn a subagent", promptsByDefault: true, permission: "default", disabled: false },
  ],
};

export type FixtureRepo = { repoDir: string; configHome: string; stateDir: string; cleanup: () => void };

export function makeFixtureRepo(): FixtureRepo {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "profile-fixture-"));
  const repoDir = path.join(root, "repo");
  writeRepoFiles(repoDir);
  return {
    repoDir,
    configHome: path.join(root, "config"),
    stateDir: path.join(root, "state"),
    cleanup: () => fs.rmSync(root, { recursive: true, force: true }),
  };
}

function writeRepoFiles(repoDir: string): void {
  for (const folder of ["bin", "personal", "ollama"]) {
    fs.mkdirSync(path.join(repoDir, folder), { recursive: true });
  }
  fs.writeFileSync(path.join(repoDir, "personal", "settings.tokens.json"), JSON.stringify({ sandbox: { enabled: true } }));
  fs.writeFileSync(
    path.join(repoDir, "ollama", "settings.27b.json"),
    JSON.stringify({ model: "qwen3.8-27b-cc", hooks: { Stop: [{ hooks: [{ type: "command", command: "x/stop-verify.py" }] }] } }),
  );
  fs.writeFileSync(path.join(repoDir, "ollama", "Modelfile.27b"), "FROM qwen3.8:27b-mlx\n");
  fs.writeFileSync(
    path.join(repoDir, "ollama", "sizes.json"),
    JSON.stringify({ "27b": { base: "qwen3.8:27b-mlx", model: "qwen3.8-27b-cc", context: 65536, output_tokens: 8192, parameters: { temperature: 0.7 } } }),
  );
  writeClaudeToolsStub(path.join(repoDir, "bin", "claude-tools"));
}

function writeClaudeToolsStub(target: string): void {
  const report = JSON.stringify(TOOL_REPORT).replaceAll("'", "");
  fs.writeFileSync(target, `#!/bin/sh\nprintf '%s' '${report}'\n`, { mode: 0o755 });
}
