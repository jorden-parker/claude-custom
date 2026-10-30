import type { ComponentPropsWithoutRef } from "react";
import Markdown from "react-markdown";
import remarkGfm from "remark-gfm";

const BLOCK_BODY_CLASS =
  "break-words text-sm leading-relaxed [overflow-wrap:anywhere] [&_code]:rounded [&_code]:bg-muted [&_code]:px-1 [&_p+p]:mt-2 [&_pre]:my-2 [&_pre]:overflow-x-auto [&_pre]:rounded [&_pre]:bg-muted [&_pre]:p-2 [&_ul]:my-2 [&_ul]:list-disc [&_ul]:pl-5 [&_ol]:my-2 [&_ol]:list-decimal [&_ol]:pl-5 [&_h1]:mt-4 [&_h1]:mb-2 [&_h1]:text-lg [&_h1]:font-semibold [&_h2]:mt-4 [&_h2]:mb-2 [&_h2]:text-base [&_h2]:font-semibold [&_h3]:mt-3 [&_h3]:mb-1 [&_h3]:font-semibold [&_blockquote]:my-2 [&_blockquote]:border-l-2 [&_blockquote]:pl-3 [&_table]:my-2 [&_table]:block [&_table]:overflow-x-auto [&_td]:border [&_td]:px-2 [&_td]:py-1 [&_th]:border [&_th]:px-2 [&_th]:py-1";

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
        remarkPlugins={[remarkGfm]}
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
