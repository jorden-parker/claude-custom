import fs from "node:fs";
import os from "node:os";
import path from "node:path";

export type RescueReport = { path: string; text: string };

const RESCUE_DIR_NAME = path.join(".claude-ollama", "rescue");
const REPORT_SUFFIX = ".md";

function rescueReportsDir(): string {
  return path.join(os.homedir(), RESCUE_DIR_NAME);
}

export function latestRescueReport(): RescueReport | null {
  const dir = rescueReportsDir();
  if (!fs.existsSync(dir)) {
    return null;
  }
  const newest = fs
    .readdirSync(dir)
    .filter((name) => name.endsWith(REPORT_SUFFIX))
    .sort()
    .at(-1);
  if (newest === undefined) {
    return null;
  }
  const file = path.join(dir, newest);
  return { path: file, text: fs.readFileSync(file, "utf8") };
}
