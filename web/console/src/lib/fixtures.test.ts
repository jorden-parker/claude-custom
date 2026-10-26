import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { parseEvents } from "./reviews";
import { reduceEvents } from "./review-state";

const fixturesDir = fileURLToPath(new URL("../../fixtures", import.meta.url));

function readFixture(name: string): string {
  return fs.readFileSync(path.join(fixturesDir, name), "utf8");
}

function fixtureNames(): string[] {
  return fs.readdirSync(fixturesDir).filter((name) => name.endsWith(".jsonl"));
}

function nonBlankLines(text: string): string[] {
  return text.split("\n").filter((line) => line.trim() !== "");
}

describe("review fixtures", () => {
  it.each(fixtureNames())("%s parses every line and reduces without error", (name) => {
    const text = readFixture(name);
    const events = parseEvents(text);

    expect(events).toHaveLength(nonBlankLines(text).length);
    expect(() => reduceEvents(events)).not.toThrow();
  });

  it("has a 25-file review", () => {
    const state = reduceEvents(parseEvents(readFixture("20261020-100000-main..big.jsonl")));

    expect(state.files).toHaveLength(25);
    expect(state.verdict?.verdict).toBe("APPROVE WITH COMMENTS");
  });

  it("has an error review and a stopped review", () => {
    const failed = reduceEvents(parseEvents(readFixture("20261020-110000-pr-42.jsonl")));
    const stopped = reduceEvents(parseEvents(readFixture("20261020-120000-pr-43.jsonl")));

    expect(failed.error).toContain("Connection refused");
    expect(failed.header.status).toBe("error");
    expect(stopped.ended).toBe(false);
  });
});
