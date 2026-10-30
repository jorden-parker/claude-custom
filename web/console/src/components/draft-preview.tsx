import { MarkdownText } from "@/components/markdown-text";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { pullRequestBody, reviewPayload } from "@/lib/draft-render";
import type { Draft, PrDraft, ReviewDraft } from "@/lib/draft-schema";

export function DraftPreview({
  draft,
  asDraft,
}: {
  draft: Draft;
  asDraft: boolean;
}) {
  return draft.kind === "pr" ? (
    <PrPreview draft={draft} asDraft={asDraft} />
  ) : (
    <ReviewPreview draft={draft} />
  );
}

function PrPreview({ draft, asDraft }: { draft: PrDraft; asDraft: boolean }) {
  return (
    <Card>
      <CardHeader>
        <CardTitle>{draft.title}</CardTitle>
        <p className="text-xs text-muted-foreground">
          {draft.head} into {draft.base}
        </p>
        {asDraft ? (
          <p className="text-xs text-muted-foreground">Opens as a draft PR</p>
        ) : null}
      </CardHeader>
      <CardContent>
        <PostedText text={pullRequestBody(draft.sections)} />
      </CardContent>
    </Card>
  );
}

function ReviewPreview({ draft }: { draft: ReviewDraft }) {
  const payload = reviewPayload(draft);
  return (
    <div className="flex flex-col gap-4">
      <Card>
        <CardHeader>
          <CardTitle>Review of PR #{draft.pr}</CardTitle>
          <p className="text-xs text-muted-foreground">{payload.event}</p>
        </CardHeader>
        <CardContent>
          <PostedText text={payload.body} />
        </CardContent>
      </Card>
      {payload.comments.map((comment, index) => (
        <Card key={`${index}-${comment.path}:${comment.line}`}>
          <CardHeader>
            <CardTitle>{`${comment.path}:${comment.line}`}</CardTitle>
          </CardHeader>
          <CardContent>
            <PostedText text={comment.body} />
          </CardContent>
        </Card>
      ))}
    </div>
  );
}

function PostedText({ text }: { text: string }) {
  if (text.trim() === "") {
    return (
      <p className="text-sm text-muted-foreground">Nothing to post yet.</p>
    );
  }
  return <MarkdownText>{text}</MarkdownText>;
}
