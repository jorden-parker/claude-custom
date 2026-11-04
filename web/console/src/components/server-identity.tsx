"use client";

import { useEffect, useState } from "react";
import type { ModelServerHealth } from "@/lib/model-server-health";

const PRESET_FILE = "~/.claude-ollama/presets/models.ini";

export function ServerIdentity() {
  const [health, setHealth] = useState<ModelServerHealth | null>(null);

  useEffect(() => {
    const load = async () => {
      const response = await fetch("/api/server/ping", { cache: "no-store" });
      if (response.ok) {
        setHealth((await response.json()) as ModelServerHealth);
      }
    };
    void load().catch(() => undefined);
  }, []);

  if (health === null) {
    return <p className="text-sm text-muted-foreground">Asking the model server…</p>;
  }
  return (
    <dl className="grid grid-cols-2 gap-x-4 gap-y-1 text-sm [&>dd]:min-w-0 [&>dd]:break-all">
      <dt className="text-muted-foreground">Model server</dt>
      <dd className="font-mono text-xs">{health.url}</dd>
      <dt className="text-muted-foreground">State</dt>
      <dd>{health.state}</dd>
      <dt className="text-muted-foreground">Build</dt>
      <dd className="font-mono text-xs">{health.build ?? "unknown"}</dd>
      <dt className="text-muted-foreground">Presets</dt>
      <dd>
        The server reads <span className="font-mono text-xs">{PRESET_FILE}</span>
      </dd>
    </dl>
  );
}
