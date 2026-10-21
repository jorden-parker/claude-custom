"use client";

import { useEffect, useState } from "react";
import { parseReviewEvent } from "@/lib/review-event";
import { applyEvent, initialReviewState, type ReviewState } from "@/lib/review-state";
import { ReviewBody } from "./review-body";

const SECOND_MS = 1000;

export function ReviewView({ id }: { id: string }) {
  const [state, setState] = useState<ReviewState>(initialReviewState);
  const [elapsedSeconds, setElapsedSeconds] = useState(0);

  useEffect(() => {
    const source = new EventSource(`/api/reviews/${encodeURIComponent(id)}/events`);
    source.onmessage = (message: MessageEvent<string>) => {
      const event = parseReviewEvent(message.data);
      if (!event) {
        return;
      }
      const eventId = message.lastEventId ? Number(message.lastEventId) : undefined;
      setState((previous) => applyEvent(previous, event, eventId));
      if (event.kind === "end") {
        source.close();
      }
    };
    return () => source.close();
  }, [id]);

  useEffect(() => {
    if (state.ended) {
      return;
    }
    const timer = setInterval(() => setElapsedSeconds((seconds) => seconds + 1), SECOND_MS);
    return () => clearInterval(timer);
  }, [state.ended]);

  return <ReviewBody state={state} elapsedSeconds={elapsedSeconds} />;
}
