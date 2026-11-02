import { Badge } from "@/components/ui/badge";
import { formatLocalTime } from "@/lib/format-time";
import type { MockSpikeDiagnostics } from "@/lib/mock-spike/reports.ts";

export function MockDiagnostics({
  diagnostics,
}: {
  diagnostics: MockSpikeDiagnostics;
}) {
  return (
    <div className="flex flex-col gap-2 text-sm">
      <p className="text-muted-foreground">
        Reads <code>mock-spike-*.json</code> from{" "}
        <code>{diagnostics.directory}</code>; newest by modification time is
        shown above.
      </p>
      {diagnostics.files.length === 0 ? (
        <p className="text-muted-foreground">
          No matching files. A finished run prints a <code>saved:</code> line
          naming one.
        </p>
      ) : (
        <ul className="flex flex-col gap-1">
          {diagnostics.files.map((file) => (
            <li key={file.name} className="flex flex-wrap items-center gap-2">
              <code className="break-all">{file.name}</code>
              <time
                className="text-xs text-muted-foreground"
                dateTime={file.modifiedAt}
              >
                {formatLocalTime(file.modifiedAt)}
              </time>
              {file.problem === null ? (
                <Badge variant="outline">readable</Badge>
              ) : (
                <Badge variant="destructive">{file.problem}</Badge>
              )}
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
