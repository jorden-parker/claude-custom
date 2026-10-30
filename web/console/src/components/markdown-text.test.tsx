import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import { MarkdownText } from "./markdown-text";

describe("MarkdownText", () => {
  it("never renders a markdown image from model text", () => {
    const markup = renderToStaticMarkup(
      <MarkdownText>
        {"Look ![tracker](https://attacker.example/p.png) here"}
      </MarkdownText>,
    );

    expect(markup).not.toContain("<img");
    expect(markup).not.toContain("attacker.example");
    expect(markup).toContain("Look");
    expect(markup).toContain("here");
  });

  it("keeps an http link as a link", () => {
    const markup = renderToStaticMarkup(
      <MarkdownText>{"[docs](https://example.com/docs)"}</MarkdownText>,
    );

    expect(markup).toContain('href="https://example.com/docs"');
  });

  it("renders a GitHub table as a table", () => {
    const markup = renderToStaticMarkup(
      <MarkdownText>{"| a | b |\n| - | - |\n| 1 | 2 |"}</MarkdownText>,
    );

    expect(markup).toContain("<table");
  });

  it("renders a GitHub task list item as a checkbox", () => {
    const markup = renderToStaticMarkup(
      <MarkdownText>{"- [ ] todo"}</MarkdownText>,
    );

    expect(markup).toContain('type="checkbox"');
  });

  it("renders a section heading as a heading", () => {
    const markup = renderToStaticMarkup(
      <MarkdownText>{"## Summary"}</MarkdownText>,
    );

    expect(markup).toContain("<h2");
  });
});
