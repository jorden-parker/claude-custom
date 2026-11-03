import type { ReactNode } from "react";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import type { ToolState } from "@/lib/tool-states";

export type ToolLine = { name: string; description: string; baseline?: string };

type ToolStateTableProps<State extends ToolState> = {
  rows: readonly ToolLine[];
  states: Record<string, State>;
  options: readonly State[] | ((name: string) => readonly State[]);
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
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead>Tool</TableHead>
          <TableHead>Description</TableHead>
          {showBaseline ? <TableHead>Default</TableHead> : null}
          <TableHead>Permission</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {rows.map((row) => (
          <TableRow
            key={row.name}
            className={`align-top ${isChanged(row.name) ? "bg-warning" : ""}`}
          >
            <TableCell className="font-mono">{row.name}</TableCell>
            <TableCell className="whitespace-normal text-muted-foreground">
              {row.description}
            </TableCell>
            {showBaseline ? (
              <TableCell className="font-mono text-xs text-muted-foreground">
                {row.baseline}
              </TableCell>
            ) : null}
            <TableCell>
              <div className="flex flex-col items-start gap-2">
                <StateButtons
                  name={row.name}
                  current={states[row.name]}
                  options={
                    typeof options === "function" ? options(row.name) : options
                  }
                  onSelect={(state) => onChange(row.name, state)}
                />
                {aside?.(row.name)}
              </div>
            </TableCell>
          </TableRow>
        ))}
      </TableBody>
    </Table>
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
