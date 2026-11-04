import type { CommandParams } from "./console-commands";

export type FixAction = { command: string; params: CommandParams; label: string };

const MODEL_UPGRADE_FIX = /^bin\/model-upgrade ([A-Za-z0-9][A-Za-z0-9._-]*)$/;
const SERVER_APPLY_FIX = "claude-custom agent -apply";

export function fixActionFor(fix: string): FixAction | null {
  const upgrade = MODEL_UPGRADE_FIX.exec(fix);
  if (upgrade !== null) {
    return { command: "model-upgrade", params: { size: upgrade[1] }, label: `Upgrade ${upgrade[1]}` };
  }
  if (fix === SERVER_APPLY_FIX) {
    return { command: "server-apply", params: {}, label: "Apply recommended settings" };
  }
  return null;
}
