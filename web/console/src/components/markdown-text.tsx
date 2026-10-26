import type { ComponentPropsWithoutRef } from "react";
import Markdown from "react-markdown";

const BLOCK_BODY_CLASS =
  "break-words text-sm leading-relaxed [overflow-wrap:anywhere] [&_code]:rounded [&_code]:bg-muted [&_code]:px-1 [&_p+p]:mt-2 [&_pre]:my-2 [&_pre]:overflow-x-auto [&_pre]:rounded [&_pre]:bg-muted [&_pre]:p-2 [&_ul]:my-2 [&_ul]:list-disc [&_ul]:pl-5 [&_ol]:my-2 [&_ol]:list-decimal [&_ol]:pl-5";

const INLINE_BODY_CLASS =
  "break-words [overflow-wrap:anywhere] [&_code]:rounded [&_code]:bg-muted [&_code]:px-1";

const INLINE_ELEMENTS = ["p", "code", "strong", "em", "a"];

function safeUrl(url: string): string {
  return /^https?:/i.test(url) ? url : "";
}

function ModelLink({ href, children }: ComponentPropsWithoutRef<"a">) {
  if (!href) {
    return <>{children}</>;
  }
  return (
    <a href={href} target="_blank" rel="noreferrer noopener">
      {children}
    </a>
  );
}

function ModelImage({ alt }: ComponentPropsWithoutRef<"img">) {
  return <>{alt}</>;
}

function InlineParagraph({ children }: ComponentPropsWithoutRef<"p">) {
  return <span className="block">{children}</span>;
}

export function MarkdownText({ children }: { children: string }) {
  return (
    <div className={BLOCK_BODY_CLASS}>
      <Markdown
        urlTransform={safeUrl}
        components={{ a: ModelLink, img: ModelImage }}
      >
        {children}
      </Markdown>
    </div>
  );
}

export function InlineMarkdown({ children }: { children: string }) {
  return (
    <span className={INLINE_BODY_CLASS}>
      <Markdown
        allowedElements={INLINE_ELEMENTS}
        unwrapDisallowed
        urlTransform={safeUrl}
        components={{ a: ModelLink, p: InlineParagraph }}
      >
        {children}
      </Markdown>
    </span>
  );
}
