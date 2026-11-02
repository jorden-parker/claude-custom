import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { parseArgs } from "node:util";
import { mockSystemPrompt } from "../src/lib/mock-spike/catalog.ts";
import {
  isPatchLine,
  scoreReply,
  type ReplyScore,
} from "../src/lib/mock-spike/score.ts";

const DEFAULT_BASE_URL = "http://localhost:11434";
const DEFAULT_RUNS = 3;
const MAX_REPLY_TOKENS = 2000;
const SOUND_PATCH_SHARE = 0.9;
const SOUND_VALID_SHARE = 0.8;
const REPAIRABLE_VALID_SHARE = 0.5;
const NANOS_PER_SECOND = 1e9;
const RUN_MARKER = "=== run ";

const BRIEFS: Record<string, string> = {
  pricing:
    "A pricing section with three tiers (Free, Pro, Team), each with a price, three feature lines and a call to action.",
  settings:
    "A settings form with name and email fields, a notifications section with a short explanation, and Save and Cancel buttons.",
  dashboard:
    "A dashboard header with a page title, a search field, and three status badges for builds, deploys and alerts.",
};

type Options = {
  model: string;
  baseUrl: string;
  runs: number;
  out: string;
  briefs: string[];
};

type RunResult = {
  brief: string;
  run: number;
  score: ReplyScore;
  firstPatchSeconds: number | null;
  totalSeconds: number;
  tokensPerSecond: number | null;
  reply: string;
};

type ChatChunk = {
  message?: { content?: string };
  done?: boolean;
  eval_count?: number;
  eval_duration?: number;
};

function usage(): never {
  console.error(
    "usage: mock-spike --model M [--base-url URL] [--runs N] [--out FILE] [--brief NAME]...",
  );
  process.exit(2);
}

function parseOptions(argv: string[]): Options {
  const { values } = parseArgs({
    args: argv,
    strict: true,
    options: {
      model: { type: "string" },
      "base-url": { type: "string", default: DEFAULT_BASE_URL },
      runs: { type: "string", default: String(DEFAULT_RUNS) },
      out: { type: "string" },
      brief: { type: "string", multiple: true, default: [] },
    },
  });
  if (!values.model) usage();
  return {
    model: values.model,
    baseUrl: values["base-url"].replace(/\/$/, ""),
    runs: parseRuns(values.runs),
    out: values.out ?? defaultOutPath(values.model),
    briefs: checkBriefs(values.brief),
  };
}

function parseRuns(value: string): number {
  const runs = Number(value);
  if (!Number.isInteger(runs) || runs < 1) usage();
  return runs;
}

function checkBriefs(briefs: string[]): string[] {
  if (briefs.length === 0) return Object.keys(BRIEFS);
  const unknown = briefs.find((brief) => !(brief in BRIEFS));
  if (unknown === undefined) return briefs;
  console.error(
    `mock-spike: unknown brief ${unknown}; known: ${Object.keys(BRIEFS).join(", ")}`,
  );
  process.exit(2);
}

function defaultOutPath(model: string): string {
  const stamp = new Date()
    .toISOString()
    .replace(/[-:]/g, "")
    .replace(/\..*/, "");
  const safeModel = model.replace(/[^A-Za-z0-9.-]+/g, "_");
  return path.join(
    os.homedir(),
    "bench-results",
    `mock-spike-${safeModel}-${stamp}.json`,
  );
}

async function streamChat(
  options: Options,
  brief: string,
): Promise<{
  reply: string;
  firstPatchSeconds: number | null;
  totalSeconds: number;
  tokensPerSecond: number | null;
}> {
  const started = process.hrtime.bigint();
  const body = await requestChat(options, brief);
  let reply = "";
  let printed = 0;
  let firstPatchSeconds: number | null = null;
  let tokensPerSecond: number | null = null;
  for await (const chunk of chatChunks(body)) {
    reply += chunk.message?.content ?? "";
    printed = printCompleteLines(reply, printed);
    if (firstPatchSeconds === null && replyHasPatch(reply)) {
      firstPatchSeconds = secondsSince(started);
    }
    tokensPerSecond = tokensPerSecondOf(chunk) ?? tokensPerSecond;
  }
  printCompleteLines(reply + "\n", printed);
  return {
    reply,
    firstPatchSeconds,
    totalSeconds: secondsSince(started),
    tokensPerSecond,
  };
}

async function requestChat(
  options: Options,
  brief: string,
): Promise<ReadableStream<Uint8Array>> {
  const response = await fetch(`${options.baseUrl}/api/chat`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      model: options.model,
      stream: true,
      think: false,
      options: { num_predict: MAX_REPLY_TOKENS },
      messages: [
        { role: "system", content: mockSystemPrompt() },
        { role: "user", content: BRIEFS[brief] },
      ],
    }),
  });
  if (!response.ok || !response.body) {
    const detail = (await response.text()).trim();
    throw new Error(
      `${options.baseUrl}/api/chat answered ${response.status}: ${detail}`,
    );
  }
  return response.body;
}

async function* chatChunks(
  body: ReadableStream<Uint8Array>,
): AsyncGenerator<ChatChunk> {
  const decoder = new TextDecoder();
  const reader = body.getReader();
  let pending = "";
  for (;;) {
    const { done, value } = await reader.read();
    if (done) return;
    pending += decoder.decode(value, { stream: true });
    const lines = pending.split("\n");
    pending = lines.pop() ?? "";
    for (const line of lines.filter((line) => line.trim())) {
      yield JSON.parse(line) as ChatChunk;
    }
  }
}

function printCompleteLines(reply: string, printed: number): number {
  const end = reply.lastIndexOf("\n");
  if (end < printed) return printed;
  for (const line of reply.slice(printed, end).split("\n")) {
    if (line.trim()) console.log(line);
  }
  return end + 1;
}

function replyHasPatch(reply: string): boolean {
  return reply
    .split("\n")
    .slice(0, -1)
    .some((line) => isPatchLine(line.trim()));
}

function secondsSince(started: bigint): number {
  return Number(process.hrtime.bigint() - started) / NANOS_PER_SECOND;
}

function tokensPerSecondOf(chunk: ChatChunk): number | null {
  if (!chunk.done || !chunk.eval_count || !chunk.eval_duration) return null;
  return chunk.eval_count / (chunk.eval_duration / NANOS_PER_SECOND);
}

function seconds(value: number | null): string {
  return value === null ? "none" : `${value.toFixed(1)}s`;
}

function describeScore(score: ReplyScore): string {
  const problem = score.valid ? "" : ` (${score.issue ?? score.propIssue})`;
  const unknown = score.unknownTypes.length
    ? ` unknown=${score.unknownTypes.join(",")}`
    : "";
  return (
    `patches ${score.patches}/${score.lines} lines, ${score.elements} elements,` +
    ` valid ${score.valid ? "yes" : "no"}${problem}${unknown}`
  );
}

function describeTiming(result: RunResult): string {
  const speed =
    result.tokensPerSecond === null
      ? ""
      : ` ${result.tokensPerSecond.toFixed(0)} tok/s`;
  return `first patch ${seconds(result.firstPatchSeconds)}, total ${result.totalSeconds.toFixed(1)}s${speed}`;
}

function formatRun(result: RunResult, total: number, index: number): string {
  return `run ${index}/${total} ${result.brief}: ${describeScore(result.score)}, ${describeTiming(result)}`;
}

function share(values: number[]): number {
  return values.length
    ? values.reduce((sum, value) => sum + value, 0) / values.length
    : 0;
}

function median(values: number[]): number | null {
  if (values.length === 0) return null;
  const sorted = [...values].sort((left, right) => left - right);
  return sorted[Math.floor(sorted.length / 2)];
}

function verdict(patchShare: number, validShare: number): string {
  if (patchShare >= SOUND_PATCH_SHARE && validShare >= SOUND_VALID_SHARE)
    return "sound";
  if (validShare >= REPAIRABLE_VALID_SHARE) return "repairable";
  return "poor";
}

function summarise(results: RunResult[]) {
  const patchShare = share(
    results.map((result) =>
      result.score.lines ? result.score.patches / result.score.lines : 0,
    ),
  );
  const validShare = share(
    results.map((result) => (result.score.valid ? 1 : 0)),
  );
  const firstPatch = median(
    results.flatMap((result) =>
      result.firstPatchSeconds === null ? [] : [result.firstPatchSeconds],
    ),
  );
  return {
    patchShare,
    validShare,
    firstPatchSeconds: firstPatch,
    verdict: verdict(patchShare, validShare),
  };
}

async function main() {
  const options = parseOptions(process.argv.slice(2));
  const total = options.briefs.length * options.runs;
  const results: RunResult[] = [];
  console.log(
    `mock-spike: ${options.model} at ${options.baseUrl}, ${total} runs, prompt ${mockSystemPrompt().length} chars`,
  );
  for (const brief of options.briefs) {
    for (let run = 1; run <= options.runs; run += 1) {
      console.log(`${RUN_MARKER}${results.length + 1}/${total} ${brief}`);
      const streamed = await streamChat(options, brief);
      const result: RunResult = {
        brief,
        run,
        score: scoreReply(streamed.reply),
        ...streamed,
      };
      results.push(result);
      console.log(formatRun(result, total, results.length));
    }
  }
  const summary = summarise(results);
  fs.mkdirSync(path.dirname(options.out), { recursive: true });
  fs.writeFileSync(
    options.out,
    JSON.stringify(
      { model: options.model, baseUrl: options.baseUrl, summary, results },
      null,
      2,
    ) + "\n",
  );
  console.log(
    `summary: patch lines ${(summary.patchShare * 100).toFixed(0)}%, valid specs ${(summary.validShare * 100).toFixed(0)}%, median first patch ${seconds(summary.firstPatchSeconds)}`,
  );
  console.log(`verdict: ${summary.verdict}`);
  console.log(`saved: ${options.out}`);
}

main().catch((error: Error) => {
  console.error(`mock-spike: ${error.message}`);
  process.exit(1);
});
