import { describe, expect, it } from "vitest";
import { fixActionFor } from "./fix-actions";

describe("fixActionFor", () => {
  it("maps a model-upgrade fix to the model-upgrade command for that size", () => {
    expect(fixActionFor("bin/model-upgrade 35b")).toEqual({
      command: "model-upgrade",
      params: { size: "35b" },
      label: "Upgrade 35b",
    });
  });

  it("maps the server env fix to the server-apply command", () => {
    expect(fixActionFor("claude-custom agent -apply")).toEqual({
      command: "server-apply",
      params: {},
      label: "Apply recommended settings",
    });
  });

  it("gives null for a fix the console cannot run", () => {
    expect(fixActionFor("claude-ollama github-token push")).toBeNull();
    expect(fixActionFor("bin/model-upgrade 35b --force")).toBeNull();
    expect(fixActionFor("bin/ollama-models pin qwen3-embedding:0.6b")).toBeNull();
  });
});
