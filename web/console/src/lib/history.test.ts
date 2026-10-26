import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import {
  historyDir,
  listHistory,
  loadChange,
  recordChange,
  restoreChange,
} from "./history";

describe("history", () => {
  let stateDir: string;
  let targetDir: string;

  beforeEach(() => {
    stateDir = fs.mkdtempSync(path.join(os.tmpdir(), "history-state-"));
    targetDir = fs.mkdtempSync(path.join(os.tmpdir(), "history-target-"));
    process.env.CLAUDE_CONSOLE_STATE_DIR = stateDir;
    delete process.env.CLAUDE_CUSTOM_HISTORY;
  });

  afterEach(() => {
    delete process.env.CLAUDE_CONSOLE_STATE_DIR;
    delete process.env.CLAUDE_CUSTOM_HISTORY;
    fs.rmSync(stateDir, { recursive: true, force: true });
    fs.rmSync(targetDir, { recursive: true, force: true });
  });

  function settingsPath(name = "settings.json"): string {
    return path.join(targetDir, name);
  }

  function writeChange(path: string, before: string | null, after: string) {
    return recordChange({
      kind: "settings",
      path,
      before,
      after,
      source: "console",
    });
  }

  it("keeps the history folder under the console state dir", () => {
    expect(historyDir()).toBe(path.join(stateDir, "history"));
  });

  it("lists changes newest first and skips bad index lines", () => {
    writeChange(settingsPath(), null, "one");
    writeChange(settingsPath(), "one", "two");
    fs.appendFileSync(path.join(historyDir(), "index.jsonl"), "not json\n");

    const entries = listHistory();

    expect(entries).toHaveLength(2);
    expect(loadChange(entries[0].id)?.after).toBe("two");
  });

  it("returns an empty list when nothing was recorded", () => {
    expect(listHistory()).toEqual([]);
  });

  it("records the first write with a null before and the exact bytes after", () => {
    const entry = writeChange(settingsPath(), null, '{"a":1}\n');

    expect(entry).not.toBeNull();
    expect(entry?.before).toBeNull();
    expect(entry?.source).toBe("console");
    expect(loadChange(entry!.id)).toEqual({
      entry,
      before: null,
      after: '{"a":1}\n',
    });
  });

  it("records both files of a later write with their exact bytes", () => {
    writeChange(settingsPath(), null, "{}");

    const entry = writeChange(settingsPath(), "{}", '{"deny":["WebFetch"]}');

    expect(loadChange(entry!.id)).toEqual({
      entry,
      before: "{}",
      after: '{"deny":["WebFetch"]}',
    });
  });

  it("records nothing when the bytes are unchanged", () => {
    const entry = writeChange(settingsPath(), "same", "same");

    expect(entry).toBeNull();
    expect(listHistory()).toEqual([]);
  });

  it("records nothing when CLAUDE_CUSTOM_HISTORY is off", () => {
    process.env.CLAUDE_CUSTOM_HISTORY = "off";

    expect(writeChange(settingsPath(), null, "{}")).toBeNull();
    expect(fs.existsSync(historyDir())).toBe(false);
  });

  it("writes history files owner-only", () => {
    const entry = writeChange(settingsPath(), null, "{}");

    expect(mode(historyDir())).toBe(0o700);
    expect(mode(path.join(historyDir(), "index.jsonl"))).toBe(0o600);
    expect(mode(path.join(historyDir(), entry!.after))).toBe(0o600);
  });

  it("refuses to record through a symlinked index", () => {
    fs.mkdirSync(historyDir(), { recursive: true, mode: 0o700 });
    const outside = path.join(targetDir, "outside.jsonl");
    fs.writeFileSync(outside, "");
    fs.symlinkSync(outside, path.join(historyDir(), "index.jsonl"));

    expect(() => writeChange(settingsPath(), null, "{}")).toThrow();
    expect(fs.readFileSync(outside, "utf8")).toBe("");
  });

  it("answers loadChange with null for an id that is not in the index", () => {
    expect(loadChange("20261026-093000-settings-beef")).toBeNull();
  });

  it("answers loadChange with null for a malformed id without reading the disk", () => {
    expect(loadChange("../../etc/passwd")).toBeNull();
  });

  it("restores the before bytes and records the restore", () => {
    fs.writeFileSync(settingsPath(), "{}", { mode: 0o600 });
    writeChange(settingsPath(), "{}", '{"deny":["WebFetch"]}');
    fs.writeFileSync(settingsPath(), '{"deny":["WebFetch"]}', { mode: 0o600 });
    const change = listHistory()[0];

    const result = restoreChange(change.id);

    expect(result).toEqual({ ok: true, entry: expect.objectContaining({ source: "console-restore" }) });
    expect(fs.readFileSync(settingsPath(), "utf8")).toBe("{}");
    expect(listHistory()).toHaveLength(2);
    expect(mode(settingsPath())).toBe(0o600);
  });

  it("answers 404 when restoring an unknown id", () => {
    expect(restoreChange("20261026-093000-settings-beef")).toEqual({
      ok: false,
      status: 404,
      message: expect.any(String),
    });
  });

  it("refuses a restore whose change had no before", () => {
    const change = writeChange(settingsPath(), null, "{}");
    fs.writeFileSync(settingsPath(), "{}");

    expect(restoreChange(change!.id)).toEqual({
      ok: false,
      status: 409,
      message: expect.stringContaining("didn't exist"),
    });
  });

  it("refuses a restore into a symlinked target", () => {
    const real = settingsPath("real.json");
    fs.writeFileSync(real, "{}");
    const link = settingsPath("linked.json");
    fs.symlinkSync(real, link);
    const change = writeChange(link, "old", "{}");

    expect(restoreChange(change!.id)).toEqual({
      ok: false,
      status: 409,
      message: expect.stringContaining("symlink"),
    });
    expect(fs.readFileSync(real, "utf8")).toBe("{}");
  });

  it("refuses a restore whose path is not absolute", () => {
    const change = recordChange({ kind: "settings", path: "relative.json", before: "old", after: "new", source: "console" });
    expect(restoreChange(change!.id)).toEqual({
      ok: false,
      status: 409,
      message: expect.stringContaining("absolute"),
    });
  });
});

function mode(file: string): number {
  return fs.statSync(file).mode & 0o777;
}
