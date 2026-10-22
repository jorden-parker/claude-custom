"use client";

import {
  CircleAlertIcon,
  CircleCheckIcon,
  ChevronDownIcon,
  ListIcon,
  Loader2Icon,
  PauseCircleIcon,
} from "lucide-react";
import { useSyncExternalStore, type ReactNode } from "react";
import { Task, TaskContent, TaskItem, TaskTrigger } from "@/components/ai-elements/task";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from "@/components/ui/collapsible";
import { Message, MessageContent } from "@/components/ui/message";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import {
  displayFileState,
  durationSeconds,
  fileFindingCount,
  fileOutcomeText,
  findingCountText,
  isFileOpenByDefault,
  type CheckView,
  type FileView,
  type FindingView,
  type ReviewState,
  type StageView,
  type VerdictView,
} from "@/lib/review-state";
import { headerStatusLabel, statusTextClass } from "@/lib/status-style";
import { tabFromHash, tabFromValue, type ReviewTab } from "@/lib/review-tab";
import { verdictClass } from "@/lib/verdict-style";
import { InlineMarkdown, MarkdownText } from "./markdown-text";
import { ReviewTranscript } from "./review-transcript";

type ReviewBodyProps = {
  state: ReviewState;
  elapsedSeconds: number;
};

export function ReviewBody({ state, elapsedSeconds }: ReviewBodyProps) {
  const shownSeconds = state.ended ? durationSeconds(state) : elapsedSeconds;
  return (
    <div className="flex min-w-0 flex-col gap-6">
      <ReviewHeader state={state} seconds={shownSeconds} />
      {state.header.status === "stopped" ? (
        <p className="text-sm text-muted-foreground">The review ended without a result.</p>
      ) : null}
      {state.error ? <ErrorBanner message={state.error} /> : null}
      <ChangedFiles files={state.files} status={state.header.status} />
      <ReviewTabs state={state} />
    </div>
  );
}

function ReviewTabs({ state }: { state: ReviewState }) {
  const tab = useSyncExternalStore(subscribeToHash, readTabFromHash, serverTab);

  function selectTab(value: string) {
    window.history.replaceState(null, "", `#${tabFromValue(value)}`);
    window.dispatchEvent(new HashChangeEvent("hashchange"));
  }

  return (
    <Tabs value={tab} onValueChange={selectTab} className="min-w-0 gap-4">
      <TabsList>
        <TabsTrigger value="findings">Findings</TabsTrigger>
        <TabsTrigger value="transcript">Transcript</TabsTrigger>
      </TabsList>
      <TabsContent value="findings" className="flex min-w-0 flex-col gap-6">
        <ProgressTask stages={state.stages} />
        <div className="flex min-w-0 flex-col gap-3">
          {state.files.map((file) => (
            <FileTask key={file.index} file={file} status={state.header.status} />
          ))}
        </div>
        {state.verdict ? <VerdictBanner verdict={state.verdict} summary={state.summary} /> : null}
        {state.report ? <ReportSection report={state.report} /> : null}
      </TabsContent>
      <TabsContent value="transcript">
        <ReviewTranscript entries={state.transcript} />
      </TabsContent>
    </Tabs>
  );
}

function subscribeToHash(onChange: () => void): () => void {
  window.addEventListener("hashchange", onChange);
  return () => window.removeEventListener("hashchange", onChange);
}

function readTabFromHash(): ReviewTab {
  return tabFromHash(window.location.hash);
}

function serverTab(): ReviewTab {
  return "findings";
}

function ReviewHeader({ state, seconds }: { state: ReviewState; seconds: number }) {
  return (
    <Card>
      <CardHeader>
        <CardTitle className="break-words">{state.header.name || "Review"}</CardTitle>
        <CardDescription className="break-words">{state.header.title}</CardDescription>
      </CardHeader>
      <CardContent className="flex flex-wrap items-center gap-2 text-sm">
        <Badge variant="outline" className={statusTextClass(state.header.status)}>
          {headerStatusLabel(state.header.status)}
        </Badge>
        <span className="break-all text-muted-foreground">{state.header.model}</span>
        <span className="text-muted-foreground">{formatSeconds(seconds)}</span>
      </CardContent>
    </Card>
  );
}

function ErrorBanner({ message }: { message: string }) {
  return (
    <div role="alert" className="break-words rounded-md border border-destructive p-4 text-sm text-destructive">
      {message}
    </div>
  );
}

function ChangedFiles({ files, status }: { files: FileView[]; status: ReviewState["header"]["status"] }) {
  if (files.length === 0) {
    return null;
  }
  return (
    <section className="flex min-w-0 flex-col gap-2">
      <h2 className="font-medium text-sm">Changed files</h2>
      <ul className="flex min-w-0 flex-wrap gap-2">
        {files.map((file) => (
          <li key={file.index} className="flex min-w-0 max-w-full">
            <span className="flex min-w-0 max-w-full items-center gap-2 rounded-md border px-2 py-1 text-xs">
              <span className="min-w-0 truncate" title={file.path}>
                {file.path}
              </span>
              <Badge variant="secondary" className={`shrink-0 text-xs ${fileStateClass(displayFileState(file, status))}`}>
                {fileBadgeText(file, status)}
              </Badge>
            </span>
          </li>
        ))}
      </ul>
    </section>
  );
}

function fileBadgeText(file: FileView, status: ReviewState["header"]["status"]): string {
  const state = displayFileState(file, status);
  const findings = fileFindingCount(file);
  return findings > 0 ? `${state} · ${findingCountText(findings)}` : state;
}

function fileStateClass(state: ReturnType<typeof displayFileState>): string {
  return state === "stopped" ? "text-muted-foreground" : "";
}

function ProgressTask({ stages }: { stages: StageView[] }) {
  if (stages.length === 0) {
    return null;
  }
  return (
    <Task defaultOpen>
      <TaskTrigger title="Review progress">
        <TaskHeading icon={<ListIcon className="size-4" />} title="Review progress" />
      </TaskTrigger>
      <TaskContent>
        {stages.map((stage, index) => (
          <TaskItem key={index}>
            {formatSeconds(stage.t)} {stage.message}
          </TaskItem>
        ))}
      </TaskContent>
    </Task>
  );
}

function FileTask({ file, status }: { file: FileView; status: ReviewState["header"]["status"] }) {
  const title = `[${file.index}/${file.total}] ${file.path}`;
  return (
    <Task defaultOpen={isFileOpenByDefault(file)} className="min-w-0">
      <TaskTrigger title={title} className="w-full min-w-0 justify-start text-left">
        <TaskHeading icon={<FileStateIcon file={file} status={status} />} title={title} />
      </TaskTrigger>
      <TaskContent>
        <FileStatusLine file={file} status={status} />
        {file.findings.map((finding, index) => (
          <FindingMessage key={index} finding={finding} />
        ))}
        {file.retries.map((reply, index) => (
          <div key={index} className="flex flex-col gap-1">
            <p className="text-xs text-muted-foreground">retried: the answer was not a JSON array</p>
            <pre className="max-h-48 overflow-auto whitespace-pre-wrap break-words rounded bg-muted p-2 font-mono text-xs text-muted-foreground">
              {reply}
            </pre>
          </div>
        ))}
        {file.check ? <CheckLine check={file.check} /> : null}
      </TaskContent>
    </Task>
  );
}

function CheckLine({ check }: { check: CheckView }) {
  const count = `${check.count} finding${check.count === 1 ? "" : "s"}`;
  const text = check.kept === null ? `checked ${count}` : `checked ${count}, kept ${check.kept}`;
  return <p className="text-xs text-muted-foreground">{text}</p>;
}

function TaskHeading({ icon, title }: { icon: ReactNode; title: string }) {
  return (
    <div className="flex w-full min-w-0 cursor-pointer items-start gap-2 text-left text-sm text-muted-foreground transition-colors hover:text-foreground">
      {icon}
      <span className="min-w-0 [overflow-wrap:anywhere]">{title}</span>
      <ChevronDownIcon className="ml-auto size-4 shrink-0 transition-transform group-data-[state=open]:rotate-180" />
    </div>
  );
}

function FileStateIcon({ file, status }: { file: FileView; status: ReviewState["header"]["status"] }) {
  const state = displayFileState(file, status);
  if (state === "stopped") {
    return <PauseCircleIcon className="size-4 shrink-0 text-muted-foreground" />;
  }
  if (state === "running") {
    return <Loader2Icon className="size-4 shrink-0 animate-spin text-blue-500" />;
  }
  if (/error|fail/i.test(file.outcome ?? "")) {
    return <CircleAlertIcon className="size-4 shrink-0 text-red-500" />;
  }
  return <CircleCheckIcon className="size-4 shrink-0 text-green-600" />;
}

const fileStatusText: Record<FileView["state"], (file: FileView) => string> = {
  waiting: (file) =>
    file.waitingSeconds === null
      ? "waiting for the first token"
      : `waiting for the first token, ${formatSeconds(file.waitingSeconds)}`,
  writing: (file) => `writing, ${file.chars} chars`,
  done: (file) =>
    file.seconds === null
      ? fileOutcomeText(file)
      : `${fileOutcomeText(file)} · ${formatSeconds(file.seconds)}`,
};

function FileStatusLine({ file, status }: { file: FileView; status: ReviewState["header"]["status"] }) {
  const state = displayFileState(file, status);
  if (state === "stopped") {
    return <p className="text-sm text-muted-foreground">stopped before a result</p>;
  }
  const pulse = state === "running" ? "animate-pulse " : "";
  return <p className={`${pulse}text-sm text-muted-foreground`}>{fileStatusText[file.state](file)}</p>;
}

function FindingMessage({ finding }: { finding: FindingView }) {
  return (
    <Message>
      <MessageContent>
        <div className="flex flex-wrap items-center gap-2">
          <Badge variant={labelVariant(finding)} className={labelClass(finding)}>
            {finding.label}
            {finding.blocking ? " · blocking" : ""}
          </Badge>
          <code className="break-all rounded bg-muted px-1.5 py-0.5 font-mono text-xs">{locationOf(finding)}</code>
          {finding.confidence && finding.confidence !== "high" ? (
            <span className="text-xs text-muted-foreground">confidence: {finding.confidence}</span>
          ) : null}
        </div>
        <div className="mt-2 break-words text-sm font-medium">
          <InlineMarkdown>{finding.summary}</InlineMarkdown>
        </div>
        {finding.why ? (
          <div className="break-words text-sm text-muted-foreground">
            <InlineMarkdown>{finding.why}</InlineMarkdown>
          </div>
        ) : null}
      </MessageContent>
    </Message>
  );
}

function VerdictBanner({ verdict, summary }: { verdict: VerdictView; summary: string | null }) {
  return (
    <Card>
      <CardHeader>
        <CardTitle className={verdictClass(verdict.verdict)}>{verdict.verdict}</CardTitle>
        {verdict.seconds === null ? null : (
          <CardDescription>{formatSeconds(verdict.seconds)}</CardDescription>
        )}
      </CardHeader>
      {summary ? (
        <CardContent>
          <MarkdownText>{summary}</MarkdownText>
        </CardContent>
      ) : null}
    </Card>
  );
}

function ReportSection({ report }: { report: string }) {
  return (
    <Collapsible>
      <CollapsibleTrigger className="group flex items-center gap-2 text-sm font-medium">
        <ChevronDownIcon className="size-4 shrink-0 transition-transform group-data-[panel-open]:rotate-180" />
        Full report
      </CollapsibleTrigger>
      <CollapsibleContent className="pt-3">
        <MarkdownText>{report}</MarkdownText>
      </CollapsibleContent>
    </Collapsible>
  );
}

const LABEL_CLASSES: Record<string, string> = {
  issue: "bg-amber-500 text-black",
  suggestion: "bg-amber-500 text-black",
  question: "bg-blue-600 text-white",
  nitpick: "text-muted-foreground",
  praise: "bg-green-600 text-white",
};

function labelClass(finding: FindingView): string {
  if (finding.blocking) {
    return "bg-destructive text-white";
  }
  return LABEL_CLASSES[finding.label] ?? "bg-muted text-foreground";
}

function labelVariant(finding: FindingView): "default" | "outline" {
  return !finding.blocking && finding.label === "nitpick" ? "outline" : "default";
}

function locationOf(finding: FindingView): string {
  return finding.line === null ? finding.path : `${finding.path}:${finding.line}`;
}

function formatSeconds(seconds: number): string {
  return `${Math.round(seconds)}s`;
}
