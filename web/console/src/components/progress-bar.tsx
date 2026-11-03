import { Progress } from "@/components/ui/progress";

type ProgressBarProps = {
  percent: number;
  phase: string | null;
  text: string;
};

export function ProgressBar({ percent, phase, text }: ProgressBarProps) {
  const pulse = percent >= 100 ? "" : "animate-pulse motion-reduce:animate-none";
  return (
    <div className="flex flex-col gap-2">
      <Progress value={percent} indicatorClassName={pulse} />
      <p className="flex flex-wrap items-baseline gap-2 font-mono text-xs text-muted-foreground">
        {phase === null ? null : <span className="font-sans text-sm font-medium text-foreground">{phase}</span>}
        <span>{text}</span>
      </p>
    </div>
  );
}
