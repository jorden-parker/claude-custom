import Markdown from "react-markdown";

export function MarkdownText({ children }: { children: string }) {
  return (
    <div className="break-words text-sm leading-relaxed [overflow-wrap:anywhere] [&_code]:rounded [&_code]:bg-muted [&_code]:px-1 [&_pre]:overflow-x-auto [&_pre]:rounded [&_pre]:bg-muted [&_pre]:p-2 [&_ul]:list-disc [&_ul]:pl-5 [&_ol]:list-decimal [&_ol]:pl-5">
      <Markdown>{children}</Markdown>
    </div>
  );
}
