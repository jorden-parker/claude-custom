"use client";

import Link from "next/link";
import {
  PROFILE_ENV_FIELDS,
  envFieldsByGroup,
  type GroupedEnvFields,
  type ProfileEnvField,
} from "@/lib/profile-rules";
import type { ProfileSummary } from "@/lib/profiles";
import { useProfileSummaries } from "@/components/use-profile-summaries";

export function SettingsOverview() {
  const { profiles, error } = useProfileSummaries();

  if (error !== null) {
    return <p className="text-sm text-error-foreground">{error}</p>;
  }
  if (profiles === null) {
    return <p className="text-sm text-muted-foreground">Loading profiles...</p>;
  }
  return (
    <SwitchTable
      profiles={profiles}
      groups={envFieldsByGroup(PROFILE_ENV_FIELDS)}
    />
  );
}

function SwitchTable({
  profiles,
  groups,
}: {
  profiles: ProfileSummary[];
  groups: GroupedEnvFields[];
}) {
  return (
    <table className="w-full text-left text-sm">
      <thead>
        <tr className="border-b text-muted-foreground">
          <th className="py-2 pr-3 font-medium">Key</th>
          <th className="py-2 pr-3 font-medium">Label</th>
          <th className="py-2 pr-3 font-medium">Default</th>
          {profiles.map((profile) => (
            <th key={profile.id} className="py-2 pr-3 font-medium">
              <Link
                href={`/profiles/${profile.id}`}
                className="underline-offset-2 hover:underline"
              >
                {profile.title}
              </Link>
            </th>
          ))}
        </tr>
      </thead>
      {groups.map(({ group, fields }) => (
        <tbody key={group}>
          <tr className="border-b bg-muted/40">
            <th
              colSpan={3 + profiles.length}
              scope="rowgroup"
              className="py-2 pr-3 font-medium"
            >
              {group}
            </th>
          </tr>
          {fields.map((field) => (
            <SwitchRow key={field.key} field={field} profiles={profiles} />
          ))}
        </tbody>
      ))}
    </table>
  );
}

function SwitchRow({
  field,
  profiles,
}: {
  field: ProfileEnvField;
  profiles: ProfileSummary[];
}) {
  return (
    <tr className="border-b">
      <td className="py-2 pr-3 font-mono text-xs">{field.key}</td>
      <td className="py-2 pr-3">{field.label}</td>
      <td className="py-2 pr-3">{shownValue(field, field.defaultValue)}</td>
      {profiles.map((profile) => (
        <td key={profile.id} className="py-2 pr-3">
          {profileValue(field, profile)}
        </td>
      ))}
    </tr>
  );
}

function profileValue(field: ProfileEnvField, profile: ProfileSummary): string {
  if (field.ollamaOnly && profile.kind === "claude-code") {
    return "n/a";
  }
  const value = profile.env[field.key];
  return value === undefined ? "default" : shownValue(field, value);
}

function shownValue(field: ProfileEnvField, value: string): string {
  if (field.kind !== "switch") {
    return value;
  }
  return value === "1" ? "on" : "off";
}
