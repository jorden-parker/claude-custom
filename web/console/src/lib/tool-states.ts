export const PERMISSIONS = ["default", "allow", "ask", "deny"] as const;

export type Permission = (typeof PERMISSIONS)[number];

export type ToolRow = {
  name: string;
  description: string;
  promptsByDefault: boolean;
  permission: Permission;
  disabled: boolean;
};

export type ToolReport = { path: string; tools: ToolRow[] };

export type ToolEdit = { permission: Permission; disabled: boolean };

export function assignmentText(name: string, permission: Permission, disabled: boolean): string | null {
  if (disabled && (permission === "default" || permission === "deny")) {
    return null;
  }
  return disabled ? `${name}=${permission},off` : `${name}=${permission}`;
}

export function setPermission(edit: ToolEdit, permission: Permission): ToolEdit {
  const keepsOff = permission === "allow" || permission === "ask";
  return { permission, disabled: keepsOff && edit.disabled };
}

export function draftsFrom(rows: readonly ToolRow[]): Record<string, ToolEdit> {
  return Object.fromEntries(rows.map((row) => [row.name, { permission: row.permission, disabled: row.disabled }]));
}

export function changedAssignments(rows: readonly ToolRow[], drafts: Record<string, ToolEdit>): string[] {
  return rows.flatMap((row) => {
    const draft = drafts[row.name];
    if (draft.permission === row.permission && draft.disabled === row.disabled) {
      return [];
    }
    const text = assignmentText(row.name, draft.permission, draft.disabled);
    return text === null ? [] : [text];
  });
}
