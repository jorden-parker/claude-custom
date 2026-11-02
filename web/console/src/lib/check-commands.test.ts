import { describe, expect, it } from "vitest";
import { CHECK_COMMANDS } from "./check-commands";
import { findCommand } from "./console-commands";

describe("check commands", () => {
  it("maps every check to a registered console command", () => {
    for (const check of CHECK_COMMANDS) {
      expect(findCommand(check.command), check.command).toBeDefined();
    }
  });

  it("lists each command once", () => {
    const names = CHECK_COMMANDS.map((check) => check.command);
    expect(new Set(names).size).toBe(names.length);
  });

  it("marks only the size-bound checks as needing a size", () => {
    const sized = CHECK_COMMANDS.filter((check) => check.needsSize).map((check) => check.command);
    expect(sized).toEqual(["doctor", "qwen-doctor"]);
  });
});
