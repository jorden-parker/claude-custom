import { spawn } from "node:child_process";
import { randomBytes } from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const appDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const fixturesDir = path.join(appDir, "fixtures");
const TEMPLATE_SUFFIX = ".template.jsonl";
const STOPPED_LOG = "20261020-120000-pr-43.jsonl";
const STOPPED_AGE_MS = 20 * 60 * 1000;
const LIVE_LOG_SUFFIX = "-pr-44.jsonl";
const SECONDS_TO_MS = 1000;

const args = process.argv.slice(2);
const serve = args.includes("--serve");
const speed = Number(args[args.indexOf("--speed") + 1]) || 1;
const port = process.env.PORT || "8799";
const token = randomBytes(24).toString("hex");

function fixtureNames() {
  return fs
    .readdirSync(fixturesDir)
    .filter((name) => name.endsWith(".jsonl") && !name.endsWith(TEMPLATE_SUFFIX));
}

function liveLogName(date) {
  const stamp = date.toISOString().replace(/[-:]/g, "").slice(0, 15).replace("T", "-");
  return `${stamp}${LIVE_LOG_SUFFIX}`;
}

function makeDemoDir() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "pr-review-demo-"));
  for (const name of fixtureNames()) {
    fs.copyFileSync(path.join(fixturesDir, name), path.join(dir, name));
  }
  const old = new Date(Date.now() - STOPPED_AGE_MS);
  fs.utimesSync(path.join(dir, STOPPED_LOG), old, old);
  return dir;
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function replayLive(dir) {
  const lines = fs
    .readFileSync(path.join(fixturesDir, "live.template.jsonl"), "utf8")
    .split("\n")
    .filter((line) => line.trim() !== "");
  const target = path.join(dir, liveLogName(new Date()));
  fs.writeFileSync(target, "");
  let previous = 0;
  for (const line of lines) {
    const { t } = JSON.parse(line);
    await sleep(((t - previous) * SECONDS_TO_MS) / speed);
    previous = t;
    fs.appendFileSync(target, `${line}\n`);
  }
}

function startServer(dir) {
  const server = spawn(path.join(appDir, "node_modules/.bin/next"), ["start", "-H", "127.0.0.1", "-p", port], {
    cwd: appDir,
    env: { ...process.env, PR_REVIEW_LOG_DIR: dir, PR_REVIEW_TOKEN: token },
    stdio: "inherit",
  });
  process.on("exit", () => server.kill());
  process.on("SIGINT", () => process.exit(130));
  process.on("SIGTERM", () => process.exit(143));
  return server;
}

const dir = makeDemoDir();
console.log(dir);
const replay = replayLive(dir).catch((error) => console.error(error));

if (serve) {
  console.log(`serving on http://127.0.0.1:${port}/?token=${token}`);
  const server = startServer(dir);
  await new Promise((resolve) => server.once("exit", resolve));
} else {
  await replay;
}
