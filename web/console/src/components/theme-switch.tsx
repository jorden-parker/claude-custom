"use client";

import { Monitor, Moon, Sun, type LucideIcon } from "lucide-react";
import { useTheme } from "next-themes";
import { useSyncExternalStore } from "react";
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

function nextThemeChoice(current: ThemeChoice): ThemeChoice {
  const index = THEME_CHOICES.indexOf(current);
  return THEME_CHOICES[(index + 1) % THEME_CHOICES.length];
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

export function ThemeSwitch() {
  const { theme, setTheme } = useTheme();
  const mounted = useMounted();

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
