import os from "node:os";
import path from "node:path";

export function consoleStateDir(): string {
  return (
    process.env.CLAUDE_CONSOLE_STATE_DIR ||
    path.join(os.homedir(), ".local/share/claude-custom/console")
  );
}
