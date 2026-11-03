"use client";

import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
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
    <div className="flex flex-col gap-4">
      <ActionsRow />
      <SwitchTable
        profiles={profiles}
        groups={envFieldsByGroup(PROFILE_ENV_FIELDS)}
      />
    </div>
  );
}

function ActionsRow() {
  return (
    <p className="text-sm text-muted-foreground">
      Actions:{" "}
      <Link href="/diagnose" className="underline underline-offset-2">
        Diagnose
      </Link>{" "}
      explains the last run, writes a rescue report and lists the rule cards and
      recovery recipes these switches control.
    </p>
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
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead className="whitespace-normal">Switch</TableHead>
          <TableHead className="whitespace-normal">Default</TableHead>
          {profiles.map((profile) => (
            <TableHead key={profile.id} className="whitespace-normal">
              <Link
                href={`/profiles/${profile.id}`}
                className="underline-offset-2 hover:underline"
              >
                {profile.title}
              </Link>
            </TableHead>
          ))}
        </TableRow>
      </TableHeader>
      {groups.map(({ group, fields }) => (
        <TableBody key={group}>
          <TableRow className="bg-muted/40">
            <TableHead colSpan={2 + profiles.length} scope="rowgroup">
              {group}
            </TableHead>
          </TableRow>
          {fields.map((field) => (
            <SwitchRow key={field.key} field={field} profiles={profiles} />
          ))}
        </TableBody>
      ))}
    </Table>
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
    <TableRow id={field.key} className="scroll-mt-4">
      <TableCell className="min-w-48 whitespace-normal">
        <span className="block">{field.label}</span>
        <span className="block font-mono text-xs text-muted-foreground [overflow-wrap:anywhere]">
          {field.key}
        </span>
      </TableCell>
      <TableCell>{shownValue(field, field.defaultValue)}</TableCell>
      {profiles.map((profile) => (
        <TableCell key={profile.id}>{profileValue(field, profile)}</TableCell>
      ))}
    </TableRow>
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
  if (field.kind === "choice") {
    return (
      field.choices.find((choice) => choice.value === value)?.word ?? value
    );
  }
  if (field.kind !== "switch") {
    return value;
  }
  return value === "1" ? "on" : "off";
}
