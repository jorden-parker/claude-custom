"use client";

import { Input } from "@/components/ui/input";
import { Select } from "@/components/ui/select";
import Link from "next/link";
import { Lock } from "lucide-react";
import { useCallback, useEffect, useState } from "react";
import { ServerRestart } from "@/components/server-restart";
import { StartRunButton } from "@/components/start-run-button";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent } from "@/components/ui/card";
import type { ServerSnapshot, ServerVariable } from "@/lib/server-snapshot";
import { serverSetting, validServerValue, type ServerSetting } from "@/lib/server-vars";

type Edits = Record<string, string>;

type Change = { name: string; value: string };

export function ServerSettingsEditor() {
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
    return <p className="text-sm text-error-foreground">{loadError}</p>;
  }
  if (snapshot === null) {
    return (
      <p className="text-sm text-muted-foreground">Reading the LaunchAgent…</p>
    );
  }
  return (
    <ServerSettingsForm
      snapshot={snapshot}
      edits={edits}
      onEdit={(name, value) =>
        setEdits((previous) => ({ ...previous, [name]: value }))
      }
      runId={runId}
      onStarted={setRunId}
      onBack={reload}
    />
  );
}

type ServerSettingsFormProps = {
  snapshot: ServerSnapshot;
  edits: Edits;
  onEdit: (name: string, value: string) => void;
  runId: string | null;
  onStarted: (id: string) => void;
  onBack: () => void;
};

function ServerSettingsForm({
  snapshot,
  edits,
  onEdit,
  runId,
  onStarted,
  onBack,
}: ServerSettingsFormProps) {
  const changes = changesOf(snapshot.variables, edits);
  const hasInvalid = changes.some(
    ({ name, value }) => !validServerValue(name, value),
  );
  const assignments = changes
    .map(({ name, value }) => `${name}=${value}`)
    .join(",");

  return (
    <div className="flex flex-col gap-4">
      <p className="font-mono text-xs text-muted-foreground">
        {snapshot.path}
        {snapshot.exists ? "" : " (not created yet)"}
      </p>
      <Link href="/history" className="text-sm underline">
        History
      </Link>
      {snapshot.conflicts.map((text) => (
        <Card key={text}>
          <CardContent className="text-sm text-warning-foreground">
            {text}
          </CardContent>
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
          disabled={changes.length === 0 || hasInvalid}
          onStarted={onStarted}
        >
          Save and reload
        </StartRunButton>
        <StartRunButton
          command="server-apply"
          params={{}}
          stay
          onStarted={onStarted}
        >
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
  const setting = serverSetting(variable.name);
  const changed = setting !== undefined && value !== currentText(variable);

  return (
    <li
      className={`flex flex-col gap-2 rounded-lg border p-3 ${changed ? "bg-muted/60" : ""}`}
    >
      <VariableHeader variable={variable} setting={setting} />
      <p className="text-sm text-muted-foreground">
        {setting?.help ?? variable.summary}
      </p>
      <dl className="grid grid-cols-2 gap-x-3 font-mono text-xs [&>dd]:min-w-0 [&>dd]:break-all">
        <dt className="text-muted-foreground">current</dt>
        <dd>{variable.set ? variable.current : "unset"}</dd>
        <dt className="text-muted-foreground">recommended</dt>
        <dd>{variable.recommended || "none"}</dd>
      </dl>
      {setting === undefined ? (
        <p className="flex items-center gap-2 text-xs text-muted-foreground">
          <Lock className="size-3" />
          edit ollama/server.ini
        </p>
      ) : (
        <SettingInput
          setting={setting}
          value={value}
          invalid={changed && !validServerValue(setting.key, value)}
          onEdit={onEdit}
        />
      )}
    </li>
  );
}

function VariableHeader({
  variable,
  setting,
}: {
  variable: ServerVariable;
  setting: ServerSetting | undefined;
}) {
  return (
    <div className="flex flex-wrap items-center gap-2">
      {setting === undefined ? null : (
        <span className="text-sm font-medium">{setting.label}</span>
      )}
      <span className="font-mono text-xs text-muted-foreground">
        {variable.name}
      </span>
      {isDifferent(variable) ? (
        <Badge variant="outline" className="text-warning-foreground">
          differs
        </Badge>
      ) : null}
    </div>
  );
}

function SettingInput({
  setting,
  value,
  invalid,
  onEdit,
}: {
  setting: ServerSetting;
  value: string;
  invalid: boolean;
  onEdit: (name: string, value: string) => void;
}) {
  const invalidRing = invalid ? "ring-2 ring-error-border" : "";
  if (setting.input.kind === "choice") {
    const choices = value === "" ? ["", ...setting.input.choices] : setting.input.choices;
    return (
      <Select
        aria-label={setting.key}
        aria-invalid={invalid}
        value={value}
        onChange={(event) => onEdit(setting.key, event.target.value)}
        className={`font-mono ${invalidRing}`}
      >
        {choices.map((choice) => (
          <option key={choice} value={choice}>
            {choice === "" ? "unset" : choice}
          </option>
        ))}
      </Select>
    );
  }
  return (
    <Input
      type="number"
      aria-label={setting.key}
      aria-invalid={invalid}
      min={setting.input.min}
      max={setting.input.max}
      step={1}
      value={value}
      onChange={(event) => onEdit(setting.key, event.target.value)}
      className={`font-mono ${invalidRing}`}
    />
  );
}

function isDifferent(variable: ServerVariable): boolean {
  return (
    variable.recommended !== "" &&
    currentText(variable) !== variable.recommended
  );
}

function currentText(variable: ServerVariable): string {
  return variable.set ? variable.current : "";
}

function changesOf(variables: ServerVariable[], edits: Edits): Change[] {
  return variables.flatMap((variable) => {
    const value = edits[variable.name];
    return serverSetting(variable.name) !== undefined &&
      value !== undefined &&
      value !== currentText(variable)
      ? [{ name: variable.name, value }]
      : [];
  });
}
