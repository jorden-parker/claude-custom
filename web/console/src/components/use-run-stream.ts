"use client";

import { useEffect, useReducer } from "react";
import { parseRunEvent } from "@/lib/run-event";
import { reduceRunMessage } from "@/lib/run-display";
import { initialRunState, type RunState } from "@/lib/run-state";

export function useRunStream(id: string): RunState {
  const [state, dispatch] = useReducer(reduceRunMessage, initialRunState);
  useEffect(() => {
    const source = new EventSource(`/api/runs/${encodeURIComponent(id)}/events`);
    source.onmessage = (message) => {
      dispatch({ data: message.data, lastEventId: message.lastEventId });
      if (parseRunEvent(message.data)?.kind === "end") {
        source.close();
      }
    };
    return () => source.close();
  }, [id]);
  return state;
}
