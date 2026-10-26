import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it, vi } from "vitest";
import { BenchCard, type BenchField } from "./bench-card";

vi.mock("next/navigation", () => ({ useRouter: () => ({ push: () => undefined }) }));

const sizeField: BenchField = { key: "size", label: "Size", options: ["27b", "35b"] };

function render(fields: readonly BenchField[]) {
  return renderToStaticMarkup(
    <BenchCard title="Cache probe" description="Prompt-cache reuse" command="cache-probe" fields={fields} />,
  );
}

describe("BenchCard", () => {
  it("renders a start button once every select has a value", () => {
    expect(render([sizeField])).toContain(">Start<");
  });

  it("hides the start button while a select has no options yet", () => {
    expect(render([{ key: "size", label: "Size", options: [] }])).not.toContain(">Start<");
  });

  it("shows the stop-other-sessions note on every card", () => {
    expect(render([sizeField])).toContain("stop other sessions first for clean numbers");
  });
});
