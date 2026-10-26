"use client";

import { SizeSelect, useSizePicker } from "@/components/size-select";
import { StartRunButton } from "@/components/start-run-button";

export function DoctorStartPanel() {
  const { sizes, size, select } = useSizePicker();

  return (
    <div className="flex flex-wrap items-center gap-3">
      <SizeSelect sizes={sizes} size={size} onChange={select} />
      {size === "" ? null : (
        <StartRunButton command="doctor" params={{ size }}>
          Run doctor
        </StartRunButton>
      )}
    </div>
  );
}
