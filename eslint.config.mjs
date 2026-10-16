import js from "@eslint/js";
import prettier from "eslint-config-prettier";
import react from "eslint-plugin-react";
import reactHooks from "eslint-plugin-react-hooks";
import tseslint from "typescript-eslint";

export default tseslint.config(
  { ignores: ["node_modules", "dist", "build", "coverage", ".husky"] },
  js.configs.recommended,
  ...tseslint.configs.recommended,
  {
    files: ["**/*.{jsx,tsx}"],
    ...react.configs.flat.recommended,
    ...react.configs.flat["jsx-runtime"],
    settings: { react: { version: "detect" } },
  },
  reactHooks.configs.flat.recommended,
  prettier,
);
