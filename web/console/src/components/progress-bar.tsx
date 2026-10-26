type ProgressBarProps = {
  percent: number;
  phase: string | null;
  text: string;
};

export function ProgressBar({ percent, phase, text }: ProgressBarProps) {
  const pulse = percent >= 100 ? "" : "animate-pulse";
  return (
    <div className="flex flex-col gap-2">
      <div className="h-2 w-full overflow-hidden rounded-full bg-muted">
        <div
          className={`h-full rounded-full bg-blue-500 transition-[width] duration-300 ease-out ${pulse}`}
          style={{ width: `${percent}%` }}
        />
      </div>
      <p className="flex flex-wrap items-baseline gap-2 font-mono text-xs text-muted-foreground">
        {phase === null ? null : <span className="font-sans text-sm font-medium text-foreground">{phase}</span>}
        <span>{text}</span>
      </p>
    </div>
  );
}
