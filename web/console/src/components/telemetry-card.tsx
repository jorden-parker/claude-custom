import type { TelemetryReport } from "@/lib/telemetry";

type TelemetryCardProps = { report: TelemetryReport };

export function TelemetryCard({ report }: TelemetryCardProps) {
  if (!report.configured) {
    return (
      <div className="flex flex-col gap-2 text-sm text-muted-foreground">
        <p>
          Tool telemetry is off only when CLAUDE_OLLAMA_TELEMETRY=0 was set for
          the sessions or the console, or the console was not started by
          claude-ollama ui.
        </p>
        <p>
          Otherwise claude-ollama ui reads
          ~/.claude-ollama/telemetry/tool-calls.jsonl, the file the sessions
          write. CLAUDE_TOOL_TELEMETRY=&lt;file&gt; picks another file for both.
        </p>
      </div>
    );
  }
  if (report.error !== undefined) {
    return <p className="text-sm text-error-foreground">{report.error}</p>;
  }
  return (
    <div className="rounded-xl bg-muted">
      <pre className="max-w-full whitespace-pre-wrap p-4 font-mono text-xs [overflow-wrap:anywhere]">
        {report.output}
      </pre>
    </div>
  );
}
