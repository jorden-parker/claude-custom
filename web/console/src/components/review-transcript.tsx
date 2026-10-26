import { ChevronDownIcon } from "lucide-react";
import type { ReactNode } from "react";
import { Badge } from "@/components/ui/badge";
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from "@/components/ui/collapsible";
import type { FileView, ReviewState } from "@/lib/review-state";
import type { TranscriptAttempt, TranscriptEntry } from "@/lib/review-transcript";

const EMPTY_MESSAGE =
  "This review has no transcript. It was recorded before transcripts were logged.";
const PLAIN_TEXT_CLASSES =
  "max-h-96 overflow-auto whitespace-pre-wrap font-mono text-xs [overflow-wrap:anywhere]";

export function ReviewTranscript({ state }: { state: ReviewState }) {
  if (state.transcript.length === 0) {
    return <p className="text-sm text-muted-foreground">{EMPTY_MESSAGE}</p>;
  }
  return (
    <div className="flex min-w-0 flex-col gap-6">
      {state.transcript.map((entry) => (
        <TranscriptSection key={`${entry.scope}:${entry.index ?? "summary"}`} entry={entry} files={state.files} />
      ))}
    </div>
  );
}

function TranscriptSection({ entry, files }: { entry: TranscriptEntry; files: FileView[] }) {
  return (
    <section className="flex min-w-0 flex-col gap-3">
      <h3 className="break-all text-sm font-medium">{headingOf(entry, files)}</h3>
      {entry.attempts.map((attempt) => (
        <AttemptView key={attempt.attempt} attempt={attempt} />
      ))}
    </section>
  );
}

function AttemptView({ attempt }: { attempt: TranscriptAttempt }) {
  const isRetry = attempt.attempt > 1;
  return (
    <div className="flex min-w-0 flex-col gap-3">
      {isRetry ? <Badge variant="outline" className="w-fit">retry</Badge> : null}
      <TranscriptBlock label="Sent to model">
        <PromptCollapsible label="System prompt" text={attempt.system} />
        <PromptCollapsible label={`Prompt · ${formatCount(attempt.user.length)} chars`} text={attempt.user} />
      </TranscriptBlock>
      <TranscriptBlock label="Model reply">
        <div className="rounded-md border bg-muted/30 p-3">
          <ReplyText attempt={attempt} />
        </div>
      </TranscriptBlock>
    </div>
  );
}

function TranscriptBlock({ label, children }: { label: string; children: ReactNode }) {
  return (
    <div className="flex min-w-0 flex-col gap-2">
      <p className="text-xs font-medium text-muted-foreground">{label}</p>
      {children}
    </div>
  );
}

function PromptCollapsible({ label, text }: { label: string; text: string }) {
  return (
    <Collapsible>
      <CollapsibleTrigger className="group flex items-center gap-2 text-xs font-medium">
        <ChevronDownIcon className="size-4 shrink-0 transition-transform group-data-[panel-open]:rotate-180" />
        {label}
      </CollapsibleTrigger>
      <CollapsibleContent className="pt-2" keepMounted>
        <pre className={PLAIN_TEXT_CLASSES}>{text}</pre>
      </CollapsibleContent>
    </Collapsible>
  );
}

function ReplyText({ attempt }: { attempt: TranscriptAttempt }) {
  if (attempt.reply === "" && !attempt.done) {
    return (
      <p className="text-xs text-muted-foreground">
        waiting for the first token
        <Caret />
      </p>
    );
  }
  return (
    <pre className={PLAIN_TEXT_CLASSES}>
      {attempt.reply}
      {attempt.done ? null : <Caret />}
    </pre>
  );
}

function Caret() {
  return (
    <span
      data-slot="transcript-caret"
      aria-hidden="true"
      className="ml-0.5 inline-block h-3 w-1.5 animate-pulse bg-foreground align-middle motion-reduce:animate-none"
    />
  );
}

function headingOf(entry: TranscriptEntry, files: FileView[]): string {
  if (entry.scope === "summary") {
    return "Summary";
  }
  const file = files.find((candidate) => candidate.index === entry.index);
  return `[${entry.index}/${file?.total ?? 0}] ${entry.path}`;
}

function formatCount(count: number): string {
  return count.toLocaleString("en-US");
}
