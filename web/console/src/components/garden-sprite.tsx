import { cn } from "cn";

export function GardenSprite({ className }: { className?: string }) {
  return (
    <svg
      viewBox="0 0 48 48"
      aria-hidden="true"
      focusable="false"
      className={cn("size-6 motion-safe:animate-sprout-bob", className)}
    >
      <ellipse cx="24" cy="42" rx="10" ry="3.5" className="fill-secondary stroke-ink" strokeWidth="2" />
      <path d="M24 41V23" fill="none" className="stroke-ink" strokeWidth="2.5" strokeLinecap="round" />
      <path
        d="M24 25C23 15 16 9 7 10c0 10 6 17 17 15Z"
        className="fill-primary stroke-ink"
        strokeWidth="2"
        strokeLinejoin="round"
      />
      <path
        d="M24 21c0-9 6-14 16-13 0 9-6 14-16 13Z"
        className="fill-accent stroke-ink"
        strokeWidth="2"
        strokeLinejoin="round"
      />
    </svg>
  );
}
