import { describe, expect, it } from "vitest";
import { runOnce } from "./run-once";

const OPTIONS = { timeoutMs: 5_000, maxBytes: 100_000 };

describe("runOnce", () => {
  it("resolves the exit code, stdout and stderr of a successful run", async () => {
    const result = await runOnce(
      [process.execPath, "-e", "process.stdout.write('hello'); process.stderr.write('note')"],
      OPTIONS,
    );
    expect(result).toEqual({ code: 0, stdout: "hello", stderr: "note" });
  });

  it("resolves a non-zero exit without throwing", async () => {
    const result = await runOnce(
      [process.execPath, "-e", "process.stderr.write('bad'); process.exit(3)"],
      OPTIONS,
    );
    expect(result).toEqual({ code: 3, stdout: "", stderr: "bad" });
  });

  it("maps a run that outlives its timeout to code 124", async () => {
    const result = await runOnce([process.execPath, "-e", "setTimeout(() => {}, 10000)"], {
      ...OPTIONS,
      timeoutMs: 200,
    });
    expect(result.code).toBe(124);
  });

  it("maps a missing executable to code 127 without throwing", async () => {
    const result = await runOnce(["/nonexistent/claude-custom-binary"], OPTIONS);
    expect(result.code).toBe(127);
  });
});
