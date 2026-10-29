"use client";

import { Button } from "@/components/ui/button";
import type { Draft } from "@/lib/draft-schema";

export type DraftStatus = {
  notice: string | null;
  error: string | null;
  busy: "saving" | "posting" | "deleting" | null;
};

type DraftActionBarProps = {
  draft: Draft;
  dirty: boolean;
  repo: string | null;
  status: DraftStatus;
  onSave: () => void;
  onPost: () => void;
  onDelete: () => void;
};

export function DraftActionBar({
  draft,
  dirty,
  repo,
  status,
  onSave,
  onPost,
  onDelete,
}: DraftActionBarProps) {
  const busy = status.busy !== null;
  const posted = draft.posted;
  const canPost = !dirty && posted === undefined && !busy && repo !== null;
  return (
    <div className="sticky bottom-0 flex flex-col gap-2 border-t bg-background px-4 py-3">
      <div className="flex flex-wrap items-center justify-between gap-2 text-sm">
        <span>{dirty ? "Unsaved changes" : status.notice}</span>
        {status.error ? (
          <span className="text-red-600">{status.error}</span>
        ) : null}
      </div>
      <div className="flex flex-wrap items-center gap-2">
        <RepoLine repo={repo} project={draft.project} />
        <div className="ml-auto flex flex-wrap gap-2">
          <Button
            type="button"
            variant="outline"
            onClick={onSave}
            disabled={!dirty || busy}
          >
            Save
          </Button>
          <Button type="button" onClick={onPost} disabled={!canPost}>
            {draft.kind === "pr" ? "Create PR on GitHub" : "Post review"}
          </Button>
          <Button
            type="button"
            variant="destructive"
            onClick={onDelete}
            disabled={busy}
          >
            Delete
          </Button>
        </div>
      </div>
      {posted ? (
        <a
          className="text-sm underline"
          href={posted.url}
          target="_blank"
          rel="noreferrer noopener"
        >
          View posted on GitHub
        </a>
      ) : null}
    </div>
  );
}

function RepoLine({ repo, project }: { repo: string | null; project: string }) {
  if (repo === null) {
    return (
      <span className="text-sm text-red-600">
        No GitHub origin in {project}
      </span>
    );
  }
  return (
    <span className="text-sm">
      Posts to <strong>{repo}</strong>
    </span>
  );
}
