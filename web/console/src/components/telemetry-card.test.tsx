import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import { TelemetryCard } from "./telemetry-card";

describe("TelemetryCard", () => {
  it("explains how to opt in when telemetry is not configured", () => {
    const markup = renderToStaticMarkup(<TelemetryCard report={{ configured: false }} />);
    expect(markup).toContain("CLAUDE_TOOL_TELEMETRY");
    expect(markup).toContain("claude-ollama ui");
  });

  it("shows the report output in a monospace block", () => {
    const markup = renderToStaticMarkup(<TelemetryCard report={{ configured: true, output: "Bash 3 calls" }} />);
    expect(markup).toContain("<pre");
    expect(markup).toContain("Bash 3 calls");
  });
});
