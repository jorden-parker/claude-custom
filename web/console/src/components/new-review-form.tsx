"use client";

import { Input } from "@/components/ui/input";
import { Select } from "@/components/ui/select";
import { Label } from "@/components/ui/label";
import { useEffect, useState } from "react";
import { StartRunButton } from "@/components/start-run-button";
import { PR_NUMBER_PATTERN } from "@/lib/pr-number";

type ProjectInfo = { dir: string | null };

export function NewReviewForm() {
  const [sizes, setSizes] = useState<string[]>([]);
  const [size, setSize] = useState("");
  const [pr, setPr] = useState("");
  const [projectDir, setProjectDir] = useState<string | null>(null);

  useEffect(() => {
    const load = async () => {
      const [sizesResponse, projectResponse] = await Promise.all([
        fetch("/api/sizes", { cache: "no-store" }),
        fetch("/api/project", { cache: "no-store" }),
      ]);
      if (sizesResponse.ok) {
        const loaded = (await sizesResponse.json()) as string[];
        setSizes(loaded);
        setSize(loaded[0] ?? "");
      }
      if (projectResponse.ok) {
        setProjectDir(((await projectResponse.json()) as ProjectInfo).dir);
      }
    };
    void load();
  }, []);

  return (
    <NewReviewFields
      sizes={sizes}
      size={size}
      pr={pr}
      projectDir={projectDir}
      onSizeChange={setSize}
      onPrChange={setPr}
    />
  );
}

type NewReviewFieldsProps = {
  sizes: string[];
  size: string;
  pr: string;
  projectDir: string | null;
  onSizeChange: (size: string) => void;
  onPrChange: (pr: string) => void;
};

export function NewReviewFields({ sizes, size, pr, projectDir, onSizeChange, onPrChange }: NewReviewFieldsProps) {
  const prValid = PR_NUMBER_PATTERN.test(pr);
  const canStart = prValid && size !== "" && projectDir !== null;

  return (
    <section className="flex flex-col gap-4 rounded-xl border border-border p-4">
      <h2 className="text-lg font-semibold">New review</h2>
      {projectDir === null ? (
        <p className="text-sm text-muted-foreground">
          Start the console from a project folder to review its pull requests.
        </p>
      ) : (
        <p className="text-sm text-muted-foreground">
          Reviews the pull requests of <code className="font-mono text-xs">{projectDir}</code>.
        </p>
      )}
      <div className="flex flex-wrap items-end gap-3">
        <Label className="flex flex-col items-start gap-1">
          Size
          <Select
            className="w-auto"
            value={size}
            onChange={(event) => onSizeChange(event.target.value)}
            disabled={sizes.length === 0}
          >
            {sizes.map((name) => (
              <option key={name} value={name}>
                {name}
              </option>
            ))}
          </Select>
        </Label>
        <Label className="flex flex-col items-start gap-1">
          PR number
          <Input
            className="w-28 font-mono"
            inputMode="numeric"
            placeholder="12"
            value={pr}
            onChange={(event) => onPrChange(event.target.value)}
            aria-invalid={pr !== "" && !prValid}
          />
        </Label>
        <StartRunButton command="review" params={{ size, pr }} disabled={!canStart}>
          Start review
        </StartRunButton>
      </div>
      {pr === "" || prValid ? null : (
        <p className="text-sm text-error-foreground">Enter a PR number, such as 12.</p>
      )}
    </section>
  );
}
