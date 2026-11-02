import { NewReviewForm } from "@/components/new-review-form";
import { PageHeading } from "@/components/page-heading";
import { ReviewList } from "@/components/review-list";

export default function ReviewsPage() {
  return (
    <>
      <PageHeading title="Reviews" />
      <NewReviewForm />
      <ReviewList />
    </>
  );
}
