import type { TelemetryReport } from "@/lib/telemetry";

type TelemetryCardProps = { report: TelemetryReport };

export function TelemetryCard({ report }: TelemetryCardProps) {
  if (!report.configured) {
    return (
      <div className="flex flex-col gap-2 text-sm text-muted-foreground">
        <p>Tool telemetry is off. To opt in, set CLAUDE_TOOL_TELEMETRY=&lt;file&gt; for sessions.</p>
        <p>
          Start the console with the same variable: CLAUDE_TOOL_TELEMETRY=&lt;file&gt; claude-ollama ui
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
