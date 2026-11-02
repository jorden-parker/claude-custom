import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { createSpecStreamCompiler, type Spec } from "@json-render/core";
import { isPatchLine, scoreReply, type ReplyScore } from "./score.ts";

export type MockSpec = Spec;

export type MockRun = {
  brief: string;
  run: number;
  score: ReplyScore;
  spec: MockSpec;
};

export type MockSpikeReport = {
  file: string;
  model: string;
  verdict: string;
  runs: MockRun[];
};

type StoredRun = { brief: string; run: number; reply: string };
type StoredReport = {
  model: string;
  summary: { verdict: string };
  results: StoredRun[];
};

const REPORT_PATTERN = /^mock-spike-.*\.json$/;

export function reportsDir(): string {
  return path.join(os.homedir(), "bench-results");
}

function modifiedAt(file: string): number {
  try {
    return fs.statSync(file).mtimeMs;
  } catch {
    return 0;
  }
}

export function listMockSpikeReports(
  directory: string = reportsDir(),
): MockSpikeReport[] {
  return readNames(directory)
    .filter((name) => REPORT_PATTERN.test(name))
    .sort(
      (left, right) =>
        modifiedAt(path.join(directory, right)) -
        modifiedAt(path.join(directory, left)),
    )
    .flatMap((name) => {
      const report = readReport(path.join(directory, name), name);
      return report === null ? [] : [report];
    });
}

function readNames(directory: string): string[] {
  try {
    return fs.readdirSync(directory);
  } catch {
    return [];
  }
}

function readReport(file: string, name: string): MockSpikeReport | null {
  try {
    const stored = JSON.parse(fs.readFileSync(file, "utf8")) as StoredReport;
    if (typeof stored.model !== "string" || !Array.isArray(stored.results))
      return null;
    return {
      file: name,
      model: stored.model,
      verdict: stored.summary?.verdict ?? "unknown",
      runs: stored.results.map(runFromStored),
    };
  } catch {
    return null;
  }
}

function runFromStored(stored: StoredRun): MockRun {
  return {
    brief: stored.brief,
    run: stored.run,
    score: scoreReply(stored.reply),
    spec: specFromReply(stored.reply),
  };
}

export function specFromReply(reply: string): MockSpec {
  const compiler = createSpecStreamCompiler<MockSpec>();
  const patches = reply
    .split("\n")
    .map((line) => line.trim())
    .filter(isPatchLine);
  compiler.push(patches.join("\n") + "\n");
  return compiler.getResult() ?? { root: "", elements: {} };
}
