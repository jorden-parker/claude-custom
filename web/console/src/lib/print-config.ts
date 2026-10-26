export type ConfigEntry = { key: string; value: string };

const KEY_SEPARATOR = ": ";

export function parsePrintConfig(stdout: string): ConfigEntry[] {
  const entries: ConfigEntry[] = [];
  for (const line of stdout.split("\n")) {
    const separatorAt = line.indexOf(KEY_SEPARATOR);
    if (separatorAt === -1) {
      continue;
    }
    entries.push({
      key: line.slice(0, separatorAt),
      value: line.slice(separatorAt + KEY_SEPARATOR.length),
    });
  }
  return entries;
}
