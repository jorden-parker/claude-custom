export type LeaseHolder = {
  state: "live" | "stale";
  name: string;
  pid: number;
  model: string | null;
  rung: string | null;
};

export type Residency = {
  holders: LeaseHolder[];
  rung: string | null;
  fit: string | null;
};

export const PROMOTABLE_RUNGS = ["embeddings-off", "context-down"] as const;
