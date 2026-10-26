import fs from "node:fs";
import { parseRunEvents } from "./run-event";
import { listRuns, resolveRunFileIn, runsDir } from "./run-log";

export type SpeedCheckFailure = { id: string; startedAt: string; stoppedLine: string | null };

const SPEED_CHECK = "speed-check";
const STOPPED_PREFIX = "speed-check stopped:";

export function failedSpeedChecks(directory: string = runsDir()): SpeedCheckFailure[] {
  return listRuns(directory)
    .filter((run) => run.command === SPEED_CHECK && run.status === "failed")
    .map((run) => ({ id: run.id, startedAt: run.startedAt, stoppedLine: stoppedLineOf(directory, run.id) }));
}

function stoppedLineOf(directory: string, id: string): string | null {
  const file = resolveRunFileIn(directory, id);
  if (file === null) {
    return null;
  }
  const stopped = parseRunEvents(fs.readFileSync(file, "utf8")).find(
    (event) => event.kind === "line" && typeof event.text === "string" && event.text.startsWith(STOPPED_PREFIX),
  );
  return typeof stopped?.text === "string" ? stopped.text : null;
}
