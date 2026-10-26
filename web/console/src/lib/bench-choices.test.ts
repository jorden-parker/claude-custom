import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { BENCH_OFF_MODELS, BENCH_OFF_SERVERS } from "./bench-choices";

const BENCH_OFF_SCRIPT = fileURLToPath(new URL("../../../../bin/backend-bench-off", import.meta.url));

describe("bench-off choices", () => {
  const script = readFileSync(BENCH_OFF_SCRIPT, "utf8");

  it("matches the servers the script benches", () => {
    const servers = /^servers="([^"]*)"$/m.exec(script)?.[1];
    expect(servers?.split(" ")).toEqual(BENCH_OFF_SERVERS);
  });

  it("matches the models the script benches", () => {
    const models = /^bench_models\(\) \{\n\s*echo ([^\n]+)\n/m.exec(script)?.[1];
    expect(models?.split(" ")).toEqual(BENCH_OFF_MODELS);
  });
});
