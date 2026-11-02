"use client";

import { defineRegistry } from "@json-render/react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { mockCatalog } from "./catalog.ts";

const GAP_CLASSES = { sm: "gap-2", md: "gap-4", lg: "gap-6" } as const;
const BUTTON_VARIANTS = {
  primary: "default",
  secondary: "secondary",
  ghost: "ghost",
} as const;
const BADGE_VARIANTS = {
  neutral: "outline",
  success: "default",
  warning: "destructive",
} as const;
const HEADING_CLASSES = {
  "1": "text-2xl font-semibold",
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
      <Card className="min-w-48 flex-1">
        <CardHeader>
          <CardTitle>{props.title}</CardTitle>
          {props.description ? (
            <CardDescription>{props.description}</CardDescription>
          ) : null}
        </CardHeader>
        <CardContent className="flex flex-col gap-3">{children}</CardContent>
      </Card>
    ),
    Heading: ({ props }) => (
      <p className={HEADING_CLASSES[props.level]}>{props.text}</p>
    ),
    Text: ({ props }) => (
      <p className={`text-sm ${props.muted ? "text-muted-foreground" : ""}`}>
        {props.text}
      </p>
    ),
    Button: ({ props }) => (
      <Button type="button" variant={BUTTON_VARIANTS[props.variant]}>
        {props.label}
      </Button>
    ),
    Input: ({ props }) => (
      <label className="flex flex-col gap-1 text-sm">
        {props.label}
        <Input placeholder={props.placeholder ?? undefined} readOnly />
      </label>
    ),
    Badge: ({ props }) => (
      <Badge variant={BADGE_VARIANTS[props.tone]}>{props.text}</Badge>
    ),
  },
});
