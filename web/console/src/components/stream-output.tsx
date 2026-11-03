"use client";

import {
  Conversation,
  ConversationContent,
  ConversationScrollButton,
} from "@/components/ai-elements/conversation";
import { cn } from "@/lib/utils";

export type StreamLine = {
  key: string | number;
  text: string;
  className?: string;
};

type StreamOutputProps = {
  lines: readonly StreamLine[];
  className?: string;
};

export function StreamOutput({ lines, className }: StreamOutputProps) {
  return (
    <Conversation
      className={cn(
        "flex max-h-[70dvh] min-h-40 flex-col rounded-lg bg-muted/40 font-mono text-xs",
        className,
      )}
    >
      <ConversationContent className="gap-0 p-3">
        {lines.map((line) => (
          <div
            key={line.key}
            className={cn(
              "stream-line animate-in fade-in whitespace-pre-wrap break-all motion-reduce:animate-none",
              line.className,
            )}
          >
            {line.text}
          </div>
        ))}
      </ConversationContent>
      <ConversationScrollButton aria-label="Jump to latest" />
    </Conversation>
  );
}
