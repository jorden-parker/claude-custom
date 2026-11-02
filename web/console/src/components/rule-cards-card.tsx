"use client";

import Link from "next/link";
import { MarkdownText } from "@/components/markdown-text";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { useFetchedJson } from "@/components/use-fetched-json";
import type { RuleCard } from "@/lib/diagnose";

const RULE_CARDS_URL = "/api/rule-cards";
const RULE_CARDS_SWITCH = "CLAUDE_OLLAMA_RULE_CARDS";

export function RuleCardsCard() {
  const { value, error } = useFetchedJson<{ cards: RuleCard[] }>(
    RULE_CARDS_URL,
  );
  return (
    <Card>
      <CardHeader>
        <CardTitle>Rule cards</CardTitle>
        <CardDescription>
          Situational rules the rule-cards hook hands the model when a tool call
          matches a trigger; read-only
        </CardDescription>
      </CardHeader>
      <CardContent className="flex flex-col gap-3">
        <p className="text-xs text-muted-foreground">
          Turning{" "}
          <Link
            href={`/settings#${RULE_CARDS_SWITCH}`}
            className="font-mono underline underline-offset-2"
          >
            {RULE_CARDS_SWITCH}
          </Link>{" "}
          off on the Settings page stops the delivery.
        </p>
        {error !== null ? (
          <p className="text-sm text-error-foreground">{error}</p>
        ) : null}
        {value === null && error === null ? (
          <p className="text-sm text-muted-foreground">Loading rule cards...</p>
        ) : null}
        {value !== null && value.cards.length === 0 ? (
          <p className="text-sm text-muted-foreground">No rule cards found.</p>
        ) : null}
        {value === null
          ? null
          : value.cards.map((card) => (
              <RuleCardView key={card.id} card={card} />
            ))}
      </CardContent>
    </Card>
  );
}

function RuleCardView({ card }: { card: RuleCard }) {
  return (
    <article className="flex flex-col gap-1 rounded-lg border border-border p-3">
      <h3 className="font-mono text-sm font-semibold">{card.id}</h3>
      <p className="text-xs text-muted-foreground">
        {card.triggers.join(", ")}
      </p>
      <MarkdownText>{card.body}</MarkdownText>
    </article>
  );
}
