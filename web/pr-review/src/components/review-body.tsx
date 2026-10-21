"use client";

import {
  Attachment,
  AttachmentInfo,
  Attachments,
} from "@/components/ai-elements/attachments";
import { Task, TaskContent, TaskItem, TaskTrigger } from "@/components/ai-elements/task";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from "@/components/ui/collapsible";
import { Message, MessageContent } from "@/components/ui/message";
import type {
  FileState,
  FileView,
  FindingView,
  ReviewState,
  StageView,
  VerdictView,
} from "@/lib/review-state";
import { verdictClass } from "@/lib/verdict-style";
import { MarkdownText } from "./markdown-text";

type ReviewBodyProps = {
  state: ReviewState;
  elapsedSeconds: number;
};

export function ReviewBody({ state, elapsedSeconds }: ReviewBodyProps) {
  return (
    <div className="flex flex-col gap-6">
      <ReviewHeader state={state} elapsedSeconds={elapsedSeconds} />
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

function ReviewHeader({ state, elapsedSeconds }: ReviewBodyProps) {
  return (
    <Card>
      <CardHeader>
        <CardTitle className="break-words">{state.header.name || "Review"}</CardTitle>
        <CardDescription className="break-words">{state.header.title}</CardDescription>
      </CardHeader>
      <CardContent className="flex flex-wrap items-center gap-2 text-sm">
        <Badge variant="outline">{state.header.status}</Badge>
        <span className="break-all text-muted-foreground">{state.header.model}</span>
        <span className="text-muted-foreground">{formatSeconds(elapsedSeconds)}</span>
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
      <Attachments variant="list">
        {files.map((file) => (
          <div key={file.index} className="flex min-w-0 items-center gap-2">
            <Attachment
              data={{
                id: String(file.index),
                type: "file",
                mediaType: "text/plain",
                filename: file.path,
                url: "",
              }}
            >
              <AttachmentInfo />
            </Attachment>
            <span className={file.state === "done" ? "text-xs text-muted-foreground" : "animate-pulse text-xs text-muted-foreground"}>
              {file.state}
            </span>
          </div>
        ))}
      </Attachments>
    </section>
  );
}

function ProgressTask({ stages }: { stages: StageView[] }) {
  if (stages.length === 0) {
    return null;
  }
  return (
    <Task defaultOpen>
      <TaskTrigger title="Review progress" />
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
  return (
    <Task defaultOpen={file.state !== "done"}>
      <TaskTrigger title={`[${file.index}/${file.total}] ${file.path}`} />
      <TaskContent>
        <FileStatusLine file={file} />
        {file.findings.map((finding, index) => (
          <FindingMessage key={index} finding={finding} />
        ))}
        {file.retries.map((reply, index) => (
          <p key={index} className="break-words text-xs text-muted-foreground">
            retry: {reply}
          </p>
        ))}
      </TaskContent>
    </Task>
  );
}

const fileStatusText: Record<FileState, (file: FileView) => string> = {
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
          <code className="break-all rounded bg-muted px-1.5 py-0.5 text-xs">{locationOf(finding)}</code>
          <span className="text-xs text-muted-foreground">confidence: {finding.confidence}</span>
        </div>
        <p className="mt-2 break-words text-sm font-medium">{finding.summary}</p>
        {finding.why ? <p className="break-words text-sm text-muted-foreground">{finding.why}</p> : null}
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
