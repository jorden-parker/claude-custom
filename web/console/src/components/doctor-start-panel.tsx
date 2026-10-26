"use client";

import { useEffect, useState } from "react";
import { StartRunButton } from "@/components/start-run-button";

export function DoctorStartPanel() {
  const [sizes, setSizes] = useState<string[]>([]);
  const [size, setSize] = useState("");

  useEffect(() => {
    const load = async () => {
      const response = await fetch("/api/sizes", { cache: "no-store" });
      if (response.ok) {
        const loaded = (await response.json()) as string[];
        setSizes(loaded);
        setSize(loaded[0] ?? "");
      }
    };
    void load();
  }, []);

  return (
    <div className="flex flex-wrap items-center gap-3">
      <label className="flex items-center gap-2 text-sm">
        Size
        <select
          className="rounded-md border border-border bg-background px-2 py-1"
          value={size}
          onChange={(event) => setSize(event.target.value)}
          disabled={sizes.length === 0}
        >
          {sizes.map((name) => (
            <option key={name} value={name}>
              {name}
            </option>
          ))}
        </select>
      </label>
      {size === "" ? null : (
        <StartRunButton command="doctor" params={{ size }}>
          Run doctor
        </StartRunButton>
      )}
    </div>
  );
}
