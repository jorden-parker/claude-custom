import { cleanup, render, screen } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { stubResizeObserver } from "./run-stream-test-support";
import { StreamOutput } from "./stream-output";

describe("StreamOutput", () => {
  beforeEach(stubResizeObserver);

  afterEach(() => {
    cleanup();
    vi.unstubAllGlobals();
  });

  it("grows with its lines when it is not live", () => {
    render(<StreamOutput lines={[{ key: 1, text: "a" }]} />);
    expect(screen.getByRole("log").className).not.toContain("max-h-");
  });

  it("is one screen tall while live", () => {
    render(<StreamOutput lines={[{ key: 1, text: "a" }]} live />);
    expect(screen.getByRole("log").className).toContain(
      "max-h-[calc(100dvh-6rem)]",
    );
  });
});
