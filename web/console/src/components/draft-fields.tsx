"use client";

import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Select } from "@/components/ui/select";
import {
  CommentCard,
  EditableMarkdown,
  SectionCard,
} from "@/components/draft-cards";
import {
  blankComment,
  blankSection,
  removeAt,
  replaceAt,
} from "@/lib/draft-edits";
import {
  DRAFT_EVENTS,
  type DraftEvent,
  type PrDraft,
  type ReviewDraft,
} from "@/lib/draft-schema";

type PrFieldsProps = {
  draft: PrDraft;
  asDraft: boolean;
  onAsDraftChange: (asDraft: boolean) => void;
  onChange: (patch: Partial<PrDraft>) => void;
};

export function PrFields({
  draft,
  asDraft,
  onAsDraftChange,
  onChange,
}: PrFieldsProps) {
  return (
    <>
      <Card size="sm">
        <CardHeader>
          <CardTitle>Title</CardTitle>
        </CardHeader>
        <CardContent>
          <Input
            aria-label="Title"
            value={draft.title}
            onChange={(event) => onChange({ title: event.target.value })}
          />
        </CardContent>
      </Card>
      <label className="flex items-center gap-2 text-sm">
        <input
          type="checkbox"
          aria-label="Draft PR"
          checked={asDraft}
          onChange={(event) => onAsDraftChange(event.target.checked)}
        />
        Draft PR
      </label>
      {draft.sections.map((section, index) => (
        <SectionCard
          key={index}
          number={index + 1}
          section={section}
          onChange={(next) =>
            onChange({ sections: replaceAt(draft.sections, index, next) })
          }
          onRemove={() =>
            onChange({ sections: removeAt(draft.sections, index) })
          }
        />
      ))}
      <Button
        type="button"
        variant="outline"
        className="self-start"
        onClick={() =>
          onChange({ sections: [...draft.sections, blankSection()] })
        }
      >
        Add section
      </Button>
    </>
  );
}

type ReviewFieldsProps = {
  draft: ReviewDraft;
  onChange: (patch: Partial<ReviewDraft>) => void;
};

export function ReviewFields({ draft, onChange }: ReviewFieldsProps) {
  return (
    <>
      <Card size="sm">
        <CardHeader>
          <CardTitle>Review</CardTitle>
        </CardHeader>
        <CardContent className="flex flex-col gap-3">
          <Select
            aria-label="Event"
            className="w-auto"
            value={draft.event}
            onChange={(event) =>
              onChange({ event: event.target.value as DraftEvent })
            }
          >
            {DRAFT_EVENTS.map((event) => (
              <option key={event} value={event}>
                {event}
              </option>
            ))}
          </Select>
          <EditableMarkdown
            label="Summary"
            value={draft.summary}
            onChange={(summary) => onChange({ summary })}
          />
        </CardContent>
      </Card>
      {draft.comments.map((comment, index) => (
        <CommentCard
          key={index}
          number={index + 1}
          comment={comment}
          onChange={(next) =>
            onChange({ comments: replaceAt(draft.comments, index, next) })
          }
          onRemove={() =>
            onChange({ comments: removeAt(draft.comments, index) })
          }
        />
      ))}
      <Button
        type="button"
        variant="outline"
        className="self-start"
        onClick={() =>
          onChange({ comments: [...draft.comments, blankComment()] })
        }
      >
        Add comment
      </Button>
    </>
  );
}
