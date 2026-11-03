"use client";

import { Label } from "@/components/ui/label";
import { Switch } from "@/components/ui/switch";
import Link from "next/link";
import { useEffect, useState } from "react";
import { StartRunButton } from "@/components/start-run-button";
import { Button } from "@/components/ui/button";
import { ToolStateTable } from "@/components/tool-state-table";
import type { RunSummary } from "@/lib/run-log";
import {
  PERMISSIONS,
  changedAssignments,
  draftsFrom,
  setPermission,
  type Permission,
  type ToolEdit,
  type ToolReport,
  type ToolRow,
} from "@/lib/tool-states";

const POLL_INTERVAL_MS = 1000;

export function ToolsEditor() {
  const [report, setReport] = useState<ToolReport | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [drafts, setDrafts] = useState<Record<string, ToolEdit>>({});
  const [savingId, setSavingId] = useState<string | null>(null);

  const [reloads, setReloads] = useState(0);

  useEffect(() => {
    const loadTools = async () => {
      const response = await fetch("/api/tools", { cache: "no-store" });
      if (!response.ok) {
        setError(((await response.json()) as { message: string }).message);
        return;
      }
      const loaded = (await response.json()) as ToolReport;
      setError(null);
      setReport(loaded);
      setDrafts(draftsFrom(loaded.tools));
    };
    void loadTools();
  }, [reloads]);

  useEffect(() => {
    if (savingId === null) {
      return;
    }
    const finishWhenDone = async () => {
      const response = await fetch("/api/runs", { cache: "no-store" });
      if (!response.ok) {
        return;
      }
      const run = ((await response.json()) as RunSummary[]).find(
        (item) => item.id === savingId,
      );
      if (run !== undefined && run.status !== "running") {
        setSavingId(null);
        setReloads((count) => count + 1);
      }
    };
    const timer = setInterval(() => void finishWhenDone(), POLL_INTERVAL_MS);
    return () => clearInterval(timer);
  }, [savingId]);

  if (error !== null) {
    return (
      <div className="flex flex-col gap-2 text-sm">
        <p className="text-error-foreground">{error}</p>
        <p className="text-muted-foreground">
          Open claude-tools once in a terminal, sync the tool list, then reload
          this page.
        </p>
      </div>
    );
  }
  if (report === null) {
    return <p className="text-sm text-muted-foreground">Loading tools...</p>;
  }

  const assignments = changedAssignments(report.tools, drafts);
  const changeLabel =
    assignments.length === 1 ? "1 change" : `${assignments.length} changes`;

  const changePermission = (name: string, permission: Permission) =>
    setDrafts((current) => ({
      ...current,
      [name]: setPermission(current[name], permission),
    }));

  const changeOff = (name: string, disabled: boolean) =>
    setDrafts((current) => ({
      ...current,
      [name]: { ...current[name], disabled },
    }));

  return (
    <section className="flex flex-col gap-4">
      <div className="flex flex-col gap-1 text-sm">
        <p className="font-mono break-all">{report.path}</p>
        <p className="text-muted-foreground">
          Changes apply to new Claude Code sessions.
        </p>
        <Link href="/history" className="underline">
          History
        </Link>
      </div>
      {report.tools.length === 0 ? (
        <p className="text-sm text-muted-foreground">
          No tools in the catalog.
        </p>
      ) : (
        <ToolStateTable
          rows={report.tools}
          states={permissionsOf(drafts)}
          options={PERMISSIONS}
          isChanged={(name) => isEdited(report.tools, drafts, name)}
          onChange={changePermission}
          aside={(name) =>
            keepOutOfContext(drafts[name], (disabled) =>
              changeOff(name, disabled),
            )
          }
        />
      )}
      {assignments.length === 0 ? null : (
        <div className="sticky bottom-0 flex flex-wrap items-center justify-between gap-3 rounded-xl border bg-background p-3 shadow-sm">
          <span className="text-sm">{changeLabel}</span>
          <div className="flex gap-2">
            <Button
              variant="outline"
              onClick={() => setDrafts(draftsFrom(report.tools))}
              disabled={savingId !== null}
            >
              Discard
            </Button>
            {savingId === null ? (
              <StartRunButton
                command="tools-set"
                params={{ assignments: assignments.join(";") }}
                stay
                onStarted={setSavingId}
              >
                Save
              </StartRunButton>
            ) : (
              <span className="text-sm text-muted-foreground">Saving...</span>
            )}
          </div>
        </div>
      )}
    </section>
  );
}

function permissionsOf(
  drafts: Record<string, ToolEdit>,
): Record<string, Permission> {
  return Object.fromEntries(
    Object.entries(drafts).map(([name, edit]) => [name, edit.permission]),
  );
}

function isEdited(
  rows: readonly ToolRow[],
  drafts: Record<string, ToolEdit>,
  name: string,
): boolean {
  const row = rows.find((candidate) => candidate.name === name);
  const edit = drafts[name];
  return (
    row !== undefined &&
    (edit.permission !== row.permission || edit.disabled !== row.disabled)
  );
}

function keepOutOfContext(edit: ToolEdit, onOff: (disabled: boolean) => void) {
  const keepsOffSwitch =
    edit.permission === "allow" || edit.permission === "ask";
  if (!keepsOffSwitch) {
    return null;
  }
  return (
    <Label className="flex items-center gap-2 text-xs">
      <Switch
        aria-label="Keep out of context"
        checked={edit.disabled}
        onCheckedChange={onOff}
      />
      Keep out of context
    </Label>
  );
}
