"use client";

import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { useFetchedJson } from "@/components/use-fetched-json";
import type { HookRecipes, RecipeEntry } from "@/lib/diagnose";

const RECIPES_URL = "/api/recipes";

export function RecipesCard() {
  const { value, error } = useFetchedJson<{ recipes: HookRecipes[] }>(
    RECIPES_URL,
  );
  return (
    <Card>
      <CardHeader>
        <CardTitle>Recovery recipes</CardTitle>
        <CardDescription>
          The numbered steps a guard appends to its third identical denial, by
          hook and denial pattern; read-only
        </CardDescription>
      </CardHeader>
      <CardContent className="flex flex-col gap-3">
        {error !== null ? (
          <p className="text-sm text-error-foreground">{error}</p>
        ) : null}
        {value === null && error === null ? (
          <p className="text-sm text-muted-foreground">Loading recipes...</p>
        ) : null}
        {value !== null && value.recipes.length === 0 ? (
          <p className="text-sm text-muted-foreground">
            No recovery recipes found.
          </p>
        ) : null}
        {value === null
          ? null
          : value.recipes.map((hook) => (
              <HookRecipesView key={hook.hook} hook={hook} />
            ))}
      </CardContent>
    </Card>
  );
}

function HookRecipesView({ hook }: { hook: HookRecipes }) {
  return (
    <article className="flex flex-col gap-2 rounded-lg border border-border p-3">
      <h3 className="font-mono text-sm font-semibold">{hook.hook}</h3>
      {hook.entries.map((entry) => (
        <RecipeEntryView key={entry.match} entry={entry} />
      ))}
    </article>
  );
}

function RecipeEntryView({ entry }: { entry: RecipeEntry }) {
  return (
    <div className="flex flex-col gap-1 text-sm">
      <code className="w-fit rounded bg-muted px-1 text-xs">{entry.match}</code>
      <ol className="list-decimal pl-5">
        {entry.steps.map((step) => (
          <li key={step}>{step}</li>
        ))}
      </ol>
    </div>
  );
}
