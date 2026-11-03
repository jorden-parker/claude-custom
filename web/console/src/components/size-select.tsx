"use client";

import { Select } from "@/components/ui/select";
import { Label } from "@/components/ui/label";
import { useEffect, useState } from "react";

export function useSizePicker(): {
  sizes: string[];
  size: string;
  select: (size: string) => void;
} {
  const [sizes, setSizes] = useState<string[]>([]);
  const [picked, setPicked] = useState("");
  useEffect(() => {
    const load = async () => {
      const response = await fetch("/api/sizes", { cache: "no-store" });
      if (response.ok) {
        setSizes((await response.json()) as string[]);
      }
    };
    void load();
  }, []);
  return {
    sizes,
    size: sizes.includes(picked) ? picked : (sizes[0] ?? ""),
    select: setPicked,
  };
}

type SizeSelectProps = {
  sizes: string[];
  size: string;
  onChange: (size: string) => void;
};

export function SizeSelect({ sizes, size, onChange }: SizeSelectProps) {
  return (
    <Label className="flex items-center gap-2">
      Size
      <Select
        className="w-auto"
        value={size}
        onChange={(event) => onChange(event.target.value)}
        disabled={sizes.length === 0}
      >
        {sizes.map((name) => (
          <option key={name} value={name}>
            {name}
          </option>
        ))}
      </Select>
    </Label>
  );
}
