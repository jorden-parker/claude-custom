export type MockPreset = {
  id: string;
  name: string;
  summary: string;
  prompt: string;
};

export const MOCK_PRESETS: readonly MockPreset[] = [
  {
    id: "calm-saas",
    name: "Calm SaaS",
    summary: "White surfaces, zinc greys, one blue accent",
    prompt:
      "Calm product UI: generous whitespace, short labels, one clear primary action per screen, nothing decorative. Content first, chrome second.",
  },
  {
    id: "dense-admin",
    name: "Dense admin",
    summary: "Tight spacing, slate greys, indigo accent",
    prompt:
      "Dense operator tooling: small gaps, more items per group, terse labels, status badges where they help scanning, no marketing copy.",
  },
  {
    id: "editorial",
    name: "Editorial",
    summary: "Cream paper, serif type, terracotta accent",
    prompt:
      "Editorial layout: strong headings, longer descriptive text in full sentences, few buttons, vertical rhythm over grids. Reads like a well set page.",
  },
  {
    id: "playful",
    name: "Playful",
    summary: "Soft lilac, big radii, violet accent",
    prompt:
      "Friendly consumer app: warm conversational labels, rounded shapes, badges as encouragement, one bold primary action, short cheerful copy.",
  },
  {
    id: "brutalist",
    name: "Brutalist",
    summary: "Black lines, no radius, monospace, yellow accent",
    prompt:
      "Brutalist interface: plain monospace labels, hard edges, uppercase-feeling brevity, no softening words, buttons that look like controls not invitations.",
  },
];

export const DEFAULT_PRESET_ID = MOCK_PRESETS[0].id;

export function presetIds(): string[] {
  return MOCK_PRESETS.map((preset) => preset.id);
}

export function presetOrDefault(id: string | null | undefined): MockPreset {
  return MOCK_PRESETS.find((preset) => preset.id === id) ?? MOCK_PRESETS[0];
}
