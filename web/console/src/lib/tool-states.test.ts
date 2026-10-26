import { describe, expect, it } from "vitest";
import {
  assignmentText,
  changedAssignments,
  draftsFrom,
  setPermission,
  type ToolRow,
} from "./tool-states";

const row = (name: string, permission: ToolRow["permission"], disabled = false): ToolRow => ({
  name,
  description: `${name} tool`,
  promptsByDefault: false,
  permission,
  disabled,
});

describe("assignmentText", () => {
  it("writes the bare permission for each mode", () => {
    expect(assignmentText("Bash", "default", false)).toBe("Bash=default");
    expect(assignmentText("Bash", "allow", false)).toBe("Bash=allow");
    expect(assignmentText("Bash", "ask", false)).toBe("Bash=ask");
    expect(assignmentText("Bash", "deny", false)).toBe("Bash=deny");
  });

  it("adds the off suffix to allow and ask", () => {
    expect(assignmentText("WebFetch", "allow", true)).toBe("WebFetch=allow,off");
    expect(assignmentText("WebFetch", "ask", true)).toBe("WebFetch=ask,off");
  });

  it("rejects off with deny or default", () => {
    expect(assignmentText("WebFetch", "deny", true)).toBeNull();
    expect(assignmentText("WebFetch", "default", true)).toBeNull();
  });
});

describe("setPermission", () => {
  it("keeps the off switch for allow and ask", () => {
    expect(setPermission({ permission: "allow", disabled: true }, "ask")).toEqual({
      permission: "ask",
      disabled: true,
    });
  });

  it("clears the off switch for deny and default", () => {
    expect(setPermission({ permission: "allow", disabled: true }, "deny")).toEqual({
      permission: "deny",
      disabled: false,
    });
    expect(setPermission({ permission: "ask", disabled: true }, "default")).toEqual({
      permission: "default",
      disabled: false,
    });
  });
});

describe("draftsFrom", () => {
  it("copies each row's saved state by tool name", () => {
    expect(draftsFrom([row("Bash", "allow", true), row("Read", "default")])).toEqual({
      Bash: { permission: "allow", disabled: true },
      Read: { permission: "default", disabled: false },
    });
  });
});

describe("changedAssignments", () => {
  it("lists only the rows whose draft differs from the saved state", () => {
    const rows = [row("Bash", "allow"), row("WebFetch", "deny"), row("Read", "default")];
    const drafts = {
      Bash: { permission: "allow" as const, disabled: true },
      WebFetch: { permission: "deny" as const, disabled: false },
      Read: { permission: "ask" as const, disabled: false },
    };
    expect(changedAssignments(rows, drafts)).toEqual(["Bash=allow,off", "Read=ask"]);
  });

  it("is empty when nothing changed", () => {
    const rows = [row("Bash", "allow")];
    expect(changedAssignments(rows, draftsFrom(rows))).toEqual([]);
  });
});
