import { defineCatalog } from "@json-render/core";
import { schema } from "@json-render/react/schema";
import { z } from "zod";

export const mockCatalog = defineCatalog(schema, {
  components: {
    Stack: {
      props: z.object({
        direction: z.enum(["vertical", "horizontal"]),
        gap: z.enum(["sm", "md", "lg"]).nullable(),
      }),
      slots: ["default"],
      description: "Lays children out in a column or a row",
    },
    Card: {
      props: z.object({
        title: z.string(),
        description: z.string().nullable(),
      }),
      slots: ["default"],
      description: "A bordered panel with a title",
    },
    Heading: {
      props: z.object({
        text: z.string(),
        level: z.enum(["1", "2", "3"]),
      }),
      description: "A section heading",
    },
    Text: {
      props: z.object({
        text: z.string(),
        muted: z.boolean().nullable(),
      }),
      description: "A paragraph of body text",
    },
    Button: {
      props: z.object({
        label: z.string(),
        variant: z.enum(["primary", "secondary", "ghost"]),
      }),
      description: "A clickable button",
    },
    Input: {
      props: z.object({
        label: z.string(),
        placeholder: z.string().nullable(),
      }),
      description: "A labelled text field",
    },
    Badge: {
      props: z.object({
        text: z.string(),
        tone: z.enum(["neutral", "success", "warning"]),
      }),
      description: "A small status pill",
    },
  },
  actions: {},
});

const mockPromptRules = [
  "Use Stack as the root and for every group of siblings",
  "Never use state, repeat, on, visible or watch; this is a static mockup",
];

export function mockSystemPrompt(): string {
  return mockCatalog.prompt({ customRules: mockPromptRules });
}
