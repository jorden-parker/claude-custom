"use client";

import {
  Conversation,
  ConversationContent,
  ConversationScrollButton,
} from "@/components/ai-elements/conversation";
import { cn } from "@/lib/utils";

type StreamLine = {
  key: string | number;
  text: string;
  className?: string;
};

type StreamOutputProps = {
  lines: readonly StreamLine[];
  live?: boolean;
  className?: string;
};

export function StreamOutput({ lines, live, className }: StreamOutputProps) {
  return (
    <Conversation
      className={cn(
        "flex min-h-40 flex-col rounded-lg bg-muted/40 font-mono text-xs",
        live && "max-h-[calc(100dvh-6rem)]",
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
