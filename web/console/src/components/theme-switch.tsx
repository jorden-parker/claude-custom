"use client";

import { Monitor, Moon, Sun, type LucideIcon } from "lucide-react";
import { useTheme } from "next-themes";
import { useEffect, useSyncExternalStore } from "react";
import { Kbd } from "@/components/ui/kbd";
import { SidebarMenuButton } from "@/components/ui/sidebar";

const THEME_CHOICES = ["system", "light", "dark"] as const;

type ThemeChoice = (typeof THEME_CHOICES)[number];

const THEME_LABELS: Record<ThemeChoice, string> = {
  system: "System",
  light: "Light",
  dark: "Dark",
};

const THEME_ICONS: Record<ThemeChoice, LucideIcon> = {
  system: Monitor,
  light: Sun,
  dark: Moon,
};

const TYPING_TAGS = new Set(["INPUT", "TEXTAREA", "SELECT"]);

function nextThemeChoice(current: ThemeChoice): ThemeChoice {
  const index = THEME_CHOICES.indexOf(current);
  return THEME_CHOICES[(index + 1) % THEME_CHOICES.length];
}

function isTypingTarget(target: EventTarget | null): boolean {
  if (!(target instanceof HTMLElement)) {
    return false;
  }
  return TYPING_TAGS.has(target.tagName) || target.isContentEditable;
}

function isThemeChoice(value: string | undefined): value is ThemeChoice {
  return THEME_CHOICES.some((choice) => choice === value);
}

function subscribeToNothing() {
  return () => undefined;
}

function useMounted(): boolean {
  return useSyncExternalStore(
    subscribeToNothing,
    () => true,
    () => false,
  );
}

function useDarkShortcut() {
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
}

export function ThemeSwitch() {
  const { theme, setTheme } = useTheme();
  const mounted = useMounted();
  useDarkShortcut();

  const choice: ThemeChoice =
    mounted && isThemeChoice(theme) ? theme : "system";
  const Icon = THEME_ICONS[choice];
  const label = `Theme: ${THEME_LABELS[choice]}`;

  return (
    <SidebarMenuButton
      onClick={() => setTheme(nextThemeChoice(choice))}
      tooltip={{
        children: (
          <>
            {label} <Kbd>D</Kbd>
          </>
        ),
      }}
    >
      <Icon />
      <span>{label}</span>
    </SidebarMenuButton>
  );
}
