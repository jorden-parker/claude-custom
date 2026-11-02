import type { ReactNode } from "react";
import type { ToolState } from "@/lib/tool-states";

export type ToolLine = { name: string; description: string; baseline?: string };

type ToolStateTableProps<State extends ToolState> = {
  rows: readonly ToolLine[];
  states: Record<string, State>;
  options: readonly State[];
  isChanged: (name: string) => boolean;
  onChange: (name: string, state: State) => void;
  aside?: (name: string) => ReactNode;
};

export function ToolStateTable<State extends ToolState>({
  rows,
  states,
  options,
  isChanged,
  onChange,
  aside,
}: ToolStateTableProps<State>) {
  const showBaseline = rows.some((row) => row.baseline !== undefined);
  return (
    <table className="w-full text-left text-sm">
      <thead>
        <tr className="border-b text-muted-foreground">
          <th className="py-2 pr-3 font-medium">Tool</th>
          <th className="py-2 pr-3 font-medium">Description</th>
          {showBaseline ? <th className="py-2 pr-3 font-medium">Default</th> : null}
          <th className="py-2 pr-3 font-medium">Permission</th>
        </tr>
      </thead>
      <tbody>
        {rows.map((row) => (
          <tr key={row.name} className={`border-b align-top ${isChanged(row.name) ? "bg-warning" : ""}`}>
            <td className="py-2 pr-3 font-mono">{row.name}</td>
            <td className="py-2 pr-3 text-muted-foreground">{row.description}</td>
            {showBaseline ? (
              <td className="py-2 pr-3 font-mono text-xs text-muted-foreground">{row.baseline}</td>
            ) : null}
            <td className="py-2 pr-3">
              <div className="flex flex-col items-start gap-2">
                <StateButtons
                  name={row.name}
                  current={states[row.name]}
                  options={options}
                  onSelect={(state) => onChange(row.name, state)}
                />
                {aside?.(row.name)}
              </div>
            </td>
          </tr>
        ))}
      </tbody>
    </table>
  );
}

function StateButtons<State extends ToolState>({
  name,
  current,
  options,
  onSelect,
}: {
  name: string;
  current: State;
  options: readonly State[];
  onSelect: (state: State) => void;
}) {
  return (
    <div role="group" aria-label={`Permission for ${name}`} className="inline-flex rounded-md border">
      {options.map((state) => (
        <button
          key={state}
          type="button"
          aria-pressed={current === state}
          onClick={() => onSelect(state)}
          className={`px-2 py-1 text-xs first:rounded-l-md last:rounded-r-md ${
            current === state ? "bg-muted font-medium" : "hover:bg-muted/60"
          }`}
        >
          {state}
        </button>
      ))}
    </div>
  );
}
