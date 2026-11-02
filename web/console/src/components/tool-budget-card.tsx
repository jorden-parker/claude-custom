"use client";

import { useEffect, useState } from "react";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { useProfileSummaries } from "@/components/use-profile-summaries";
import type { ProfileOverride } from "@/lib/profile-rules";
import type { ProfileSummary } from "@/lib/profiles";
import {
  applySuggestion,
  budgetBars,
  costText,
  savesText,
  type ToolBudgetReport,
  type ToolBudgetRow,
} from "@/lib/tool-budget";

type Loaded =
  | { report: ToolBudgetReport; error: null }
  | { report: null; error: string }
  | { report: null; error: null };

type ProfileDetailReply = {
  override: ProfileOverride;
  base: { tools: { name: string }[] };
};

type ApplyOutcome = { notice: string | null; error: string | null };

export function ToolBudgetCard() {
  const loaded = useToolBudget();
  const { profiles } = useProfileSummaries();
  const [confirming, setConfirming] = useState<ProfileSummary | null>(null);
  const [outcome, setOutcome] = useState<ApplyOutcome>({
    notice: null,
    error: null,
  });

  return (
    <Card>
      <CardHeader>
        <CardTitle>Tool budget</CardTitle>
      </CardHeader>
      <CardContent className="flex flex-col gap-3">
        <LoadedBudget
          loaded={loaded}
          profiles={profiles ?? []}
          confirming={confirming}
          onAsk={setConfirming}
          onConfirm={async (profile, drop) => {
            setConfirming(null);
            setOutcome(await applyToProfile(profile, drop));
          }}
        />
        {outcome.error !== null ? (
          <p className="text-sm text-error-foreground">{outcome.error}</p>
        ) : null}
        {outcome.notice !== null ? (
          <p className="text-sm text-success-foreground">{outcome.notice}</p>
        ) : null}
      </CardContent>
    </Card>
  );
}

function useToolBudget(): Loaded {
  const [loaded, setLoaded] = useState<Loaded>({ report: null, error: null });
  useEffect(() => {
    const loadBudget = async () => {
      const response = await fetch("/api/tool-budget", { cache: "no-store" });
      const body = await response.json();
      if (!response.ok) {
        setLoaded({
          report: null,
          error: (body as { message: string }).message,
        });
        return;
      }
      setLoaded({ report: body as ToolBudgetReport, error: null });
    };
    void loadBudget();
  }, []);
  return loaded;
}

async function applyToProfile(
  profile: ProfileSummary,
  drop: string[],
): Promise<ApplyOutcome> {
  const url = `/api/profiles/${profile.id}`;
  const detailResponse = await fetch(url, { cache: "no-store" });
  if (!detailResponse.ok) {
    return { notice: null, error: await replyMessage(detailResponse) };
  }
  const detail = (await detailResponse.json()) as ProfileDetailReply;
  const toolNames = detail.base.tools.map((tool) => tool.name);
  const { override, applied, skipped } = applySuggestion(
    detail.override,
    drop,
    toolNames,
  );
  const saveResponse = await fetch(url, {
    method: "PUT",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(override),
  });
  if (!saveResponse.ok) {
    return { notice: null, error: await replyMessage(saveResponse) };
  }
  return { notice: appliedText(profile, applied, skipped), error: null };
}

async function replyMessage(response: Response): Promise<string> {
  const body = (await response.json().catch(() => null)) as {
    message?: string;
  } | null;
  return body?.message ?? `profile request failed with ${response.status}`;
}

function appliedText(
  profile: ProfileSummary,
  applied: string[],
  skipped: string[],
): string {
  const turnedOff =
    applied.length === 0
      ? "nothing to turn off"
      : `turned off ${applied.join(", ")}`;
  const left =
    skipped.length === 0
      ? ""
      : `; skipped ${skipped.join(", ")} (not a profile tool)`;
  return `${profile.title}: ${turnedOff}${left}`;
}

type LoadedBudgetProps = {
  loaded: Loaded;
  profiles: ProfileSummary[];
  confirming: ProfileSummary | null;
  onAsk: (profile: ProfileSummary | null) => void;
  onConfirm: (profile: ProfileSummary, drop: string[]) => Promise<void>;
};

function LoadedBudget({
  loaded,
  profiles,
  confirming,
  onAsk,
  onConfirm,
}: LoadedBudgetProps) {
  if (loaded.error !== null) {
    return <p className="text-sm text-error-foreground">{loaded.error}</p>;
  }
  if (loaded.report === null) {
    return (
      <p className="text-sm text-muted-foreground">
        Joining the proxy and telemetry logs…
      </p>
    );
  }
  const { report } = loaded;
  return (
    <>
      <p className="text-sm text-muted-foreground">
        Last {report.since_days} days, {report.requests} requests
      </p>
      <BudgetTable rows={report.rows} />
      <SuggestionLine report={report} />
      <p className="text-xs text-muted-foreground">
        Protected ({report.protected_source}): {report.protected.join(", ")}
      </p>
      <ApplyButtons
        profiles={profiles.filter((profile) => profile.kind === "ollama")}
        drop={report.suggest.drop}
        onAsk={onAsk}
      />
      {confirming !== null ? (
        <ApplyConfirm
          profile={confirming}
          drop={report.suggest.drop}
          onConfirm={() => void onConfirm(confirming, report.suggest.drop)}
          onCancel={() => onAsk(null)}
        />
      ) : null}
    </>
  );
}

function BudgetTable({ rows }: { rows: ToolBudgetRow[] }) {
  if (rows.length === 0) {
    return (
      <p className="text-sm text-muted-foreground">
        No requests or calls in the window
      </p>
    );
  }
  const bars = new Map(budgetBars(rows).map((bar) => [bar.tool, bar.share]));
  return (
    <div className="flex flex-col gap-1 font-mono text-xs">
      <div className="grid grid-cols-[minmax(8rem,1fr)_4rem_4rem_5rem_3rem_8rem_3fr] gap-2 text-muted-foreground">
        <span>tool</span>
        <span className="text-right">schema</span>
        <span className="text-right">requests</span>
        <span className="text-right">per session</span>
        <span className="text-right">calls</span>
        <span>cost</span>
        <span />
      </div>
      {rows.map((row) => (
        <div
          key={row.tool}
          data-tool={row.tool}
          className="grid grid-cols-[minmax(8rem,1fr)_4rem_4rem_5rem_3rem_8rem_3fr] items-center gap-2"
        >
          <span className="truncate">{row.tool}</span>
          <span className="text-right">{row.schema_bytes}</span>
          <span className="text-right">{row.requests}</span>
          <span className="text-right">{row.session_bytes}</span>
          <span className="text-right">{row.calls}</span>
          <span>{costText(row)}</span>
          <span className="h-2 rounded bg-muted">
            <span
              data-share={bars.get(row.tool) ?? 0}
              className="block h-2 rounded bg-foreground/60"
              style={{
                width: `${Math.round((bars.get(row.tool) ?? 0) * 100)}%`,
              }}
            />
          </span>
        </div>
      ))}
    </div>
  );
}

function SuggestionLine({ report }: { report: ToolBudgetReport }) {
  if (report.suggest.drop.length === 0) {
    return <p className="text-sm">Nothing to drop</p>;
  }
  return (
    <p className="text-sm">
      Drop {report.suggest.drop.join(", ")} ({savesText(report.suggest)})
    </p>
  );
}

type ApplyButtonsProps = {
  profiles: ProfileSummary[];
  drop: string[];
  onAsk: (profile: ProfileSummary) => void;
};

function ApplyButtons({ profiles, drop, onAsk }: ApplyButtonsProps) {
  return (
    <div className="flex flex-wrap gap-2">
      {profiles.map((profile) => (
        <Button
          key={profile.id}
          type="button"
          size="sm"
          variant="outline"
          disabled={drop.length === 0}
          onClick={() => onAsk(profile)}
        >
          Apply suggestion to {profile.title}
        </Button>
      ))}
    </div>
  );
}

type ApplyConfirmProps = {
  profile: ProfileSummary;
  drop: string[];
  onConfirm: () => void;
  onCancel: () => void;
};

function ApplyConfirm({
  profile,
  drop,
  onConfirm,
  onCancel,
}: ApplyConfirmProps) {
  return (
    <div className="flex flex-col gap-2 rounded-xl bg-muted p-3">
      <p className="text-sm font-medium">
        Turn these tools off in {profile.title}?
      </p>
      <ul className="flex flex-col gap-1 font-mono text-xs">
        {drop.map((name) => (
          <li key={name}>{name}</li>
        ))}
      </ul>
      <div className="flex gap-2">
        <Button type="button" size="sm" onClick={onConfirm}>
          Turn these off
        </Button>
        <Button type="button" size="sm" variant="outline" onClick={onCancel}>
          Cancel
        </Button>
      </div>
    </div>
  );
}
