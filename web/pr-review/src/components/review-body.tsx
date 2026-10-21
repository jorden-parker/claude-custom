"use client";

import {
  CircleAlertIcon,
  CircleCheckIcon,
  ChevronDownIcon,
  ListIcon,
  Loader2Icon,
} from "lucide-react";
import type { ReactNode } from "react";
import {
  Attachment,
  AttachmentInfo,
  AttachmentPreview,
  Attachments,
} from "@/components/ai-elements/attachments";
import { Task, TaskContent, TaskItem, TaskTrigger } from "@/components/ai-elements/task";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from "@/components/ui/collapsible";
import { Message, MessageContent } from "@/components/ui/message";
import {
  isFileOpenByDefault,
  type FileView,
  type FindingView,
  type ReviewState,
  type StageView,
  type VerdictView,
} from "@/lib/review-state";
import { headerStatusLabel, statusTextClass } from "@/lib/status-style";
import { verdictClass } from "@/lib/verdict-style";
import { InlineMarkdown, MarkdownText } from "./markdown-text";

type ReviewBodyProps = {
  state: ReviewState;
  elapsedSeconds: number;
};

export function ReviewBody({ state, elapsedSeconds }: ReviewBodyProps) {
  const shownSeconds = state.ended ? state.lastSeconds : elapsedSeconds;
  return (
    <div className="flex flex-col gap-6">
      <ReviewHeader state={state} seconds={shownSeconds} />
      {state.error ? <ErrorBanner message={state.error} /> : null}
      <ChangedFiles files={state.files} />
      <ProgressTask stages={state.stages} />
      <div className="flex flex-col gap-3">
        {state.files.map((file) => (
          <FileTask key={file.index} file={file} />
        ))}
      </div>
      {state.verdict ? <VerdictBanner verdict={state.verdict} summary={state.summary} /> : null}
      {state.report ? <ReportSection report={state.report} /> : null}
    </div>
  );
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

function ChangedFiles({ files }: { files: FileView[] }) {
  if (files.length === 0) {
    return null;
  }
  return (
    <section className="flex flex-col gap-2">
      <h2 className="font-medium text-sm">Changed files</h2>
      <Attachments variant="inline">
        {files.map((file) => (
          <Attachment
            key={file.index}
            data={{
              id: String(file.index),
              type: "file",
              mediaType: "text/plain",
              filename: file.path,
              url: "",
            }}
          >
            <AttachmentPreview />
            <AttachmentInfo />
            <Badge variant="secondary" className="shrink-0 text-xs">
              {fileBadgeText(file)}
            </Badge>
          </Attachment>
        ))}
      </Attachments>
    </section>
  );
}

function fileBadgeText(file: FileView): string {
  const state = file.state === "done" ? "done" : "running";
  const findings = file.findings.length;
  return findings > 0 ? `${state} · ${findings} finding${findings === 1 ? "" : "s"}` : state;
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

function FileTask({ file }: { file: FileView }) {
  const title = `[${file.index}/${file.total}] ${file.path}`;
  return (
    <Task defaultOpen={isFileOpenByDefault(file)}>
      <TaskTrigger title={title}>
        <TaskHeading icon={<FileStateIcon file={file} />} title={title} />
      </TaskTrigger>
      <TaskContent>
        <FileStatusLine file={file} />
        {file.findings.map((finding, index) => (
          <FindingMessage key={index} finding={finding} />
        ))}
        {file.retries.map((reply, index) => (
          <pre
            key={index}
            className="max-h-48 overflow-auto whitespace-pre-wrap break-words rounded bg-muted p-2 font-mono text-xs text-muted-foreground"
          >
            {reply}
          </pre>
        ))}
      </TaskContent>
    </Task>
  );
}

function TaskHeading({ icon, title }: { icon: ReactNode; title: string }) {
  return (
    <div className="flex w-full min-w-0 cursor-pointer items-center gap-2 text-sm text-muted-foreground transition-colors hover:text-foreground">
      {icon}
      <span className="min-w-0 break-words">{title}</span>
      <ChevronDownIcon className="ml-auto size-4 shrink-0 transition-transform group-data-[state=open]:rotate-180" />
    </div>
  );
}

function FileStateIcon({ file }: { file: FileView }) {
  if (file.state !== "done") {
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
    file.seconds === null ? (file.outcome ?? "") : `${file.outcome ?? ""} · ${formatSeconds(file.seconds)}`,
};

function FileStatusLine({ file }: { file: FileView }) {
  const pulse = file.state === "done" ? "" : "animate-pulse ";
  return <p className={`${pulse}text-sm text-muted-foreground`}>{fileStatusText[file.state](file)}</p>;
}

function FindingMessage({ finding }: { finding: FindingView }) {
  return (
    <Message>
      <MessageContent>
        <div className="flex flex-wrap items-center gap-2">
          <Badge className={labelClass(finding)}>
            {finding.label}
            {finding.blocking ? " · blocking" : ""}
          </Badge>
          <code className="break-all rounded bg-muted px-1.5 py-0.5 font-mono text-xs">{locationOf(finding)}</code>
          <span className="text-xs text-muted-foreground">confidence: {finding.confidence}</span>
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
      <CollapsibleTrigger className="text-sm font-medium underline">Full report</CollapsibleTrigger>
      <CollapsibleContent className="pt-3">
        <MarkdownText>{report}</MarkdownText>
      </CollapsibleContent>
    </Collapsible>
  );
}

function labelClass(finding: FindingView): string {
  if (finding.blocking) {
    return "bg-destructive text-white";
  }
  if (finding.label === "issue") {
    return "bg-amber-500 text-black";
  }
  return "bg-muted text-foreground";
}

function locationOf(finding: FindingView): string {
  return finding.line === null ? finding.path : `${finding.path}:${finding.line}`;
}

function formatSeconds(seconds: number): string {
  return `${Math.round(seconds)}s`;
}
