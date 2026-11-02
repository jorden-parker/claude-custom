import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { runOnce } from "@/lib/run-once";
import { GET } from "./route";

vi.mock("@/lib/run-once", () => ({ runOnce: vi.fn() }));
vi.mock("next/server", async (importOriginal) => ({
  ...(await importOriginal<typeof import("next/server")>()),
  connection: async () => undefined,
}));

describe("/api/rule-cards", () => {
  let repo: string;

  beforeEach(() => {
    repo = fs.mkdtempSync(path.join(os.tmpdir(), "rule-cards-route-"));
    fs.mkdirSync(path.join(repo, "ollama", "rule-cards"), { recursive: true });
    fs.writeFileSync(
      path.join(repo, "ollama", "rule-cards", "bash.md"),
      "---\ntriggers:\n  - tool: Bash\n---\n\nBash runs in a sandbox.\n",
    );
    process.env.CLAUDE_CUSTOM_HOME = repo;
  });

  afterEach(() => {
    delete process.env.CLAUDE_CUSTOM_HOME;
    vi.mocked(runOnce).mockReset();
    fs.rmSync(repo, { recursive: true, force: true });
  });

  it("lists the cards that rule-cards.py --list prints with each body", async () => {
    vi.mocked(runOnce).mockResolvedValue({
      code: 0,
      stdout: "bash: tool Bash\nmissing: suffix .zz\n",
      stderr: "",
    });

    const response = await GET();

    expect(runOnce).toHaveBeenCalledWith(
      [`${repo}/shared/hooks/rule-cards.py`, "--list"],
      expect.any(Object),
    );
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({
      cards: [
        {
          id: "bash",
          triggers: ["tool Bash"],
          body: "Bash runs in a sandbox.",
        },
        { id: "missing", triggers: ["suffix .zz"], body: "" },
      ],
    });
  });

  it("answers 502 with the stderr message when the hook fails", async () => {
    vi.mocked(runOnce).mockResolvedValue({
      code: 1,
      stdout: "",
      stderr: "rule-cards: skipping broken.md: no trigger\n",
    });

    const response = await GET();

    expect(response.status).toBe(502);
    expect(await response.json()).toEqual({
      message: "rule-cards: skipping broken.md: no trigger",
    });
  });
});
