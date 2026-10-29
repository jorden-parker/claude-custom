"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent } from "@/components/ui/card";
import type { DraftRow } from "@/lib/drafts";
import type { Draft } from "@/lib/draft-schema";

export function DraftList() {
  const [rows, setRows] = useState<DraftRow[] | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    fetch("/api/drafts", { cache: "no-store" })
      .then(async (response) => {
        if (!response.ok) {
          throw new Error(`request failed (${response.status})`);
        }
        setRows(((await response.json()) as { drafts: DraftRow[] }).drafts);
      })
      .catch(() => setError("could not load the drafts"));
  }, []);

  if (error !== null) {
    return <p className="text-sm text-red-600">{error}</p>;
  }
  if (rows === null) {
    return <p className="text-sm text-muted-foreground">Loading drafts…</p>;
  }
  if (rows.length === 0) {
    return (
      <p className="text-sm text-muted-foreground">
        No drafts yet. /pr-draft and /pr-review-draft write them here.
      </p>
    );
  }
  return (
    <ul className="flex flex-col gap-3">
      {rows.map((row) => (
        <li key={row.id}>
          <DraftRowCard row={row} />
        </li>
      ))}
    </ul>
  );
}

function DraftRowCard({ row }: { row: DraftRow }) {
  return (
    <Link href={`/drafts/${row.id}`} className="block">
      <Card size="sm">
        <CardContent className="flex flex-col gap-1">
          {row.draft === null ? (
            <InvalidRow id={row.id} reason={row.invalid ?? "invalid"} />
          ) : (
            <ValidRow row={row} draft={row.draft} />
          )}
        </CardContent>
      </Card>
    </Link>
  );
}

function InvalidRow({ id, reason }: { id: string; reason: string }) {
  return (
    <>
      <div className="flex items-center gap-2">
        <Badge variant="destructive">invalid</Badge>
        <span className="font-mono text-xs">{id}</span>
      </div>
      <span className="text-sm text-red-600">{reason}</span>
    </>
  );
}

function ValidRow({ row, draft }: { row: DraftRow; draft: Draft }) {
  return (
    <>
      <div className="flex flex-wrap items-center gap-2">
        <Badge variant="secondary">
          {draft.kind === "pr" ? "PR" : "review"}
        </Badge>
        <span className="text-sm">{row.repo ?? "no GitHub origin"}</span>
        {draft.posted ? <Badge>posted</Badge> : null}
      </div>
      <span className="text-sm font-medium">{targetOf(draft)}</span>
      <span className="truncate text-sm text-muted-foreground">
        {summaryOf(draft)}
      </span>
    </>
  );
}

function targetOf(draft: Draft): string {
  return draft.kind === "pr"
    ? `${draft.head} → ${draft.base}`
    : `PR #${draft.pr}`;
}

function summaryOf(draft: Draft): string {
  const text = draft.kind === "pr" ? draft.title : draft.summary;
  return text.split("\n")[0] ?? "";
}
