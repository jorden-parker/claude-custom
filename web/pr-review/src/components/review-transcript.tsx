import { ChevronDownIcon } from "lucide-react";
import type { ReactNode } from "react";
import { Badge } from "@/components/ui/badge";
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from "@/components/ui/collapsible";
import { Message, MessageContent } from "@/components/ui/message";
import type { TranscriptAttempt, TranscriptEntry } from "@/lib/review-transcript";

const EMPTY_MESSAGE =
  "This review has no transcript. It was recorded before transcripts were logged.";
const PLAIN_TEXT_CLASSES =
  "max-h-96 overflow-auto whitespace-pre-wrap font-mono text-xs [overflow-wrap:anywhere]";

export function ReviewTranscript({ entries }: { entries: TranscriptEntry[] }) {
  if (entries.length === 0) {
    return <p className="text-sm text-muted-foreground">{EMPTY_MESSAGE}</p>;
  }
  const fileTotal = entries.filter((entry) => entry.scope === "file").length;
  return (
    <div className="flex min-w-0 flex-col gap-6">
      {entries.map((entry) => (
        <TranscriptSection key={`${entry.scope}:${entry.index ?? "summary"}`} entry={entry} fileTotal={fileTotal} />
      ))}
    </div>
  );
}

function TranscriptSection({ entry, fileTotal }: { entry: TranscriptEntry; fileTotal: number }) {
  return (
    <section className="flex min-w-0 flex-col gap-3">
      <h3 className="break-all text-sm font-medium">{headingOf(entry, fileTotal)}</h3>
      {entry.attempts.map((attempt) => (
        <AttemptView key={attempt.attempt} attempt={attempt} />
      ))}
    </section>
  );
}

function AttemptView({ attempt }: { attempt: TranscriptAttempt }) {
  const isRetry = attempt.attempt > 1;
  return (
    <div className="flex min-w-0 flex-col gap-2">
      {isRetry ? <Badge variant="outline" className="w-fit">retry</Badge> : null}
      <Message align="end">
        <MessageContent className="min-w-0">
          <PromptCollapsible label="System prompt">
            <pre className={PLAIN_TEXT_CLASSES}>{attempt.system}</pre>
          </PromptCollapsible>
          <PromptCollapsible label={`Prompt · ${formatCount(attempt.user.length)} chars`}>
            <pre className={PLAIN_TEXT_CLASSES}>{attempt.user}</pre>
          </PromptCollapsible>
        </MessageContent>
      </Message>
      <Message>
        <MessageContent className="min-w-0">
          <ReplyText attempt={attempt} />
        </MessageContent>
      </Message>
    </div>
  );
}

function PromptCollapsible({ label, children }: { label: string; children: ReactNode }) {
  return (
    <Collapsible>
      <CollapsibleTrigger className="group flex items-center gap-2 text-xs font-medium">
        <ChevronDownIcon className="size-4 shrink-0 transition-transform group-data-[panel-open]:rotate-180" />
        {label}
      </CollapsibleTrigger>
      <CollapsibleContent className="pt-2" keepMounted>
        {children}
      </CollapsibleContent>
    </Collapsible>
  );
}

function ReplyText({ attempt }: { attempt: TranscriptAttempt }) {
  const waiting = attempt.reply === "" && !attempt.done;
  return (
    <>
      <pre className={PLAIN_TEXT_CLASSES}>{attempt.reply}</pre>
      {waiting ? <p className="text-xs text-muted-foreground">waiting for the first token</p> : null}
      {attempt.done ? null : <Caret />}
    </>
  );
}

function Caret() {
  return (
    <span
      data-slot="transcript-caret"
      aria-hidden="true"
      className="inline-block h-4 w-2 animate-pulse bg-foreground motion-reduce:animate-none"
    />
  );
}

function headingOf(entry: TranscriptEntry, fileTotal: number): string {
  if (entry.scope === "summary") {
    return "Summary";
  }
  return `[${entry.index}/${fileTotal}] ${entry.path}`;
}

function formatCount(count: number): string {
  return count.toLocaleString("en-US");
}
