"use client";

import { Lock } from "lucide-react";
import { useCallback, useEffect, useState } from "react";
import { ServerRestart } from "@/components/server-restart";
import { StartRunButton } from "@/components/start-run-button";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent } from "@/components/ui/card";
import type { ServerSnapshot, ServerVariable } from "@/lib/server-snapshot";
import { EDITABLE_VARIABLES, validServerValue } from "@/lib/server-vars";

const APP_CONFLICT_MARKER = "the Ollama app is running";

type Edits = Record<string, string>;

type Change = { name: string; value: string };

export function ServerEnvEditor() {
  const [reloadCount, setReloadCount] = useState(0);
  const [snapshot, setSnapshot] = useState<ServerSnapshot | null>(null);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [edits, setEdits] = useState<Edits>({});
  const [runId, setRunId] = useState<string | null>(null);
  const reload = useCallback(() => setReloadCount((count) => count + 1), []);

  useEffect(() => {
    const loadSnapshot = async () => {
      const response = await fetch("/api/server", { cache: "no-store" });
      const body = await response.json();
      if (!response.ok) {
        setLoadError((body as { message: string }).message);
        return;
      }
      setSnapshot(body as ServerSnapshot);
      setLoadError(null);
      setEdits({});
    };
    void loadSnapshot();
  }, [reloadCount]);

  if (loadError !== null) {
    return <p className="text-sm text-red-700 dark:text-red-400">{loadError}</p>;
  }
  if (snapshot === null) {
    return <p className="text-sm text-muted-foreground">Reading the LaunchAgent…</p>;
  }
  return (
    <ServerEnvForm
      snapshot={snapshot}
      edits={edits}
      onEdit={(name, value) => setEdits((previous) => ({ ...previous, [name]: value }))}
      runId={runId}
      onStarted={setRunId}
      onBack={reload}
    />
  );
}

type ServerEnvFormProps = {
  snapshot: ServerSnapshot;
  edits: Edits;
  onEdit: (name: string, value: string) => void;
  runId: string | null;
  onStarted: (id: string) => void;
  onBack: () => void;
};

function ServerEnvForm({ snapshot, edits, onEdit, runId, onStarted, onBack }: ServerEnvFormProps) {
  const changes = changesOf(snapshot.variables, edits);
  const hasInvalid = changes.some(({ name, value }) => !validServerValue(name, value));
  const appRunning = snapshot.conflicts.some((text) => text.includes(APP_CONFLICT_MARKER));
  const assignments = changes.map(({ name, value }) => `${name}=${value}`).join(",");

  return (
    <div className="flex flex-col gap-4">
      <p className="font-mono text-xs text-muted-foreground">
        {snapshot.path}
        {snapshot.exists ? "" : " (not created yet)"}
      </p>
      {snapshot.conflicts.map((text) => (
        <Card key={text}>
          <CardContent className="text-sm text-amber-700 dark:text-amber-400">{text}</CardContent>
        </Card>
      ))}
      <ul className="flex flex-col gap-3">
        {snapshot.variables.map((variable) => (
          <VariableRow
            key={variable.name}
            variable={variable}
            value={edits[variable.name] ?? currentText(variable)}
            onEdit={onEdit}
          />
        ))}
      </ul>
      <div className="sticky bottom-0 flex flex-wrap items-center gap-3 border-t bg-background py-3">
        <span className="text-sm">
          {changes.length} {changes.length === 1 ? "change" : "changes"}
        </span>
        <StartRunButton
          command="server-set"
          params={{ assignments }}
          stay
          disabled={changes.length === 0 || hasInvalid || appRunning}
          onStarted={onStarted}
        >
          Save and reload
        </StartRunButton>
        <StartRunButton command="server-apply" params={{}} stay disabled={appRunning} onStarted={onStarted}>
          Apply recommended
        </StartRunButton>
      </div>
      {runId === null ? null : <ServerRestart runId={runId} onBack={onBack} />}
    </div>
  );
}

function VariableRow({
  variable,
  value,
  onEdit,
}: {
  variable: ServerVariable;
  value: string;
  onEdit: (name: string, value: string) => void;
}) {
  const editable = EDITABLE_VARIABLES.has(variable.name);
  const changed = editable && value !== currentText(variable);

  return (
    <li className={`flex flex-col gap-2 rounded-lg border p-3 ${changed ? "bg-muted/60" : ""}`}>
      <VariableHeader variable={variable} />
      <p className="text-sm text-muted-foreground">{variable.summary}</p>
      <dl className="grid grid-cols-2 gap-x-3 font-mono text-xs">
        <dt className="text-muted-foreground">current</dt>
        <dd>{variable.set ? variable.current : "unset"}</dd>
        <dt className="text-muted-foreground">recommended</dt>
        <dd>{variable.recommended || "none"}</dd>
      </dl>
      {editable ? (
        <ValueInput name={variable.name} value={value} invalid={changed && !validServerValue(variable.name, value)} onEdit={onEdit} />
      ) : (
        <p className="flex items-center gap-2 text-xs text-muted-foreground">
          <Lock className="size-3" />
          edit with `claude-custom agent`
        </p>
      )}
    </li>
  );
}

function VariableHeader({ variable }: { variable: ServerVariable }) {
  return (
    <div className="flex flex-wrap items-center gap-2">
      <span className="font-mono text-sm font-medium">{variable.name}</span>
      {isDifferent(variable) ? (
        <Badge variant="outline" className="text-amber-700 dark:text-amber-400">
          differs
        </Badge>
      ) : null}
    </div>
  );
}

function ValueInput({
  name,
  value,
  invalid,
  onEdit,
}: {
  name: string;
  value: string;
  invalid: boolean;
  onEdit: (name: string, value: string) => void;
}) {
  return (
    <input
      aria-label={name}
      aria-invalid={invalid}
      value={value}
      onChange={(event) => onEdit(name, event.target.value)}
      className={`rounded-md border bg-background px-2 py-1 font-mono text-sm ${invalid ? "ring-2 ring-red-500" : ""}`}
    />
  );
}

function isDifferent(variable: ServerVariable): boolean {
  return variable.recommended !== "" && currentText(variable) !== variable.recommended;
}

function currentText(variable: ServerVariable): string {
  return variable.set ? variable.current : "";
}

function changesOf(variables: ServerVariable[], edits: Edits): Change[] {
  return variables.flatMap((variable) => {
    const value = edits[variable.name];
    return EDITABLE_VARIABLES.has(variable.name) && value !== undefined && value !== currentText(variable)
      ? [{ name: variable.name, value }]
      : [];
  });
}
