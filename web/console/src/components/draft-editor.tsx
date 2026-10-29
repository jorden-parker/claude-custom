"use client";

import { useRouter } from "next/navigation";
import { useEffect, useState } from "react";
import {
  DraftActionBar,
  type DraftStatus,
} from "@/components/draft-action-bar";
import { PrFields, ReviewFields } from "@/components/draft-fields";
import { isDirty } from "@/lib/draft-edits";
import {
  editableFieldsOf,
  type Draft,
  type PrDraft,
  type ReviewDraft,
} from "@/lib/draft-schema";

type Saved = { draft: Draft; hash: string; repo: string | null };
type RequestResult = { ok: true; body: Saved } | { ok: false; message: string };

const IDLE_STATUS: DraftStatus = { notice: null, error: null, busy: null };

export function DraftEditor({ id }: { id: string }) {
  const router = useRouter();
  const [saved, setSaved] = useState<Saved | null>(null);
  const [draft, setDraft] = useState<Draft | null>(null);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [status, setStatus] = useState<DraftStatus>(IDLE_STATUS);
  const [asDraft, setAsDraft] = useState(false);

  useEffect(() => {
    let active = true;
    fetch(`/api/drafts/${id}`, { cache: "no-store" })
      .then(async (response) => {
        if (!active) {
          return;
        }
        const result = await readResult(response);
        if (!result.ok) {
          setLoadError(result.message);
          return;
        }
        setSaved(result.body);
        setDraft(result.body.draft);
      })
      .catch(() => active && setLoadError("could not load the draft"));
    return () => {
      active = false;
    };
  }, [id]);

  if (loadError !== null) {
    return <p className="text-sm text-red-600">{loadError}</p>;
  }
  if (saved === null || draft === null) {
    return <p className="text-sm text-muted-foreground">Loading draft…</p>;
  }

  const current = draft;
  const latest = saved;
  const dirty = isDirty(current, latest.draft);

  async function runRequest(
    busy: DraftStatus["busy"],
    url: string,
    method: string,
    body: unknown,
    done: string,
  ) {
    setStatus({ notice: null, error: null, busy });
    const result = await sendJson(url, method, body);
    if (!result.ok) {
      setStatus({ notice: null, error: result.message, busy: null });
      return;
    }
    setSaved(result.body);
    setDraft(result.body.draft);
    setStatus({ notice: done, error: null, busy: null });
  }

  async function remove() {
    setStatus({ notice: null, error: null, busy: "deleting" });
    const response = await fetch(`/api/drafts/${id}`, { method: "DELETE" });
    if (!response.ok) {
      setStatus({ notice: null, error: await messageOf(response), busy: null });
      return;
    }
    router.push("/drafts");
  }

  return (
    <div className="flex flex-col gap-4">
      <p className="text-xs text-muted-foreground">{current.id}</p>
      {current.kind === "pr" ? (
        <PrFields
          draft={current}
          asDraft={asDraft}
          onAsDraftChange={setAsDraft}
          onChange={(patch: Partial<PrDraft>) =>
            setDraft(withPatch(current, patch))
          }
        />
      ) : (
        <ReviewFields
          draft={current}
          onChange={(patch: Partial<ReviewDraft>) =>
            setDraft(withPatch(current, patch))
          }
        />
      )}
      <DraftActionBar
        draft={current}
        dirty={dirty}
        repo={latest.repo}
        status={status}
        onSave={() =>
          runRequest(
            "saving",
            `/api/drafts/${id}`,
            "PUT",
            { hash: latest.hash, ...editableFieldsOf(current) },
            "saved",
          )
        }
        onPost={() =>
          runRequest(
            "posting",
            `/api/drafts/${id}/post`,
            "POST",
            { hash: latest.hash, draft: asDraft },
            "posted",
          )
        }
        onDelete={remove}
      />
    </div>
  );
}

function withPatch<T extends Draft>(draft: T, patch: Partial<T>): T {
  return { ...draft, ...patch };
}

async function sendJson(
  url: string,
  method: string,
  body: unknown,
): Promise<RequestResult> {
  const response = await fetch(url, {
    method,
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
  });
  return readResult(response);
}

async function readResult(response: Response): Promise<RequestResult> {
  if (!response.ok) {
    return { ok: false, message: await messageOf(response) };
  }
  return { ok: true, body: (await response.json()) as Saved };
}

async function messageOf(response: Response): Promise<string> {
  try {
    return ((await response.json()) as { message: string }).message;
  } catch {
    return `request failed (${response.status})`;
  }
}
