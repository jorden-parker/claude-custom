import { describe, expect, it } from "vitest";
import {
  GH_REPO_PATTERN,
  MAX_LINES,
  bareToolNames,
  isPolicyFile,
  parseLines,
  planLines,
} from "./machine-policy-rules";

const KNOWN_TOOLS = ["Artifact", "CronCreate", "Workflow"];

describe("GH_REPO_PATTERN", () => {
  it.each(["owner/name", "Some-Owner/repo.name_1"])("accepts %s", (repo) => {
    expect(GH_REPO_PATTERN.test(repo)).toBe(true);
  });

  it.each(["owner", "owner/name/extra", "owner name/repo", "-owner/repo"])(
    "rejects %s",
    (repo) => {
      expect(GH_REPO_PATTERN.test(repo)).toBe(false);
    },
  );
});

describe("parseLines for gh-repos", () => {
  it("keeps owner/name lines and reports the others with a reason", () => {
    const parsed = parseLines(
      "gh-repos",
      "acme/web\nacme/*\nacme\n  \nacme/web/extra\n",
    );

    expect(parsed.valid).toEqual(["acme/web"]);
    expect(parsed.invalid).toEqual([
      { line: "acme/*", reason: "expected owner/name" },
      { line: "acme", reason: "expected owner/name" },
      { line: "acme/web/extra", reason: "expected owner/name" },
    ]);
  });

  it("trims each line before checking it", () => {
    expect(parseLines("gh-repos", "  acme/web  \n").valid).toEqual([
      "acme/web",
    ]);
  });

  it("accepts a # line as a comment with no problem", () => {
    const parsed = parseLines("gh-repos", "# repos\n");

    expect(parsed.valid).toEqual(["# repos"]);
    expect(parsed.invalid).toEqual([]);
  });
});

describe("parseLines for enabled-tools", () => {
  it("accepts a bare tool name from the overlay's deny list", () => {
    expect(
      parseLines("enabled-tools", "Artifact\n", KNOWN_TOOLS).valid,
    ).toEqual(["Artifact"]);
  });

  it("rejects a name the overlay's deny list does not hold", () => {
    const parsed = parseLines("enabled-tools", "Bash\n", KNOWN_TOOLS);

    expect(parsed.valid).toEqual([]);
    expect(parsed.invalid).toEqual([
      {
        line: "Bash",
        reason: "not a bare tool name in the overlay's deny list",
      },
    ]);
  });

  it("rejects a scoped rule even when its tool is in the deny list", () => {
    expect(
      parseLines("enabled-tools", "Read(**/dist/**)\n", KNOWN_TOOLS).valid,
    ).toEqual([]);
  });
});

describe("planLines", () => {
  it("writes the lines joined with newlines and a trailing newline", () => {
    expect(planLines("gh-repos", ["acme/web", " acme/api "])).toEqual({
      text: "acme/web\nacme/api\n",
      lines: ["acme/web", "acme/api"],
    });
  });

  it("plans an empty file as empty text", () => {
    expect(planLines("gh-repos", [])).toEqual({ text: "", lines: [] });
  });

  it("throws an error naming the first bad line and why", () => {
    expect(() => planLines("gh-repos", ["acme/web", "acme"])).toThrow(
      "acme: expected owner/name",
    );
  });

  it("throws for an enabled-tools name missing from the deny list", () => {
    expect(() => planLines("enabled-tools", ["Bash"], KNOWN_TOOLS)).toThrow(
      "Bash: not a bare tool name in the overlay's deny list",
    );
  });

  it("caps the number of non-empty lines at MAX_LINES", () => {
    const lines = Array.from(
      { length: MAX_LINES + 1 },
      (_, index) => `acme/repo${index}`,
    );

    expect(() => planLines("gh-repos", lines)).toThrow(
      `at most ${MAX_LINES} lines`,
    );
  });

  it("allows exactly MAX_LINES non-empty lines", () => {
    const lines = Array.from(
      { length: MAX_LINES },
      (_, index) => `acme/repo${index}`,
    );

    expect(planLines("gh-repos", lines).lines).toHaveLength(MAX_LINES);
  });
});

describe("isPolicyFile", () => {
  it.each(["gh-repos", "enabled-tools"])("accepts %s", (name) => {
    expect(isPolicyFile(name)).toBe(true);
  });

  it.each(["fetch-domains", "sandbox-off", "gh-repo", ""])(
    "rejects %s",
    (name) => {
      expect(isPolicyFile(name)).toBe(false);
    },
  );
});

describe("bareToolNames", () => {
  it("keeps only the bare tool names of a deny list", () => {
    expect(bareToolNames(["Artifact", "Read(**/dist/**)", "Workflow"])).toEqual(
      ["Artifact", "Workflow"],
    );
  });
});
