export type SizeStatus = {
  size: string;
  model: string | null;
  base: string | null;
  installed: boolean;
  class: string | null;
};

export type InstalledModel = {
  name: string;
  class: string;
  bytes: number;
  loaded: boolean;
};

export type SizeState = "installed" | "missing" | "mismatch";

export function sizeStateOf(size: SizeStatus): SizeState {
  if (!size.installed) {
    return "missing";
  }
  return size.class === "mismatch" ? "mismatch" : "installed";
}

export function namesToRemove(models: readonly InstalledModel[]): string[] {
  return models.map((model) => model.name);
}

export function gigabytes(bytes: number): string {
  return (bytes / 1e9).toFixed(1);
}

export function totalBytes(models: readonly InstalledModel[]): number {
  return models.reduce((total, model) => total + model.bytes, 0);
}
