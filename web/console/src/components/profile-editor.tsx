"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import {
  ProfileEnvTab,
  ProfileMcpHooksTab,
  ProfileModelTab,
  ProfileToolsTab,
  type ProfileTabProps,
} from "@/components/profile-tabs";
import { Button } from "@/components/ui/button";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import type { ProfileDetail } from "@/lib/profile-base";
import type { ProfileOverride } from "@/lib/profile-rules";

type Loaded = { ok: true; detail: ProfileDetail } | { ok: false; message: string };

export function ProfileEditor({ id }: { id: string }) {
  const [detail, setDetail] = useState<ProfileDetail | null>(null);
  const [saved, setSaved] = useState<ProfileOverride>({});
  const [draft, setDraft] = useState<ProfileOverride>({});
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    void loadDetail(id).then((loaded) => {
      if (!loaded.ok) {
        setError(loaded.message);
        return;
      }
      setDetail(loaded.detail);
      setSaved(loaded.detail.override);
      setDraft(loaded.detail.override);
    });
  }, [id]);

  async function persist(override: ProfileOverride, done: string) {
    setBusy(true);
    const result = await saveDetail(id, override);
    setBusy(false);
    if (!result.ok) {
      setNotice(null);
      setError(result.message);
      return;
    }
    setError(null);
    setNotice(done);
    setSaved(result.override);
    setDraft(result.override);
  }

  if (detail === null) {
    return error === null ? (
      <p className="text-sm text-muted-foreground">Loading profile...</p>
    ) : (
      <p className="text-sm text-error-foreground">{error}</p>
    );
  }

  const tabProps: ProfileTabProps = {
    detail,
    draft,
    saved,
    update: setDraft,
  };
  const dirty = JSON.stringify(draft) !== JSON.stringify(saved);

  return (
    <section className="flex flex-col gap-4">
      <ProfileFacts detail={detail} />
      <Tabs defaultValue="tools">
        <TabsList>
          <TabsTrigger value="tools">Tools</TabsTrigger>
          <TabsTrigger value="model">Sandbox &amp; model</TabsTrigger>
          <TabsTrigger value="mcp">MCP &amp; hooks</TabsTrigger>
          <TabsTrigger value="env">Env</TabsTrigger>
        </TabsList>
        <TabsContent value="tools" className="pt-3">
          <ProfileToolsTab {...tabProps} />
        </TabsContent>
        <TabsContent value="model" className="pt-3">
          <ProfileModelTab {...tabProps} />
        </TabsContent>
        <TabsContent value="mcp" className="pt-3">
          <ProfileMcpHooksTab {...tabProps} />
        </TabsContent>
        <TabsContent value="env" className="pt-3">
          <ProfileEnvTab {...tabProps} />
        </TabsContent>
      </Tabs>
      <SaveBar
        dirty={dirty}
        busy={busy}
        notice={notice}
        error={error}
        onSave={() => void persist(draft, "saved; applies to the next session")}
        onDiscard={() => setDraft(saved)}
        onReset={() => void persist({}, "reset to defaults")}
      />
    </section>
  );
}

function ProfileFacts({ detail }: { detail: ProfileDetail }) {
  return (
    <div className="flex flex-col gap-1 text-sm">
      <p className="font-mono break-all">{detail.base.settingsPath}</p>
      <p className="text-muted-foreground">
        {detail.model === null ? "Your Claude Code settings" : `Model ${detail.model}`}
        {detail.context === null ? "" : `, context ${detail.context}`}
      </p>
      <Link href="/history" className="underline">
        History
      </Link>
    </div>
  );
}

function SaveBar({
  dirty,
  busy,
  notice,
  error,
  onSave,
  onDiscard,
  onReset,
}: {
  dirty: boolean;
  busy: boolean;
  notice: string | null;
  error: string | null;
  onSave: () => void;
  onDiscard: () => void;
  onReset: () => void;
}) {
  return (
    <div className="flex flex-col gap-2">
      {error === null ? null : <p className="text-sm text-error-foreground">{error}</p>}
      <div className="sticky bottom-0 flex flex-wrap items-center justify-between gap-3 rounded-xl border bg-background p-3 shadow-sm">
        <span className="text-sm">{statusText(dirty, notice)}</span>
        <div className="flex gap-2">
          <Button variant="outline" onClick={onReset} disabled={busy}>
            Reset to defaults
          </Button>
          <Button variant="outline" onClick={onDiscard} disabled={busy || !dirty}>
            Discard
          </Button>
          <Button onClick={onSave} disabled={busy || !dirty}>
            Save
          </Button>
        </div>
      </div>
    </div>
  );
}

function statusText(dirty: boolean, notice: string | null): string {
  if (dirty) {
    return "Unsaved changes";
  }
  return notice ?? "No unsaved changes";
}

async function loadDetail(id: string): Promise<Loaded> {
  const response = await fetch(profileUrl(id), { cache: "no-store" });
  if (!response.ok) {
    return { ok: false, message: await responseMessage(response) };
  }
  return { ok: true, detail: (await response.json()) as ProfileDetail };
}

async function saveDetail(
  id: string,
  override: ProfileOverride,
): Promise<{ ok: true; override: ProfileOverride } | { ok: false; message: string }> {
  const response = await fetch(profileUrl(id), {
    method: "PUT",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(override),
  });
  if (!response.ok) {
    return { ok: false, message: await responseMessage(response) };
  }
  return { ok: true, override: ((await response.json()) as { override: ProfileOverride }).override };
}

function profileUrl(id: string): string {
  return `/api/profiles/${encodeURIComponent(id)}`;
}

async function responseMessage(response: Response): Promise<string> {
  const body = (await response.json().catch(() => null)) as { message?: string } | null;
  return body?.message ?? `request failed with status ${response.status}`;
}
