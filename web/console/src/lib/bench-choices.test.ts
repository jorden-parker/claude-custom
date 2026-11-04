import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { BENCH_OFF_MODELS, BENCH_OFF_SERVERS } from "./bench-choices";

const BENCH_OFF_SCRIPT = fileURLToPath(
  new URL("../../../../bin/backend-bench-off", import.meta.url),
);

describe("bench-off choices", () => {
  const script = readFileSync(BENCH_OFF_SCRIPT, "utf8");

  it("matches the servers the script benches", () => {
    const servers = /^servers="([^"]*)"$/m.exec(script)?.[1];
    expect(servers?.split(" ")).toEqual(BENCH_OFF_SERVERS);
  });

  it("offers llama.cpp with and without MTP", () => {
    expect(BENCH_OFF_SERVERS).toEqual(
      expect.arrayContaining(["llama-server", "llama-server-mtp"]),
    );
  });

  it("offers every staged cell, with Ollama first as the baseline", () => {
    expect(BENCH_OFF_SERVERS[0]).toBe("ollama");
    expect(BENCH_OFF_SERVERS).toEqual(
      expect.arrayContaining([
        "vllm-metal",
        "llama-server-src",
        "lmstudio-mlx",
        "mtplx-nomtp",
        "rapid-mlx",
        "optiq-ngram",
        "mistralrs",
      ]),
    );
  });

  it("matches the models the script benches", () => {
    const models = /^all_bench_models\(\) \{\n\s*echo ([^\n]+)\n/m.exec(
      script,
    )?.[1];
    expect(models?.split(" ")).toEqual(BENCH_OFF_MODELS);
  });
});
