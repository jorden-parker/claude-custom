import Link from "next/link";
import { notFound } from "next/navigation";
import { connection } from "next/server";
import { Suspense } from "react";
import { ReviewView } from "@/components/review-view";
import { isStoppedReview, resolveReviewFile } from "@/lib/reviews";

type ReviewPageProps = { params: Promise<{ id: string }> };

export default function ReviewPage({ params }: ReviewPageProps) {
  return (
    <main className="mx-auto flex w-full max-w-3xl flex-col gap-6 px-4 py-8">
      <Link href="/" className="text-sm underline">
        All reviews
      </Link>
      <Suspense fallback={<p className="text-sm text-muted-foreground">Loading review...</p>}>
        <LiveReview params={params} />
      </Suspense>
    </main>
  );
}

async function LiveReview({ params }: ReviewPageProps) {
  await connection();
  const { id } = await params;
  const file = resolveReviewFile(id);
  if (!file) {
    notFound();
  }
  return <ReviewView id={id} stopped={isStoppedReview(file)} />;
}
