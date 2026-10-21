const LOCAL_TIME = new Intl.DateTimeFormat("en-US", {
  month: "short",
  day: "numeric",
  hour: "2-digit",
  minute: "2-digit",
  hourCycle: "h23",
});

const MINUTE_MS = 60_000;
const HOUR_MS = 3_600_000;
const DAY_MS = 86_400_000;

export function formatLocalTime(iso: string): string {
  if (iso === "") {
    return "";
  }
  return LOCAL_TIME.format(new Date(iso));
}

export function formatRelative(iso: string, nowMs: number): string {
  if (iso === "") {
    return "";
  }
  const elapsed = nowMs - new Date(iso).getTime();
  if (elapsed < MINUTE_MS) {
    return "just now";
  }
  if (elapsed < HOUR_MS) {
    return `${Math.floor(elapsed / MINUTE_MS)} min ago`;
  }
  if (elapsed < DAY_MS) {
    return `${Math.floor(elapsed / HOUR_MS)} h ago`;
  }
  return `${Math.floor(elapsed / DAY_MS)} d ago`;
}
