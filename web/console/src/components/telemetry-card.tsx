import type { TelemetryReport } from "@/lib/telemetry";

type TelemetryCardProps = { report: TelemetryReport };

export function TelemetryCard({ report }: TelemetryCardProps) {
  if (!report.configured) {
    return (
      <div className="flex flex-col gap-2 text-sm text-muted-foreground">
        <p>
          Tool telemetry is off only when CLAUDE_OLLAMA_TELEMETRY=0 was set for the sessions or the console, or
          the console was not started by claude-ollama ui.
        </p>
        <p>
          Otherwise claude-ollama ui reads ~/.claude-ollama/telemetry/tool-calls.jsonl, the file the sessions
          write. CLAUDE_TOOL_TELEMETRY=&lt;file&gt; picks another file for both.
        </p>
      </div>
    );
  }
  if (report.error !== undefined) {
    return <p className="text-sm text-red-700 dark:text-red-400">{report.error}</p>;
  }
  return (
    <pre className="overflow-x-auto whitespace-pre rounded-xl bg-muted p-4 font-mono text-xs">
      {report.output}
    </pre>
  );
}
