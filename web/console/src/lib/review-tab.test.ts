import { describe, expect, it } from "vitest";
import { tabFromHash, tabFromValue } from "./review-tab";

describe("review tab selection", () => {
  it("opens the transcript tab for the #transcript hash", () => {
    expect(tabFromHash("#transcript")).toBe("transcript");
  });

  it("opens the findings tab for any other hash or none", () => {
    expect(tabFromHash("")).toBe("findings");
    expect(tabFromHash("#findings")).toBe("findings");
    expect(tabFromHash("#something-else")).toBe("findings");
  });

  it("maps a tab value to a tab, defaulting to findings", () => {
    expect(tabFromValue("transcript")).toBe("transcript");
    expect(tabFromValue("findings")).toBe("findings");
    expect(tabFromValue("bogus")).toBe("findings");
  });
});
