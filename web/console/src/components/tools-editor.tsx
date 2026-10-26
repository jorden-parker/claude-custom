"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { StartRunButton } from "@/components/start-run-button";
import { Button } from "@/components/ui/button";
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
      const run = ((await response.json()) as RunSummary[]).find((item) => item.id === savingId);
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
        <p className="text-red-700 dark:text-red-400">{error}</p>
        <p className="text-muted-foreground">
          Open claude-tools once in a terminal, sync the tool list, then reload this page.
        </p>
      </div>
    );
  }
  if (report === null) {
    return <p className="text-sm text-muted-foreground">Loading tools...</p>;
  }

  const assignments = changedAssignments(report.tools, drafts);
  const changeLabel = assignments.length === 1 ? "1 change" : `${assignments.length} changes`;

  const changePermission = (name: string, permission: Permission) =>
    setDrafts((current) => ({ ...current, [name]: setPermission(current[name], permission) }));

  const changeOff = (name: string, disabled: boolean) =>
    setDrafts((current) => ({ ...current, [name]: { ...current[name], disabled } }));

  return (
    <section className="flex flex-col gap-4">
      <div className="flex flex-col gap-1 text-sm">
        <p className="font-mono break-all">{report.path}</p>
        <p className="text-muted-foreground">Changes apply to new Claude Code sessions.</p>
        <Link href="/history" className="underline">
          History
        </Link>
      </div>
      {report.tools.length === 0 ? (
        <p className="text-sm text-muted-foreground">No tools in the catalog.</p>
      ) : (
        <table className="w-full text-left text-sm">
          <thead>
            <tr className="border-b text-muted-foreground">
              <th className="py-2 pr-3 font-medium">Tool</th>
              <th className="py-2 pr-3 font-medium">Description</th>
              <th className="py-2 pr-3 font-medium">Permission</th>
            </tr>
          </thead>
          <tbody>
            {report.tools.map((tool) => (
              <ToolTableRow
                key={tool.name}
                tool={tool}
                edit={drafts[tool.name]}
                onPermission={(permission) => changePermission(tool.name, permission)}
                onOff={(disabled) => changeOff(tool.name, disabled)}
              />
            ))}
          </tbody>
        </table>
      )}
      {assignments.length === 0 ? null : (
        <div className="sticky bottom-0 flex flex-wrap items-center justify-between gap-3 rounded-xl border bg-background p-3 shadow-sm">
          <span className="text-sm">{changeLabel}</span>
          <div className="flex gap-2">
            <Button variant="outline" onClick={() => setDrafts(draftsFrom(report.tools))} disabled={savingId !== null}>
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

function ToolTableRow({
  tool,
  edit,
  onPermission,
  onOff,
}: {
  tool: ToolRow;
  edit: ToolEdit;
  onPermission: (permission: Permission) => void;
  onOff: (disabled: boolean) => void;
}) {
  const changed = edit.permission !== tool.permission || edit.disabled !== tool.disabled;
  const keepsOffSwitch = edit.permission === "allow" || edit.permission === "ask";
  return (
    <tr className={`border-b align-top ${changed ? "bg-amber-50 dark:bg-amber-950/30" : ""}`}>
      <td className="py-2 pr-3 font-mono">{tool.name}</td>
      <td className="py-2 pr-3 text-muted-foreground">{tool.description}</td>
      <td className="py-2 pr-3">
        <div className="flex flex-col items-start gap-2">
          <div role="group" aria-label={`Permission for ${tool.name}`} className="inline-flex rounded-md border">
            {PERMISSIONS.map((permission) => (
              <button
                key={permission}
                type="button"
                aria-pressed={edit.permission === permission}
                onClick={() => onPermission(permission)}
                className={`px-2 py-1 text-xs first:rounded-l-md last:rounded-r-md ${
                  edit.permission === permission ? "bg-muted font-medium" : "hover:bg-muted/60"
                }`}
              >
                {permission}
              </button>
            ))}
          </div>
          {keepsOffSwitch ? (
            <label className="flex items-center gap-2 text-xs">
              <input
                type="checkbox"
                role="switch"
                aria-label="Keep out of context"
                checked={edit.disabled}
                onChange={(event) => onOff(event.target.checked)}
              />
              Keep out of context
            </label>
          ) : null}
        </div>
      </td>
    </tr>
  );
}
