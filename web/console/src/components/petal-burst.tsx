import type { CSSProperties } from "react";
import type { RunStatus } from "@/lib/run-log";

type Petal = { x: string; y: string; spin: string; delay: string; tone: string };

const PETALS: readonly Petal[] = [
  { x: "-64px", y: "-46px", spin: "200deg", delay: "0ms", tone: "var(--petal-1)" },
  { x: "-30px", y: "-70px", spin: "-160deg", delay: "60ms", tone: "var(--petal-2)" },
  { x: "2px", y: "-82px", spin: "140deg", delay: "20ms", tone: "var(--petal-3)" },
  { x: "36px", y: "-68px", spin: "-220deg", delay: "90ms", tone: "var(--petal-4)" },
  { x: "66px", y: "-40px", spin: "180deg", delay: "40ms", tone: "var(--petal-1)" },
  { x: "-48px", y: "-14px", spin: "-140deg", delay: "110ms", tone: "var(--petal-3)" },
  { x: "50px", y: "-10px", spin: "160deg", delay: "70ms", tone: "var(--petal-2)" },
  { x: "2px", y: "-40px", spin: "-200deg", delay: "130ms", tone: "var(--petal-4)" },
];

function petalStyle(petal: Petal): CSSProperties {
  return {
    backgroundColor: petal.tone,
    animationDelay: petal.delay,
    "--petal-x": petal.x,
    "--petal-y": petal.y,
    "--petal-spin": petal.spin,
  } as CSSProperties;
}

export function PetalBurst({ status }: { status: RunStatus }) {
  if (status !== "ok") {
    return null;
  }

  return (
    <div aria-hidden="true" className="pointer-events-none absolute inset-0 overflow-hidden">
      {PETALS.map((petal) => (
        <span
          key={petal.delay}
          data-petal
          className="absolute top-1/2 left-1/2 hidden size-2.5 rounded-[60%_0] motion-safe:block motion-safe:animate-petal-fall"
          style={petalStyle(petal)}
        />
      ))}
    </div>
  );
}
