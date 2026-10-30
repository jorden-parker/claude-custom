import type { ReviewComment, ReviewDraft, Section } from "./draft-schema";

const INLINE_SIDE = "RIGHT";

type PlacedComment = ReviewComment & { path: string; line: number };
type InlineComment = {
  path: string;
  line: number;
  side: typeof INLINE_SIDE;
  body: string;
};
type ReviewPayload = {
  event: string;
  body: string;
  comments: InlineComment[];
};

export function pullRequestBody(sections: Section[]): string {
  return sections
    .map((section) => `## ${section.heading}\n\n${section.body}`)
    .join("\n\n");
}

export function reviewPayload(draft: ReviewDraft): ReviewPayload {
  const unplaced = draft.comments.filter((comment) => !isPlaced(comment));
  return {
    event: draft.event,
    body: [draft.summary, ...unplaced.map(renderComment)]
      .filter((part) => part.trim() !== "")
      .join("\n\n"),
    comments: draft.comments.filter(isPlaced).map((comment) => ({
      path: comment.path,
      line: comment.line,
      side: INLINE_SIDE,
      body: renderComment(comment),
    })),
  };
}

function isPlaced(comment: ReviewComment): comment is PlacedComment {
  return comment.path !== undefined && comment.line !== undefined;
}

function renderComment(comment: ReviewComment): string {
  const tags = comment.decorations.join(", ");
  const heading = tags === "" ? comment.label : `${comment.label} (${tags})`;
  return `**${heading}:** ${comment.body}`;
}
