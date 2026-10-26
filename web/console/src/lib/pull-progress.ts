const PERCENT = /(\d{1,3})%/g;
const PHASES = new Set(["pulling", "verifying", "writing", "success"]);

export function percentFrom(text: string): number | null {
  const matches = [...text.matchAll(PERCENT)];
  const last = matches.at(-1);
  if (last === undefined) {
    return null;
  }
  return Math.min(Number(last[1]), 100);
}

export function phaseFrom(text: string): string | null {
  const leadingWord = text.trim().split(/\s/)[0];
  return PHASES.has(leadingWord) ? leadingWord : null;
}
