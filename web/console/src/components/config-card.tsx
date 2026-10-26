"use client";

import { useEffect, useState } from "react";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import type { ConfigEntry } from "@/lib/print-config";

const COMMAND_KEY = "command";

type ConfigResponse = { code: number; entries: ConfigEntry[]; stderr: string };

export function ConfigCard({ size }: { size: string }) {
  const [config, setConfig] = useState<ConfigResponse | null>(null);
  const [failure, setFailure] = useState<string | null>(null);

  useEffect(() => {
    const load = async () => {
      const response = await fetch(`/api/config?size=${encodeURIComponent(size)}`, { cache: "no-store" });
      const body = (await response.json()) as ConfigResponse & { message?: string };
      if (response.ok) {
        setConfig(body);
      } else {
        setFailure(body.message ?? "Settings unavailable");
      }
    };
    void load();
  }, [size]);

  return (
    <Card>
      <CardHeader>
        <CardTitle>Settings for {size}</CardTitle>
      </CardHeader>
      <CardContent>
        <ConfigBody config={config} failure={failure} />
      </CardContent>
    </Card>
  );
}

function ConfigBody({ config, failure }: { config: ConfigResponse | null; failure: string | null }) {
  if (failure !== null) {
    return <p className="text-sm text-red-500">{failure}</p>;
  }
  if (config === null) {
    return <p className="text-sm text-muted-foreground">Reading settings...</p>;
  }
  if (config.code !== 0) {
    return (
      <div className="flex flex-col gap-2 text-sm">
        <p className="text-red-500">Reading settings failed (exit {config.code})</p>
        <pre className="whitespace-pre-wrap break-all rounded-lg bg-muted/40 p-3 font-mono text-xs">{config.stderr}</pre>
      </div>
    );
  }
  return (
    <dl className="grid grid-cols-[max-content_minmax(0,1fr)] gap-x-4 gap-y-3 text-sm">
      {config.entries.map((entry) => (
        <div key={entry.key} className="contents">
          <dt className="font-medium text-muted-foreground">{entry.key}</dt>
          <dd className="min-w-0 break-all font-mono text-xs">
            {entry.key === COMMAND_KEY ? <CommandValue value={entry.value} /> : entry.value}
          </dd>
        </div>
      ))}
    </dl>
  );
}

function CommandValue({ value }: { value: string }) {
  return (
    <div className="flex items-start gap-2">
      <code className="min-w-0 flex-1 whitespace-pre-wrap break-all rounded-lg bg-muted/40 p-2">{value}</code>
      <Button variant="outline" size="sm" onClick={() => void navigator.clipboard.writeText(value)}>
        Copy
      </Button>
    </div>
  );
}
