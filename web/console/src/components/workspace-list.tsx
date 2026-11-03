"use client";

import { Alert, AlertDescription } from "@/components/ui/alert";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Switch } from "@/components/ui/switch";
import { useEffect, useState } from "react";
import { Button } from "@/components/ui/button";
import { levelBoxClass } from "@/lib/level-style";

type ProjectSkill = {
  name: string;
  description: string | null;
  modelInvocable: boolean;
};

type Workspace = {
  path: string;
  trusted: boolean;
  exists: boolean;
  skills: ProjectSkill[];
};

type WorkspaceState = {
  path: string;
  workspaces: Workspace[];
};

type SkillCheck = {
  version: string | null;
  discovered: string[];
  missing: string[];
  error: string | null;
};

const SAVED_MESSAGE =
  "saved; applies to the next claude-ollama launch in that folder";
const NOT_ABSOLUTE_MESSAGE = "expected an absolute path (starting with /)";
const CHECK_HINT =
  "Claude Code skipped these; check each SKILL.md frontmatter (quote a description with a colon, use a plain lowercase name).";

export function WorkspaceList() {
  const [state, setState] = useState<WorkspaceState | null>(null);
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    const loadState = async () => {
      const response = await fetch("/api/workspaces", { cache: "no-store" });
      if (!response.ok) {
        setError(await responseMessage(response));
        return;
      }
      setState((await response.json()) as WorkspaceState);
    };
    void loadState();
  }, []);

  async function setTrust(path: string, trusted: boolean) {
    setSaving(true);
    setMessage(null);
    const response = await fetch("/api/workspaces", {
      method: "PUT",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ path, trusted }),
    });
    setSaving(false);
    if (!response.ok) {
      setError(await responseMessage(response));
      return;
    }
    setError(null);
    setState((await response.json()) as WorkspaceState);
    setMessage(SAVED_MESSAGE);
  }

  return (
    <div className="flex flex-col gap-6">
      <Alert className={levelBoxClass("info")}>
        <AlertDescription className="text-inherit">
          claude-ollama keeps its own trust list, apart from plain claude. A
          project&apos;s <code>.claude/skills</code>, settings and hooks load
          only in a trusted folder, so an untrusted folder shows no project
          skills in the <code>/</code> menu.
        </AlertDescription>
      </Alert>
      <FilePath path={state?.path ?? null} />
      {error ? <p className="text-sm text-error-foreground">{error}</p> : null}

      <AddWorkspaceForm
        disabled={saving}
        onAdd={(path) => void setTrust(path, true)}
      />

      <WorkspaceRows
        workspaces={state?.workspaces ?? []}
        loaded={state !== null}
        disabled={saving}
        onToggle={(workspace) =>
          void setTrust(workspace.path, !workspace.trusted)
        }
      />

      {message ? (
        <p className="text-sm text-success-foreground">{message}</p>
      ) : null}
    </div>
  );
}

function FilePath({ path }: { path: string | null }) {
  if (path === null) {
    return null;
  }
  return <p className="text-sm text-muted-foreground">File: {path}</p>;
}

function AddWorkspaceForm({
  disabled,
  onAdd,
}: {
  disabled: boolean;
  onAdd: (path: string) => void;
}) {
  const [draft, setDraft] = useState("");
  const trimmed = draft.trim();
  const draftError =
    trimmed !== "" && !trimmed.startsWith("/") ? NOT_ABSOLUTE_MESSAGE : null;
  const blocked = disabled || trimmed === "" || draftError !== null;

  return (
    <form
      className="flex items-start gap-2"
      onSubmit={(event) => {
        event.preventDefault();
        if (!blocked) {
          onAdd(trimmed);
          setDraft("");
        }
      }}
    >
      <div className="flex grow flex-col gap-1">
        <Input
          aria-label="Trust a folder"
          aria-invalid={draftError !== null}
          value={draft}
          onChange={(event) => setDraft(event.target.value)}
          placeholder="/Users/you/src/project"
          className={`h-auto px-3 py-2 font-mono ${draftError ? "border-error-border ring-2 ring-error-border" : ""}`}
        />
        {draftError ? (
          <span className="text-xs text-error-foreground">{draftError}</span>
        ) : null}
      </div>
      <Button type="submit" variant="outline" disabled={blocked}>
        Trust
      </Button>
    </form>
  );
}

function WorkspaceRows({
  workspaces,
  loaded,
  disabled,
  onToggle,
}: {
  workspaces: Workspace[];
  loaded: boolean;
  disabled: boolean;
  onToggle: (workspace: Workspace) => void;
}) {
  if (loaded && workspaces.length === 0) {
    return (
      <p className="text-sm text-muted-foreground">
        No folders yet. Launch claude-ollama in a project, or trust one above.
      </p>
    );
  }
  return (
    <ul className="flex flex-col divide-y rounded-md border">
      {workspaces.map((workspace) => (
        <WorkspaceRow
          key={workspace.path}
          workspace={workspace}
          disabled={disabled}
          onToggle={onToggle}
        />
      ))}
    </ul>
  );
}

function WorkspaceRow({
  workspace,
  disabled,
  onToggle,
}: {
  workspace: Workspace;
  disabled: boolean;
  onToggle: (workspace: Workspace) => void;
}) {
  return (
    <li className="flex flex-col gap-2 px-4 py-3">
      <Label className="flex flex-wrap items-center gap-3">
        <Switch
          aria-label={workspace.path}
          checked={workspace.trusted}
          disabled={disabled}
          onCheckedChange={() => onToggle(workspace)}
        />
        <span className="min-w-0 break-all font-mono">{workspace.path}</span>
        <TrustBadge workspace={workspace} />
      </Label>
      <SkillList workspace={workspace} />
      {workspace.exists && workspace.trusted ? (
        <SkillCheckPanel workspace={workspace} />
      ) : null}
    </li>
  );
}

function SkillCheckPanel({ workspace }: { workspace: Workspace }) {
  const [check, setCheck] = useState<SkillCheck | null>(null);
  const [failure, setFailure] = useState<string | null>(null);
  const [checking, setChecking] = useState(false);

  async function runCheck() {
    setChecking(true);
    setCheck(null);
    setFailure(null);
    const response = await fetch("/api/workspaces/check", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ path: workspace.path }),
    });
    setChecking(false);
    if (!response.ok) {
      setFailure(await responseMessage(response));
      return;
    }
    setCheck((await response.json()) as SkillCheck);
  }

  return (
    <div className="flex flex-col gap-2 pl-7">
      <div>
        <Button
          type="button"
          variant="outline"
          size="sm"
          disabled={checking}
          onClick={() => void runCheck()}
          aria-label={`Check skills in ${workspace.path}`}
        >
          {checking ? "Checking…" : "Check skills"}
        </Button>
      </div>
      {checking ? (
        <p className="text-xs text-muted-foreground">
          Starting claude-ollama in this folder to read the skills it discovers.
          Up to two minutes.
        </p>
      ) : null}
      {failure ? (
        <p className="text-sm text-error-foreground">{failure}</p>
      ) : null}
      {check ? <SkillCheckReport check={check} /> : null}
    </div>
  );
}

function SkillCheckReport({ check }: { check: SkillCheck }) {
  const version = check.version ?? "unknown version";
  if (check.error !== null) {
    return (
      <Alert className={levelBoxClass("error")}>
        <AlertDescription className="text-inherit">
          Claude Code {version}: {check.error}
        </AlertDescription>
      </Alert>
    );
  }
  if (check.missing.length > 0) {
    return (
      <Alert className={levelBoxClass("warn")}>
        <AlertDescription className="text-inherit">
          <p>
            Claude Code {version} found {check.discovered.length} skills but not{" "}
            {check.missing.map((name) => `/${name}`).join(", ")}.
          </p>
          <p className="mt-1 text-xs">{CHECK_HINT}</p>
        </AlertDescription>
      </Alert>
    );
  }
  return (
    <Alert className={levelBoxClass("ok")}>
      <AlertDescription className="text-inherit">
        Claude Code {version} found every project skill here. Skills available:{" "}
        {check.discovered.map((name) => `/${name}`).join(", ") || "none"}.
      </AlertDescription>
    </Alert>
  );
}

function TrustBadge({ workspace }: { workspace: Workspace }) {
  if (!workspace.exists) {
    return <Badge tone="warn">folder missing</Badge>;
  }
  return workspace.trusted ? (
    <Badge tone="ok">trusted</Badge>
  ) : (
    <Badge tone="warn">untrusted</Badge>
  );
}

function SkillList({ workspace }: { workspace: Workspace }) {
  if (!workspace.exists) {
    return null;
  }
  if (workspace.skills.length === 0) {
    return (
      <p className="pl-7 text-xs text-muted-foreground">
        No project skills under .claude/skills
      </p>
    );
  }
  return (
    <ul
      className="flex flex-wrap gap-2 pl-7"
      aria-label={`Skills in ${workspace.path}`}
    >
      {workspace.skills.map((skill) => (
        <li
          key={skill.name}
          className="rounded bg-muted px-2 py-0.5 text-xs"
          title={skill.description ?? ""}
        >
          /{skill.name}
          {skill.modelInvocable ? "" : " (user only)"}
        </li>
      ))}
    </ul>
  );
}

function Badge({ tone, children }: { tone: "ok" | "warn"; children: string }) {
  const toneClass =
    tone === "ok"
      ? "bg-success text-success-foreground"
      : "bg-warning text-warning-foreground";
  return (
    <span className={`rounded px-2 py-0.5 text-xs ${toneClass}`}>
      {children}
    </span>
  );
}

async function responseMessage(response: Response): Promise<string> {
  try {
    return ((await response.json()) as { message: string }).message;
  } catch {
    return `request failed (${response.status})`;
  }
}
