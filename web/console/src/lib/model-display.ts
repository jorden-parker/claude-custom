export type FileState = "pinned" | "mismatch" | "candidate" | "orphan" | "partial";

export type SizeStatus = {
  size: string;
  model: string | null;
  file: string | null;
  state: FileState | null;
};

export type WeightFile = {
  name: string;
  state: FileState;
  size: string | null;
  bytes: number;
};

export type SizeState = "installed" | "missing" | "partial" | "mismatch";

export function sizeStateOf(size: SizeStatus): SizeState {
  if (size.state === "pinned") {
    return "installed";
  }
  if (size.state === "mismatch" || size.state === "partial") {
    return size.state;
  }
  return "missing";
}

export function namesToRemove(files: readonly WeightFile[]): string[] {
  return files.map((file) => file.name);
}

export function gigabytes(bytes: number): string {
  return (bytes / 1e9).toFixed(1);
}

export function totalBytes(files: readonly WeightFile[]): number {
  return files.reduce((total, file) => total + file.bytes, 0);
}
