"use client";

import { useEffect, useState } from "react";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import type { LeaseHolder, Residency } from "@/lib/residency";
import { PROMOTABLE_RUNGS } from "@/lib/residency";

type PromoteReply = { ok: true; pid: number } | { message: string };

type Loaded =
  | { residency: Residency; error: null }
  | { residency: null; error: string }
  | { residency: null; error: null };

type Promotion = { notice: string | null; error: string | null };

export function ResidencyCard() {
  const loaded = useResidency();
  const [promotion, setPromotion] = useState<Promotion>({
    notice: null,
    error: null,
  });

  return (
    <Card>
      <CardHeader>
        <CardTitle>Residency</CardTitle>
      </CardHeader>
      <CardContent className="flex flex-col gap-3">
        <LoadedResidency
          loaded={loaded}
          onPromote={async (rung) => setPromotion(await promoteRung(rung))}
        />
        {promotion.error !== null ? (
          <p className="text-sm text-error-foreground">{promotion.error}</p>
        ) : null}
        {promotion.notice !== null ? (
          <p className="text-sm text-success-foreground">{promotion.notice}</p>
        ) : null}
      </CardContent>
    </Card>
  );
}

function useResidency(): Loaded {
  const [loaded, setLoaded] = useState<Loaded>({
    residency: null,
    error: null,
  });
  useEffect(() => {
    const loadResidency = async () => {
      const response = await fetch("/api/lease", { cache: "no-store" });
      const body = await response.json();
      if (!response.ok) {
        setLoaded({
          residency: null,
          error: (body as { message: string }).message,
        });
        return;
      }
      setLoaded({ residency: body as Residency, error: null });
    };
    void loadResidency();
  }, []);
  return loaded;
}

async function promoteRung(rung: string): Promise<Promotion> {
  const response = await fetch("/api/lease/promote", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ rung }),
  });
  const reply = (await response.json()) as PromoteReply;
  if (!response.ok || !("ok" in reply)) {
    const error =
      "message" in reply
        ? reply.message
        : `promote failed with ${response.status}`;
    return { notice: null, error };
  }
  return {
    notice: `Promotion queued: ${rung} recovers at the next handoff relaunch (pid ${reply.pid})`,
    error: null,
  };
}

type LoadedResidencyProps = {
  loaded: Loaded;
  onPromote: (rung: string) => Promise<void>;
};

function LoadedResidency({ loaded, onPromote }: LoadedResidencyProps) {
  if (loaded.error !== null) {
    return <p className="text-sm text-error-foreground">{loaded.error}</p>;
  }
  if (loaded.residency === null) {
    return <p className="text-sm text-muted-foreground">Reading the lease…</p>;
  }
  return (
    <ResidencyDetails residency={loaded.residency} onPromote={onPromote} />
  );
}

type ResidencyDetailsProps = {
  residency: Residency;
  onPromote: (rung: string) => Promise<void>;
};

function ResidencyDetails({ residency, onPromote }: ResidencyDetailsProps) {
  const promotable = PROMOTABLE_RUNGS.some((rung) => rung === residency.rung);
  return (
    <>
      <HolderList holders={residency.holders} />
      <p className="text-sm">Rung: {residency.rung ?? "none"}</p>
      <p className="text-sm">Fit: {residency.fit ?? "not measured yet"}</p>
      <div>
        <Button
          type="button"
          size="sm"
          disabled={!promotable}
          onClick={() => void onPromote(residency.rung ?? "")}
        >
          Promote back up
        </Button>
      </div>
    </>
  );
}

function HolderList({ holders }: { holders: LeaseHolder[] }) {
  if (holders.length === 0) {
    return <p className="text-sm text-muted-foreground">No lease holders</p>;
  }
  return (
    <ul className="flex flex-col gap-1">
      {holders.map((holder) => (
        <li key={holder.pid} className="flex items-baseline gap-2 text-sm">
          <span className="font-medium">{holder.name}</span>
          <span className="font-mono text-xs text-muted-foreground">
            {`pid ${holder.pid} · ${holder.model ?? "-"}`}
          </span>
          {holder.state === "stale" ? (
            <span className="text-xs text-muted-foreground">stale</span>
          ) : null}
        </li>
      ))}
    </ul>
  );
}
