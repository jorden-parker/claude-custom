import {
  cleanup,
  fireEvent,
  render,
  screen,
  within,
} from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { ToolStateTable } from "./tool-state-table";

const ROWS = [
  { name: "Bash", description: "Run shell commands", baseline: "allow" },
  { name: "WebFetch", description: "Fetch a web page", baseline: "deny" },
];

const rowFor = (name: string) =>
  within(screen.getByRole("row", { name: new RegExp(`^${name}\\b`) }));

describe("ToolStateTable", () => {
  afterEach(() => {
    cleanup();
  });

  it("shows each tool with its description and the default column when given", () => {
    render(
      <ToolStateTable
        rows={ROWS}
        states={{ Bash: "default", WebFetch: "ask" }}
        options={["default", "ask", "off"]}
        isChanged={() => false}
        onChange={() => undefined}
      />,
    );

    expect(
      document.querySelector('[data-slot="table-container"] table'),
    ).not.toBeNull();
    expect(screen.getByText("Fetch a web page")).toBeTruthy();
    expect(screen.getByRole("columnheader", { name: "Default" })).toBeTruthy();
    expect(rowFor("WebFetch").getByText("deny")).toBeTruthy();
  });

  it("offers only the given options and reports the chosen one", () => {
    const onChange = vi.fn();
    render(
      <ToolStateTable
        rows={ROWS}
        states={{ Bash: "default", WebFetch: "ask" }}
        options={["default", "ask", "off"]}
        isChanged={() => false}
        onChange={onChange}
      />,
    );

    expect(rowFor("Bash").queryByRole("button", { name: "allow" })).toBeNull();
    expect(
      rowFor("WebFetch")
        .getByRole("button", { name: "ask" })
        .getAttribute("aria-pressed"),
    ).toBe("true");

    fireEvent.click(rowFor("Bash").getByRole("button", { name: "off" }));
    expect(onChange).toHaveBeenCalledWith("Bash", "off");
  });

  it("highlights the rows that changed and renders the aside under the buttons", () => {
    render(
      <ToolStateTable
        rows={ROWS}
        states={{ Bash: "ask", WebFetch: "deny" }}
        options={["default", "ask", "deny"]}
        isChanged={(name) => name === "Bash"}
        onChange={() => undefined}
        aside={(name) => (name === "Bash" ? <span>keep aside</span> : null)}
      />,
    );

    expect(rowFor("Bash").getByText("keep aside")).toBeTruthy();
    expect(rowFor("WebFetch").queryByText("keep aside")).toBeNull();
    expect(screen.getByRole("row", { name: /^Bash\b/ }).className).toContain(
      "bg-warning",
    );
  });

  it("omits the default column when no row has a baseline", () => {
    render(
      <ToolStateTable
        rows={[{ name: "Bash", description: "Run shell commands" }]}
        states={{ Bash: "default" }}
        options={["default", "allow"]}
        isChanged={() => false}
        onChange={() => undefined}
      />,
    );

    expect(screen.queryByRole("columnheader", { name: "Default" })).toBeNull();
  });
});
