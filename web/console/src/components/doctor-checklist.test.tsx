import { cleanup, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import type { DoctorCheck } from "@/lib/doctor-checks";
import { DoctorChecklist } from "./doctor-checklist";

vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: vi.fn() }),
}));

const checks: DoctorCheck[] = [
  { level: "ok", text: "jq on PATH" },
  { level: "warn", text: "context mismatch on 27b" },
  { level: "fail", text: "digest NAME is X" },
];

describe("DoctorChecklist", () => {
  afterEach(() => {
    cleanup();
  });

  it("renders one row per check with an icon for its level", () => {
    const { container } = render(<DoctorChecklist checks={checks} other={[]} running={false} />);

    const rows = container.querySelectorAll("li[data-level]");
    expect(rows).toHaveLength(3);
    expect(container.querySelector('li[data-level="warn"]')?.textContent).toContain("context mismatch on 27b");
    expect(container.querySelectorAll("li[data-level] svg")).toHaveLength(3);
  });

  it("shows the count of checks at each level", () => {
    render(<DoctorChecklist checks={checks} other={[]} running={false} />);

    expect(screen.getByText("1 ok · 1 warn · 1 fail")).toBeTruthy();
  });

  it("shows a checking row only while running", () => {
    const { rerender } = render(<DoctorChecklist checks={checks} other={[]} running={true} />);
    expect(screen.getByText("checking…")).toBeTruthy();

    rerender(<DoctorChecklist checks={checks} other={[]} running={false} />);
    expect(screen.queryByText("checking…")).toBeNull();
  });

  it("shows lines that are not checks below the list", () => {
    render(<DoctorChecklist checks={[]} other={["Usage: claude-ollama doctor [size]"]} running={false} />);

    expect(screen.getByText("Usage: claude-ollama doctor [size]")).toBeTruthy();
  });

  it("shows a fix the console can run as a button beside its command", () => {
    const withFix: DoctorCheck[] = [
      { level: "fail", text: "behind qwen3.6:35b-mlx (registry 4a5e, pin e92a)", fixes: ["bin/model-upgrade 35b"] },
    ];
    render(<DoctorChecklist checks={withFix} other={[]} running={false} />);

    expect(screen.getByText("bin/model-upgrade 35b")).toBeTruthy();
    expect(screen.getByRole("button", { name: "Upgrade 35b" })).toBeTruthy();
  });

  it("shows a fix the console cannot run as text only", () => {
    const withFix: DoctorCheck[] = [
      { level: "warn", text: "no GitHub token", fixes: ["claude-ollama github-token push"] },
    ];
    render(<DoctorChecklist checks={withFix} other={[]} running={false} />);

    expect(screen.getByText("claude-ollama github-token push")).toBeTruthy();
    expect(screen.queryByRole("button")).toBeNull();
  });
});
