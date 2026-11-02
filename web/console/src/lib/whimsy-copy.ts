export const WHIMSY_SUBTITLES: readonly string[] = [
  "Everything growing under your garden gate.",
  "A little patch of the garden, tended with care.",
  "Snails are slow, but this patch is coming along.",
  "Fresh sprouts and quiet corners, all in one bed.",
  "Pull up a stool and see what has been growing.",
];

export const WHIMSY_EMPTY_LINES: readonly string[] = [
  "The beds are quiet for now.",
  "Nothing has sprouted here yet.",
  "The meadow is waiting for its first visitor.",
  "A clean patch of soil, ready for planting.",
];

function hashKey(key: string): number {
  let hash = 5381;
  for (const character of key) {
    hash = (hash * 33 + character.charCodeAt(0)) >>> 0;
  }
  return hash;
}

export function pickStable<T>(items: readonly T[], key: string): T {
  return items[hashKey(key) % items.length];
}

export function subtitleFor(pageKey: string): string {
  return pickStable(WHIMSY_SUBTITLES, pageKey);
}

export function emptyLineFor(pageKey: string): string {
  return pickStable(WHIMSY_EMPTY_LINES, pageKey);
}
