"use client";

import { useState } from "react";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardAction,
  CardContent,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Select } from "@/components/ui/select";
import { Textarea } from "@/components/ui/textarea";
import { MarkdownText } from "@/components/markdown-text";
import {
  lineFromInput,
  pathFromInput,
  toggleDecoration,
} from "@/lib/draft-edits";
import {
  DECORATIONS,
  LABELS,
  type Label,
  type ReviewComment,
  type Section,
} from "@/lib/draft-schema";

type EditableMarkdownProps = {
  label: string;
  value: string;
  onChange: (value: string) => void;
};

export function EditableMarkdown({
  label,
  value,
  onChange,
}: EditableMarkdownProps) {
  const [previewing, setPreviewing] = useState(false);
  return (
    <div className="flex flex-col gap-1">
      <div className="flex items-center justify-between">
        <span className="text-xs text-muted-foreground">{label}</span>
        <Button
          type="button"
          variant="ghost"
          size="sm"
          onClick={() => setPreviewing(!previewing)}
        >
          {previewing ? "Edit" : "Preview"}
        </Button>
      </div>
      {previewing ? (
        <div className="min-h-16 rounded-lg border p-3">
          <MarkdownText>{value}</MarkdownText>
        </div>
      ) : (
        <Textarea
          aria-label={label}
          rows={4}
          value={value}
          onChange={(event) => onChange(event.target.value)}
        />
      )}
    </div>
  );
}

type SectionCardProps = {
  section: Section;
  number: number;
  onChange: (section: Section) => void;
  onRemove: () => void;
};

export function SectionCard({
  section,
  number,
  onChange,
  onRemove,
}: SectionCardProps) {
  return (
    <Card size="sm">
      <CardHeader>
        <CardTitle>Section {number}</CardTitle>
        <CardAction>
          <Button
            type="button"
            variant="ghost"
            size="sm"
            aria-label={`Remove section ${number}`}
            onClick={onRemove}
          >
            Remove
          </Button>
        </CardAction>
      </CardHeader>
      <CardContent className="flex flex-col gap-3">
        <Input
          aria-label={`Heading ${number}`}
          value={section.heading}
          onChange={(event) =>
            onChange({ ...section, heading: event.target.value })
          }
        />
        <EditableMarkdown
          label={`Body ${number}`}
          value={section.body}
          onChange={(body) => onChange({ ...section, body })}
        />
      </CardContent>
    </Card>
  );
}

type CommentCardProps = {
  comment: ReviewComment;
  number: number;
  onChange: (comment: ReviewComment) => void;
  onRemove: () => void;
};

export function CommentCard({
  comment,
  number,
  onChange,
  onRemove,
}: CommentCardProps) {
  return (
    <Card size="sm">
      <CardHeader>
        <CardTitle>Comment {number}</CardTitle>
        <CardAction>
          <Button
            type="button"
            variant="ghost"
            size="sm"
            aria-label={`Remove comment ${number}`}
            onClick={onRemove}
          >
            Remove
          </Button>
        </CardAction>
      </CardHeader>
      <CardContent className="flex flex-col gap-3">
        <div className="flex flex-wrap items-center gap-3">
          <Select
            aria-label={`Label ${number}`}
            className="w-auto"
            value={comment.label}
            onChange={(event) =>
              onChange({ ...comment, label: event.target.value as Label })
            }
          >
            {LABELS.map((label) => (
              <option key={label} value={label}>
                {label}
              </option>
            ))}
          </Select>
          {DECORATIONS.map((decoration) => (
            <label key={decoration} className="flex items-center gap-1 text-sm">
              <input
                type="checkbox"
                aria-label={`${decoration} ${number}`}
                checked={comment.decorations.includes(decoration)}
                onChange={() =>
                  onChange({
                    ...comment,
                    decorations: toggleDecoration(
                      comment.decorations,
                      decoration,
                    ),
                  })
                }
              />
              {decoration}
            </label>
          ))}
        </div>
        <div className="flex flex-wrap gap-3">
          <Input
            aria-label={`Path ${number}`}
            placeholder="path (optional)"
            value={comment.path ?? ""}
            onChange={(event) =>
              onChange({ ...comment, path: pathFromInput(event.target.value) })
            }
          />
          <Input
            aria-label={`Line ${number}`}
            type="number"
            placeholder="line (optional)"
            value={comment.line ?? ""}
            onChange={(event) =>
              onChange({ ...comment, line: lineFromInput(event.target.value) })
            }
          />
        </div>
        <EditableMarkdown
          label={`Comment ${number}`}
          value={comment.body}
          onChange={(body) => onChange({ ...comment, body })}
        />
      </CardContent>
    </Card>
  );
}
