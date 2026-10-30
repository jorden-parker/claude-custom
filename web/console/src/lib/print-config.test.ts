import { describe, expect, it } from "vitest";
import { parsePrintConfig } from "./print-config";

const PRINT_CONFIG_35B = [
  "size: 35b",
  "model: qwen3.6-35b-cc",
  "base: qwen3.6:35b-mlx",
  "embedding model: qwen3-embedding:0.6b",
  "num_ctx: 98304",
  "max context tokens: 98304",
  "settings: /repo/ollama/settings.35b.json",
  "tools: Bash,Read,Edit,Write,Skill,TaskStop",
  "command: claude --settings /repo/ollama/settings.35b.json --tools Bash,Read,Edit,Write,Skill,TaskStop",
].join("\n");

describe("parsePrintConfig", () => {
  it("returns each key and value in output order", () => {
    const entries = parsePrintConfig(`${PRINT_CONFIG_35B}\n`);
    expect(entries.map((entry) => entry.key)).toEqual([
      "size",
      "model",
      "base",
      "embedding model",
      "num_ctx",
      "max context tokens",
      "settings",
      "tools",
      "command",
    ]);
    expect(entries[0]).toEqual({ key: "size", value: "35b" });
    expect(entries[2]).toEqual({ key: "base", value: "qwen3.6:35b-mlx" });
    expect(entries[3]).toEqual({ key: "embedding model", value: "qwen3-embedding:0.6b" });
  });

  it("keeps colons inside the command value", () => {
    const entries = parsePrintConfig("command: srt -- a:b c: d\n");
    expect(entries).toEqual([{ key: "command", value: "srt -- a:b c: d" }]);
  });

  it("skips lines without a key and value separator", () => {
    expect(parsePrintConfig("garbage line\nsize: 27b\n\n")).toEqual([
      { key: "size", value: "27b" },
    ]);
  });
});
