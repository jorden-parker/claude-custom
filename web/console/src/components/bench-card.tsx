"use client";

import { useState } from "react";
import { StartRunButton } from "@/components/start-run-button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import type { CommandParams } from "@/lib/console-commands";

export type BenchField = { key: string; label: string; options: readonly string[] };

type BenchCardProps = {
  title: string;
  description: string;
  command: string;
  fields: readonly BenchField[];
};

const BENCH_NOTE = "Uses the model now; stop other sessions first for clean numbers";

export function BenchCard({ title, description, command, fields }: BenchCardProps) {
  const [values, setValues] = useState<CommandParams>(() => initialValues(fields));
  const complete = fields.every((field) => (values[field.key] ?? "") !== "");

  return (
    <Card>
      <CardHeader>
        <CardTitle>{title}</CardTitle>
        <CardDescription>{description}</CardDescription>
      </CardHeader>
      <CardContent className="flex flex-col gap-3">
        <div className="flex flex-wrap items-center gap-3">
          {fields.map((field) => (
            <label key={field.key} className="flex items-center gap-2 text-sm">
              {field.label}
              <select
                className="rounded-md border border-border bg-background px-2 py-1"
                value={values[field.key] ?? ""}
                onChange={(event) => setValues({ ...values, [field.key]: event.target.value })}
              >
                {field.options.map((option) => (
                  <option key={option} value={option}>
                    {option}
                  </option>
                ))}
              </select>
            </label>
          ))}
        </div>
        <p className="text-xs text-muted-foreground">{BENCH_NOTE}</p>
        {complete ? <StartRunButton command={command} params={values}>Start</StartRunButton> : null}
      </CardContent>
    </Card>
  );
}

function initialValues(fields: readonly BenchField[]): CommandParams {
  return Object.fromEntries(fields.map((field) => [field.key, field.options[0] ?? ""]));
}
