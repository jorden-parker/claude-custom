export const DRAFT_ID_PATTERN = /^\d{8}-\d{6}-(pr|review)-[a-z0-9-]{1,60}$/;

const ID_KIND_PATTERN = /^\d{8}-\d{6}-(pr|review)-/;
const BRANCH_PATTERN = /^[A-Za-z0-9][A-Za-z0-9._/-]{0,254}$/;
const LINE_BREAK_PATTERN = /[\r\n]/;

export const LABELS = [
  "issue",
  "suggestion",
  "question",
  "nitpick",
  "praise",
  "todo",
  "chore",
  "thought",
] as const;
export const DECORATIONS = [
  "blocking",
  "non-blocking",
  "if-minor",
  "security",
  "test",
] as const;
export const DRAFT_EVENTS = ["COMMENT", "REQUEST_CHANGES", "APPROVE"] as const;

const LIMITS = {
  titleChars: 256,
  headingChars: 200,
  bodyChars: 20000,
  pathChars: 4096,
  urlChars: 2048,
  sections: 30,
  comments: 30,
} as const;

export type DraftKind = "pr" | "review";
export type Label = (typeof LABELS)[number];
export type Decoration = (typeof DECORATIONS)[number];
export type DraftEvent = (typeof DRAFT_EVENTS)[number];

type Posted = { url: string; at: string };
export type Section = { heading: string; body: string };
export type ReviewComment = {
  label: Label;
  decorations: Decoration[];
  path?: string;
  line?: number;
  body: string;
};

type DraftCommon = {
  id: string;
  project: string;
  created: string;
  posted?: Posted;
};
export type PrDraft = DraftCommon & {
  kind: "pr";
  base: string;
  head: string;
  title: string;
  sections: Section[];
};
export type ReviewDraft = DraftCommon & {
  kind: "review";
  pr: number;
  event: DraftEvent;
  summary: string;
  comments: ReviewComment[];
};
export type Draft = PrDraft | ReviewDraft;

export type ParseResult =
  { ok: true; draft: Draft } | { ok: false; reason: string };

const EDITABLE_FIELDS: Record<DraftKind, readonly string[]> = {
  pr: ["title", "sections"],
  review: ["summary", "event", "comments"],
};

class DraftInvalidError extends Error {}

export function kindOfDraftId(id: string): DraftKind | null {
  const match = ID_KIND_PATTERN.exec(id);
  if (!match) {
    return null;
  }
  return match[1] === "pr" ? "pr" : "review";
}

export function editableFieldsOf(draft: Draft): Record<string, unknown> {
  return pickFields(draft, EDITABLE_FIELDS[draft.kind]);
}

export function parseDraft(id: string, text: string): ParseResult {
  let value: unknown;
  try {
    value = JSON.parse(text);
  } catch {
    return { ok: false, reason: "not JSON" };
  }
  return validateDraft(id, value);
}

function validateDraft(id: string, value: unknown): ParseResult {
  try {
    return { ok: true, draft: checkDraft(id, value) };
  } catch (error) {
    if (error instanceof DraftInvalidError) {
      return { ok: false, reason: error.message };
    }
    throw error;
  }
}

export function mergeDraftEdits(current: Draft, edits: unknown): ParseResult {
  const accepted = pickFields(edits, EDITABLE_FIELDS[current.kind]);
  return validateDraft(current.id, { ...current, ...accepted });
}

function pickFields(
  source: unknown,
  keys: readonly string[],
): Record<string, unknown> {
  if (typeof source !== "object" || source === null) {
    return {};
  }
  const picked: Record<string, unknown> = {};
  for (const key of keys) {
    if (key in source) {
      picked[key] = (source as Record<string, unknown>)[key];
    }
  }
  return picked;
}

function ensure(condition: boolean, reason: string): asserts condition {
  if (!condition) {
    throw new DraftInvalidError(reason);
  }
}

function checkDraft(id: string, value: unknown): Draft {
  const record = checkRecord(value);
  const kind = kindOfDraftId(id);
  ensure(DRAFT_ID_PATTERN.test(id), "id is not a draft id");
  ensure(record.id === id, "id does not match the file name");
  ensure(record.kind === kind, `kind is not ${kind}`);
  const common: DraftCommon = {
    id,
    project: checkProject(record.project),
    created: checkTime(record.created, "created"),
    posted: checkPosted(record.posted),
  };
  return kind === "pr"
    ? checkPrFields(record, common)
    : checkReviewFields(record, common);
}

function checkPrFields(
  record: Record<string, unknown>,
  common: DraftCommon,
): PrDraft {
  return {
    ...common,
    kind: "pr",
    base: checkBranch(record.base, "base"),
    head: checkBranch(record.head, "head"),
    title: checkOneLine(record.title, "title", LIMITS.titleChars),
    sections: checkSections(record.sections),
  };
}

function checkReviewFields(
  record: Record<string, unknown>,
  common: DraftCommon,
): ReviewDraft {
  return {
    ...common,
    kind: "review",
    pr: checkPrNumber(record.pr),
    event: checkOneOf(record.event, DRAFT_EVENTS, "event"),
    summary: checkBody(record.summary, "summary"),
    comments: checkComments(record.comments),
  };
}

function checkRecord(value: unknown): Record<string, unknown> {
  ensure(
    typeof value === "object" && value !== null && !Array.isArray(value),
    "not a JSON object",
  );
  return value as Record<string, unknown>;
}

function checkOneLine(value: unknown, field: string, maxChars: number): string {
  ensure(
    typeof value === "string" &&
      value.trim() !== "" &&
      value.length <= maxChars &&
      !LINE_BREAK_PATTERN.test(value),
    `${field} must be one line of at most ${maxChars} characters`,
  );
  return value;
}

function checkBody(value: unknown, field: string): string {
  ensure(
    typeof value === "string" && value.length <= LIMITS.bodyChars,
    `${field} must be text of at most ${LIMITS.bodyChars} characters`,
  );
  return value;
}

function checkTime(value: unknown, field: string): string {
  ensure(
    typeof value === "string" && !Number.isNaN(Date.parse(value)),
    `${field} must be an ISO time`,
  );
  return value;
}

function checkProject(value: unknown): string {
  const project = checkOneLine(value, "project", LIMITS.pathChars);
  ensure(project.startsWith("/"), "project must be an absolute path");
  return project;
}

function checkBranch(value: unknown, field: string): string {
  ensure(
    typeof value === "string" && BRANCH_PATTERN.test(value),
    `${field} must be a branch name`,
  );
  return value;
}

function checkPrNumber(value: unknown): number {
  ensure(
    Number.isInteger(value) && (value as number) > 0,
    "pr must be a positive PR number",
  );
  return value as number;
}

function checkOneOf<T extends string>(
  value: unknown,
  options: readonly T[],
  field: string,
): T {
  ensure(
    options.some((option) => option === value),
    `${field} must be one of ${options.join(", ")}`,
  );
  return value as T;
}

function checkSections(value: unknown): Section[] {
  ensure(
    Array.isArray(value) && value.length <= LIMITS.sections,
    `sections must be a list of at most ${LIMITS.sections}`,
  );
  return value.map((item) => {
    const record = checkRecord(item);
    return {
      heading: checkOneLine(record.heading, "heading", LIMITS.headingChars),
      body: checkBody(record.body, "section body"),
    };
  });
}

function checkComments(value: unknown): ReviewComment[] {
  ensure(
    Array.isArray(value) && value.length <= LIMITS.comments,
    `comments must be a list of at most ${LIMITS.comments}`,
  );
  return value.map(checkComment);
}

function checkComment(value: unknown): ReviewComment {
  const record = checkRecord(value);
  const path = checkOptionalPath(record.path);
  const line = checkOptionalLine(record.line);
  ensure(line === undefined || path !== undefined, "line needs a path");
  return {
    label: checkOneOf(record.label, LABELS, "label"),
    decorations: checkDecorations(record.decorations),
    path,
    line,
    body: checkBody(record.body, "comment body"),
  };
}

function checkDecorations(value: unknown): Decoration[] {
  if (value === undefined) {
    return [];
  }
  ensure(Array.isArray(value), "decorations must be a list");
  return value.map((item) => checkOneOf(item, DECORATIONS, "decoration"));
}

function checkOptionalPath(value: unknown): string | undefined {
  return value === undefined
    ? undefined
    : checkOneLine(value, "path", LIMITS.pathChars);
}

function checkOptionalLine(value: unknown): number | undefined {
  if (value === undefined) {
    return undefined;
  }
  ensure(
    Number.isInteger(value) && (value as number) > 0,
    "line must be a positive line number",
  );
  return value as number;
}

function checkPostedUrl(value: unknown): string {
  const url = checkOneLine(value, "posted url", LIMITS.urlChars);
  ensure(isGithubLink(url), "posted url must be an https://github.com/ link");
  return url;
}

function isGithubLink(url: string): boolean {
  try {
    const parsed = new URL(url);
    return parsed.protocol === "https:" && parsed.hostname === "github.com";
  } catch {
    return false;
  }
}

function checkPosted(value: unknown): Posted | undefined {
  if (value === undefined) {
    return undefined;
  }
  const record = checkRecord(value);
  return {
    url: checkPostedUrl(record.url),
    at: checkTime(record.at, "posted at"),
  };
}
