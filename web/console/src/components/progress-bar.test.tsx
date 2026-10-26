import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import { ProgressBar } from "./progress-bar";

describe("ProgressBar", () => {
  it("sets the fill width and shows the phase and text", () => {
    const markup = renderToStaticMarkup(
      <ProgressBar percent={45} phase="pulling" text="pulling 6a0746a1ec1a:  45%" />,
    );

    expect(markup).toContain("width:45%");
    expect(markup).toContain("pulling");
    expect(markup).toContain("animate-pulse");
  });

  it("stops pulsing once the fill is complete", () => {
    const markup = renderToStaticMarkup(<ProgressBar percent={100} phase="success" text="success" />);

    expect(markup).toContain("width:100%");
    expect(markup).not.toContain("animate-pulse");
  });

  it("escapes the progress text", () => {
    const markup = renderToStaticMarkup(<ProgressBar percent={5} phase={null} text="<img src=x onerror=alert(1)>" />);

    expect(markup).not.toContain("<img");
  });
});
