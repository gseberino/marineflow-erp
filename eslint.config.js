import js from "@eslint/js";
import globals from "globals";
import reactHooks from "eslint-plugin-react-hooks";
import reactRefresh from "eslint-plugin-react-refresh";
import tseslint from "typescript-eslint";

export default tseslint.config(
  { ignores: ["dist"] },
  {
    extends: [js.configs.recommended, ...tseslint.configs.recommended],
    files: ["**/*.{ts,tsx}"],
    languageOptions: {
      ecmaVersion: 2020,
      globals: globals.browser,
    },
    plugins: {
      "react-hooks": reactHooks,
      "react-refresh": reactRefresh,
    },
    rules: {
      ...reactHooks.configs.recommended.rules,
      "react-refresh/only-export-components": ["warn", { allowConstantExport: true }],
      "@typescript-eslint/no-unused-vars": "off",
    },
  },
  {
    // ── Governança do UI v2 (Fase 0) ──────────────────────────────────────
    // 1. Cores cruas do Tailwind proibidas: tudo via token semântico.
    // 2. Princípio 0 (zero scroll horizontal): min-w-[px] e overflow-x-auto
    //    proibidos — o DataTable faz orçamento de colunas.
    // Escopo: só código v2/migrado; as telas antigas não são afetadas.
    files: ["src/v2/**/*.{ts,tsx}", "src/pages/DesignPreviewV2.tsx"],
    rules: {
      "no-restricted-syntax": [
        "error",
        {
          selector:
            "Literal[value=/(?:^|[^a-zA-Z-])(?:red|blue|emerald|green|amber|orange|purple|rose|sky|teal|slate|zinc|gray|stone|neutral|lime|cyan|indigo|violet|fuchsia|pink|yellow)-(?:50|[1-9]50?0?)(?:[^0-9]|$)/]",
          message:
            "Cor crua do Tailwind proibida no v2 — use tokens semânticos (primary, accent, info, success, warning, destructive, muted).",
        },
        {
          selector: "TemplateElement[value.raw=/(?:^|[^a-zA-Z-])(?:red|blue|emerald|green|amber|orange|purple|rose|sky|teal|slate|zinc|gray|stone|neutral|lime|cyan|indigo|violet|fuchsia|pink|yellow)-(?:50|[1-9]50?0?)(?:[^0-9]|$)/]",
          message:
            "Cor crua do Tailwind proibida no v2 — use tokens semânticos.",
        },
        {
          selector: "Literal[value=/min-w-\\u005B/]",
          message:
            "min-w-[px] proibido no v2 — o DataTable faz orçamento de colunas; nada rola para o lado (Princípio 0).",
        },
        {
          selector: "Literal[value=/overflow-x-auto|overflow-x-scroll/]",
          message:
            "overflow-x proibido no v2 — Princípio 0: zero scroll horizontal.",
        },
      ],
    },
  },
);
