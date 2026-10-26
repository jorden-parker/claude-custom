const verdictClasses: Record<string, string> = {
  "REQUEST CHANGES": "text-destructive",
  "APPROVE WITH COMMENTS": "text-amber-600 dark:text-amber-400",
  APPROVE: "text-green-600 dark:text-green-400",
};

export function verdictClass(verdict: string): string {
  return verdictClasses[verdict] ?? "text-muted-foreground";
}

export function verdictBadgeClass(verdict: string): string {
  return `${verdictClass(verdict)} font-medium`;
}
