const verdictClasses: Record<string, string> = {
  "REQUEST CHANGES": "text-error-foreground",
  "APPROVE WITH COMMENTS": "text-warning-foreground",
  APPROVE: "text-success-foreground",
};

export function verdictClass(verdict: string): string {
  return verdictClasses[verdict] ?? "text-muted-foreground";
}

export function verdictBadgeClass(verdict: string): string {
  return `${verdictClass(verdict)} font-medium`;
}
