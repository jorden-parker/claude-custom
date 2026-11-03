"use client";

import { useTheme } from "next-themes";
import { useEffect } from "react";

const TYPING_TAGS = new Set(["INPUT", "TEXTAREA", "SELECT"]);

function isTypingTarget(target: EventTarget | null): boolean {
  if (!(target instanceof HTMLElement)) {
    return false;
  }
  return TYPING_TAGS.has(target.tagName) || target.isContentEditable;
}

export function ThemeShortcut() {
  const { resolvedTheme, setTheme } = useTheme();

  useEffect(() => {
    const toggleOnD = (event: KeyboardEvent) => {
      const isPlainD =
        event.key.toLowerCase() === "d" &&
        !event.metaKey &&
        !event.ctrlKey &&
        !event.altKey;
      if (!isPlainD || isTypingTarget(event.target)) {
        return;
      }
      setTheme(resolvedTheme === "dark" ? "light" : "dark");
    };
    document.addEventListener("keydown", toggleOnD);
    return () => document.removeEventListener("keydown", toggleOnD);
  }, [resolvedTheme, setTheme]);

  return null;
}
