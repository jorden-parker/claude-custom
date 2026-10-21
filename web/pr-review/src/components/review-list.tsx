"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent } from "@/components/ui/card";
import type { ReviewSummary } from "@/lib/reviews";
import { verdictBadgeClass } from "@/lib/verdict-style";

const POLL_INTERVAL_MS = 2000;

export function ReviewList() {
  const [reviews, setReviews] = useState<ReviewSummary[] | null>(null);

  useEffect(() => {
    const load = async () => {
      const response = await fetch("/api/reviews", { cache: "no-store" });
      if (response.ok) {
        setReviews((await response.json()) as ReviewSummary[]);
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
    return <p className="text-sm text-muted-foreground">No reviews yet. Run `claude-ollama review PR`.</p>;
  }
  return (
    <ul className="flex flex-col gap-3">
      {reviews.map((review) => (
        <li key={review.id}>
          <ReviewRow review={review} />
        </li>
      ))}
    </ul>
  );
}

function ReviewRow({ review }: { review: ReviewSummary }) {
  return (
    <Link href={`/reviews/${encodeURIComponent(review.id)}`} className="block">
      <Card>
        <CardContent className="flex flex-col gap-2">
          <div className="flex min-w-0 items-center gap-2">
            <span className={`size-2 shrink-0 rounded-full ${statusDotClass(review.status)}`} />
            <span className="min-w-0 break-words font-medium">{review.name || review.id}</span>
          </div>
          <p className="break-words text-sm text-muted-foreground">{review.title}</p>
          <div className="flex flex-wrap items-center gap-2 text-xs text-muted-foreground">
            <VerdictBadge review={review} />
            <span>{review.findings} findings</span>
            {review.seconds === null ? null : <span>{Math.round(review.seconds)}s</span>}
            <span>{review.started}</span>
          </div>
        </CardContent>
      </Card>
    </Link>
  );
}

function VerdictBadge({ review }: { review: ReviewSummary }) {
  if (review.verdict === null) {
    return <Badge variant="outline">{review.status}</Badge>;
  }
  return <Badge variant="outline" className={verdictBadgeClass(review.verdict)}>{review.verdict}</Badge>;
}

function statusDotClass(status: ReviewSummary["status"]): string {
  if (status === "running") {
    return "animate-pulse bg-blue-500";
  }
  if (status === "error") {
    return "bg-destructive";
  }
  return "bg-muted-foreground";
}
