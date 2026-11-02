"use client";

import { defineRegistry, JSONUIProvider, Renderer } from "@json-render/react";
import type { Spec } from "@json-render/core";
import { mockCatalog } from "./catalog.ts";

const GAP_CLASSES = { sm: "gap-2", md: "gap-4", lg: "gap-6" } as const;
const BUTTON_CLASSES = {
  primary: "bg-(--mock-accent) text-(--mock-on-accent) hover:opacity-90",
  secondary:
    "border border-(--mock-line) bg-(--mock-surface) text-(--mock-ink) hover:bg-(--mock-surface-2)",
  ghost: "text-(--mock-ink) hover:bg-(--mock-surface-2)",
} as const;
const BADGE_CLASSES = {
  neutral: "border border-(--mock-line) text-(--mock-ink-soft)",
  success: "bg-(--mock-success-bg) text-(--mock-success)",
  warning: "bg-(--mock-warning-bg) text-(--mock-warning)",
} as const;
const HEADING_CLASSES = {
  "1": "text-2xl font-semibold tracking-tight",
  "2": "text-lg font-semibold",
  "3": "text-base font-medium",
} as const;

export const { registry: mockRegistry } = defineRegistry(mockCatalog, {
  components: {
    Stack: ({ props, children }) => (
      <div
        className={`flex ${props.direction === "horizontal" ? "flex-row flex-wrap items-start" : "flex-col"} ${GAP_CLASSES[props.gap ?? "md"]}`}
      >
        {children}
      </div>
    ),
    Card: ({ props, children }) => (
      <section className="flex min-w-48 flex-1 flex-col gap-4 rounded-lg border border-(--mock-line) bg-(--mock-surface) p-5 shadow-sm">
        <header className="flex flex-col gap-1">
          <p className="font-semibold">{props.title}</p>
          {props.description ? (
            <p className="text-sm text-(--mock-ink-soft)">
              {props.description}
            </p>
          ) : null}
        </header>
        <div className="flex flex-col gap-3">{children}</div>
      </section>
    ),
    Heading: ({ props }) => (
      <p className={HEADING_CLASSES[props.level]}>{props.text}</p>
    ),
    Text: ({ props }) => (
      <p className={`text-sm ${props.muted ? "text-(--mock-ink-soft)" : ""}`}>
        {props.text}
      </p>
    ),
    Button: ({ props }) => (
      <button
        type="button"
        className={`inline-flex h-9 items-center justify-center rounded-md px-4 text-sm font-medium ${BUTTON_CLASSES[props.variant]}`}
      >
        {props.label}
      </button>
    ),
    Input: ({ props }) => (
      <label className="flex flex-col gap-1 text-sm font-medium">
        {props.label}
        <input
          className="h-9 rounded-md border border-(--mock-line) bg-(--mock-surface) px-3 text-sm font-normal placeholder:text-(--mock-ink-faint)"
          placeholder={props.placeholder ?? undefined}
          readOnly
        />
      </label>
    ),
    Badge: ({ props }) => (
      <span
        className={`inline-flex w-fit items-center rounded-full px-2.5 py-0.5 text-xs font-medium ${BADGE_CLASSES[props.tone]}`}
      >
        {props.text}
      </span>
    ),
  },
});

export function MockFrame({ spec }: { spec: Spec }) {
  return (
    <div className="mock-frame rounded-md p-5">
      <JSONUIProvider registry={mockRegistry}>
        <Renderer spec={spec} registry={mockRegistry} />
      </JSONUIProvider>
    </div>
  );
}
