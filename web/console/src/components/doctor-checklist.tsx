"use client";

import { AlertTriangle, CheckCircle2, Loader2, XCircle } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { useRunStream } from "@/components/run-view";
import { checksFromLines, doctorSummary, type DoctorCheck, type DoctorLevel } from "@/lib/doctor-checks";

const ROW_DELAY_MS = 40;

const levelIconClass: Record<DoctorLevel, string> = {
  ok: "text-emerald-600",
  warn: "text-amber-500",
  fail: "text-red-500",
};

type DoctorChecklistProps = {
  checks: readonly DoctorCheck[];
  other: readonly string[];
  running: boolean;
};

export function DoctorChecklist({ checks, other, running }: DoctorChecklistProps) {
  const summary = doctorSummary(checks);
  return (
    <div className="flex flex-col gap-3">
      {checks.length === 0 ? null : (
        <Badge variant="outline" className="w-fit">
          {`${summary.ok} ok · ${summary.warn} warn · ${summary.fail} fail`}
        </Badge>
      )}
      <ul className="flex flex-col gap-1.5">
        {checks.map((check, index) => (
          <li
            key={`${index}-${check.text}`}
            data-level={check.level}
            className="flex items-start gap-2 text-sm animate-in fade-in slide-in-from-left-2"
            style={{ animationDelay: `${index * ROW_DELAY_MS}ms` }}
          >
            <LevelIcon level={check.level} />
            <span className="min-w-0 break-words">{check.text}</span>
          </li>
        ))}
        {running ? (
          <li className="flex items-center gap-2 text-sm text-muted-foreground">
            <Loader2 className="size-4 animate-spin" />
            checking…
          </li>
        ) : null}
      </ul>
      {other.map((line, index) => (
        <p key={index} className="font-mono text-xs text-muted-foreground">
          {line}
        </p>
      ))}
    </div>
  );
}

function LevelIcon({ level }: { level: DoctorLevel }) {
  const className = `mt-0.5 size-4 shrink-0 ${levelIconClass[level]}`;
  if (level === "ok") {
    return <CheckCircle2 className={className} />;
  }
  if (level === "warn") {
    return <AlertTriangle className={className} />;
  }
  return <XCircle className={className} />;
}

export function DoctorRunChecklist({ id }: { id: string }) {
  const state = useRunStream(id);
  const output = checksFromLines(state.lines.map((line) => line.text));
  return <DoctorChecklist checks={output.checks} other={output.other} running={state.ended === null} />;
}
