import { BenchCard } from "@/components/bench-card";
import { PREFIX_TOKENS, THINKING_MODES } from "@/lib/bench-choices";

type BenchFormsProps = { sizes: readonly string[] };

export function BenchForms({ sizes }: BenchFormsProps) {
  const sizeField = { key: "size", label: "Size", options: sizes };
  return (
    <div className="grid gap-4">
      <BenchCard
        title="Messages bench"
        description="TTFT, prefill, decode and tool-call checks against the local Ollama"
        command="messages-bench"
        fields={[
          sizeField,
          { key: "thinking", label: "Thinking", options: THINKING_MODES },
          { key: "prefix", label: "Prefix tokens", options: PREFIX_TOKENS },
        ]}
      />
      <BenchCard
        title="Cache probe"
        description="Measures prompt-cache reuse on the local Ollama"
        command="cache-probe"
        fields={[sizeField]}
      />
      <BenchCard
        title="Review eval"
        description="Scores the local reviewer on the six PR review scenarios"
        command="review-eval"
        fields={[sizeField]}
      />
    </div>
  );
}
