import { BenchCard } from "@/components/bench-card";
import { StartRunButton } from "@/components/start-run-button";
import { BENCH_OFF_MODELS, BENCH_OFF_SERVERS } from "@/lib/bench-choices";

type BenchOffFrameProps = { hasReport: boolean };

const INSTALL_COMMANDS = ["backend-bench-off install", "backend-bench-off download", "backend-bench-off all"];

export function BenchOffFrame({ hasReport }: BenchOffFrameProps) {
  return (
    <div className="flex flex-col gap-4">
      {hasReport ? (
        <iframe
          title="Bench-off report"
          sandbox="allow-scripts"
          src="/api/bench-off/report"
          className="min-h-[600px] w-full rounded-xl border border-border bg-background"
        />
      ) : (
        <div className="flex flex-col gap-2 rounded-xl border border-dashed border-border p-4 text-sm">
          <p>No bench-off report yet. Install, download and run the benches in a terminal:</p>
          {INSTALL_COMMANDS.map((command) => (
            <code key={command} className="font-mono text-xs">
              {command}
            </code>
          ))}
        </div>
      )}
      <BenchCard
        title="Run one cell"
        description="Benches one server and model, then the report can be rebuilt"
        command="bench-off-run"
        fields={[
          { key: "server", label: "Server", options: BENCH_OFF_SERVERS },
          { key: "model", label: "Model", options: BENCH_OFF_MODELS },
        ]}
      />
      <div>
        <StartRunButton command="bench-off-report" params={{}}>
          Rebuild report
        </StartRunButton>
      </div>
    </div>
  );
}
