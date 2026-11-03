import { cleanup, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it } from "vitest";
import { PageHeading } from "./page-heading";

describe("PageHeading", () => {
  afterEach(() => {
    cleanup();
  });

  it("shows the summary of the section with that title", () => {
    render(<PageHeading title="Runs" />);

    expect(
      screen.getByText("Every job the console started, live and past"),
    ).toBeTruthy();
  });

  it("prefers an explicit description", () => {
    render(<PageHeading title="Runs" description="Custom words" />);

    expect(screen.getByText("Custom words")).toBeTruthy();
    expect(screen.queryByText(/Every job/)).toBeNull();
  });

  it("renders no subtitle for a title without a section", () => {
    const { container } = render(<PageHeading title="Run run-42" />);

    expect(container.querySelector("p")).toBeNull();
  });
});
