import { describe, expect, it } from "vitest";
import { percentFrom, phaseFrom } from "./pull-progress";

const PROGRESS = "pulling 6a0746a1ec1a:  45% ▕████      ▏ 8.2 GB/18 GB  52 MB/s  3m10s";

describe("percentFrom", () => {
  it("reads the percent from a progress line", () => {
    expect(percentFrom(PROGRESS)).toBe(45);
  });

  it("uses the last percent in the text", () => {
    expect(percentFrom("pulling 10%\npulling 73%")).toBe(73);
  });

  it("clamps a percent above 100 to 100", () => {
    expect(percentFrom("pulling 999%")).toBe(100);
  });

  it("gives null when the text has no percent", () => {
    expect(percentFrom("pulling manifest")).toBeNull();
    expect(percentFrom("success")).toBeNull();
  });
});

describe("phaseFrom", () => {
  it("reads each Ollama phase", () => {
    expect(phaseFrom("pulling manifest")).toBe("pulling");
    expect(phaseFrom("pulling 6a0746a1ec1a")).toBe("pulling");
    expect(phaseFrom("verifying sha256 digest")).toBe("verifying");
    expect(phaseFrom("writing manifest")).toBe("writing");
    expect(phaseFrom("success")).toBe("success");
  });

  it("reads the phase from a full progress line", () => {
    expect(phaseFrom(PROGRESS)).toBe("pulling");
  });

  it("gives null for text that is not a known phase", () => {
    expect(phaseFrom("Error: pull model manifest: file does not exist")).toBeNull();
    expect(phaseFrom("")).toBeNull();
  });
});
