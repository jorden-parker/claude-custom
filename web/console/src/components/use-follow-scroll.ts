"use client";

import { useEffect, useRef, type UIEvent } from "react";

const FOLLOW_THRESHOLD_PX = 8;

export function useFollowScroll<T extends HTMLElement>(contentKey: unknown) {
  const outputRef = useRef<T>(null);
  const followRef = useRef(true);

  useEffect(() => {
    const output = outputRef.current;
    if (output && followRef.current) {
      output.scrollTop = output.scrollHeight;
    }
  }, [contentKey]);

  const onScroll = (event: UIEvent<T>) => {
    followRef.current = isAtBottom(event.currentTarget);
  };
  return { outputRef, onScroll };
}

function isAtBottom(box: HTMLElement): boolean {
  return box.scrollHeight - box.scrollTop - box.clientHeight < FOLLOW_THRESHOLD_PX;
}
