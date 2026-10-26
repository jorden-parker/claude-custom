export type ConsoleSection = {
  href: string;
  title: string;
  summary: string;
};

export const CONSOLE_SECTIONS: readonly ConsoleSection[] = [
  { href: "/reviews", title: "Reviews", summary: "Live and past PR reviews" },
  { href: "/runs", title: "Runs", summary: "Every job the console started, live and past" },
];
