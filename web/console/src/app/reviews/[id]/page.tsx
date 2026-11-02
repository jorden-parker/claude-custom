import { notFound } from "next/navigation";
import { connection } from "next/server";
import { Suspense } from "react";
import { PageHeading } from "@/components/page-heading";
import { ReviewView } from "@/components/review-view";
import { isStoppedReview, resolveReviewFile } from "@/lib/reviews";

type ReviewPageProps = { params: Promise<{ id: string }> };

export default function ReviewPage({ params }: ReviewPageProps) {
  return (
    <>
      <PageHeading title="Review" backHref="/reviews" backLabel="Reviews" />
      <Suspense fallback={<p className="text-sm text-muted-foreground">Loading review...</p>}>
        <LiveReview params={params} />
      </Suspense>
    </>
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
