"use client";

import { useEffect, useState } from "react";
import { parseReviewEvent } from "@/lib/review-event";
import { applyEvent, initialReviewState, markStopped, type ReviewState } from "@/lib/review-state";
import { ReviewBody } from "./review-body";

const SECOND_MS = 1000;

export function ReviewView({ id, stopped }: { id: string; stopped: boolean }) {
  const [state, setState] = useState<ReviewState>(initialReviewState);
  const [elapsedSeconds, setElapsedSeconds] = useState(0);
  const shown = stopped ? markStopped(state) : state;

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
    if (shown.ended) {
      return;
    }
    const timer = setInterval(() => setElapsedSeconds((seconds) => seconds + 1), SECOND_MS);
    return () => clearInterval(timer);
  }, [shown.ended]);

  return <ReviewBody state={shown} elapsedSeconds={elapsedSeconds} />;
}
