"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent } from "@/components/ui/card";
import { formatLocalTime, formatRelative } from "@/lib/format-time";
import type { ReviewSummary } from "@/lib/reviews";
import { headerStatusLabel, statusDotClass, statusTextClass } from "@/lib/status-style";
import { verdictBadgeClass } from "@/lib/verdict-style";

const POLL_INTERVAL_MS = 2000;

export function ReviewList() {
  const [reviews, setReviews] = useState<ReviewSummary[] | null>(null);
  const [now, setNow] = useState(0);

  useEffect(() => {
    const load = async () => {
      const response = await fetch("/api/reviews", { cache: "no-store" });
      if (response.ok) {
        setReviews((await response.json()) as ReviewSummary[]);
        setNow(Date.now());
      }
    };
    void load();
    const timer = setInterval(load, POLL_INTERVAL_MS);
    return () => clearInterval(timer);
  }, []);

  if (reviews === null) {
    return <p className="text-sm text-muted-foreground">Loading reviews...</p>;
  }
  if (reviews.length === 0) {
    return (
      <p className="text-sm text-muted-foreground">
        No reviews yet. Run <code className="rounded bg-muted px-1 font-mono text-xs">claude-ollama review PR</code>.
      </p>
    );
  }
  return (
    <ul className="flex flex-col gap-3">
      {reviews.map((review) => (
        <li key={review.id}>
          <ReviewRow review={review} now={now} />
        </li>
      ))}
    </ul>
  );
}

function ReviewRow({ review, now }: { review: ReviewSummary; now: number }) {
  return (
    <Link
      href={`/reviews/${encodeURIComponent(review.id)}`}
      className="block rounded-xl outline-none focus-visible:ring-2 focus-visible:ring-ring"
    >
      <Card className="cursor-pointer transition-colors hover:bg-muted/60">
        <CardContent className="flex flex-col gap-2">
          <div className="flex min-w-0 items-center gap-2">
            <span className={statusDotClass(review.status)} />
            <span className="min-w-0 break-words font-medium">{review.name || review.id}</span>
          </div>
          <p className="break-words text-sm text-muted-foreground">{review.title}</p>
          <div className="flex flex-wrap items-center gap-2 text-xs text-muted-foreground">
            <VerdictBadge review={review} />
            <span>{review.findings} findings</span>
            {review.seconds === null ? null : <span>{Math.round(review.seconds)}s</span>}
            <time dateTime={review.started} title={review.started}>
              {formatLocalTime(review.started)}
              {now === 0 ? "" : ` · ${formatRelative(review.started, now)}`}
            </time>
          </div>
        </CardContent>
      </Card>
    </Link>
  );
}

function VerdictBadge({ review }: { review: ReviewSummary }) {
  if (review.verdict === null) {
    return (
      <Badge variant="outline" className={statusTextClass(review.status)}>
        {headerStatusLabel(review.status)}
      </Badge>
    );
  }
  return <Badge variant="outline" className={verdictBadgeClass(review.verdict)}>{review.verdict}</Badge>;
}
