import { describe, expect, it } from "vitest";
import { scoreReply } from "./score.ts";

const patches = [
  '{"op":"add","path":"/root","value":"main"}',
  '{"op":"add","path":"/elements/main","value":{"type":"Card","props":{"title":"Pricing","description":null},"children":["cta"]}}',
  '{"op":"add","path":"/elements/cta","value":{"type":"Button","props":{"label":"Buy","variant":"primary"},"children":[]}}',
];

describe("scoreReply", () => {
  it("counts patch lines and validates a clean spec", () => {
    const score = scoreReply(patches.join("\n"));
    expect(score).toMatchObject({
      lines: 3,
      patches: 3,
      prose: 0,
      elements: 2,
      unknownTypes: [],
      valid: true,
      issue: null,
      propIssue: null,
    });
  });

  it("names the first prop outside a component's schema", () => {
    const reply = [
      patches[0],
      '{"op":"add","path":"/elements/main","value":{"type":"Button","props":{"label":"Buy","variant":"loud"},"children":[]}}',
    ].join("\n");
    const score = scoreReply(reply);
    expect(score.issue).toBeNull();
    expect(score.propIssue).toMatch(/^main\/variant: /);
    expect(score.valid).toBe(false);
  });

  it("treats fences and prose as non-patch lines but still compiles", () => {
    const reply = ["Here you go:", "```json", ...patches, "```"].join("\n");
    const score = scoreReply(reply);
    expect(score.lines).toBe(6);
    expect(score.patches).toBe(3);
    expect(score.prose).toBe(3);
    expect(score.valid).toBe(true);
  });

  it("names component types outside the catalog and fails validation", () => {
    const reply = [
      patches[0],
      '{"op":"add","path":"/elements/main","value":{"type":"Carousel","props":{},"children":[]}}',
    ].join("\n");
    const score = scoreReply(reply);
    expect(score.unknownTypes).toEqual(["Carousel"]);
    expect(score.valid).toBe(false);
    expect(score.issue).toEqual(expect.any(String));
  });

  it("reports an empty reply as invalid with no elements", () => {
    const score = scoreReply("");
    expect(score).toMatchObject({
      lines: 0,
      patches: 0,
      elements: 0,
      valid: false,
    });
  });
});
