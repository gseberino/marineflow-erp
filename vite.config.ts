import { defineConfig, normalizePath, type Plugin } from "vite";
import react from "@vitejs/plugin-react-swc";
import path from "path";
import { componentTagger } from "lovable-tagger";

// As fontes da marca (~93 KB em base64, supabase/functions/_shared/pdf/marca-fontes.ts) só chegam na tela quando uma
// folha vai ser montada: o `./marca-fontes.ts` que o marca.ts importa vira src/lib/marca-fontes-sob-demanda.ts, que as
// busca por import dinâmico (pedaço próprio). Sem isto elas iam no pedaço compartilhado de toda tela de embarcação e de
// OS (26/11/2026). O servidor (Deno) e o vitest (vitest.config.ts) usam o arquivo de verdade.
const fontesDaMarcaSobDemanda: Plugin = {
  name: "fontes-da-marca-sob-demanda",
  enforce: "pre",
  resolveId(fonte, quemImporta) {
    if (fonte === "./marca-fontes.ts" && quemImporta && /[\\/]_shared[\\/]pdf[\\/]marca\.ts$/.test(quemImporta)) {
      // normalizePath: com barra invertida (Windows) o Vite via DOIS módulos — o do marca.ts e o do route-sheet.ts —, e o
      // marca.ts nunca enxergava as fontes carregadas.
      return normalizePath(path.resolve(__dirname, "./src/lib/marca-fontes-sob-demanda.ts"));
    }
    return null;
  },
};

// https://vitejs.dev/config/
export default defineConfig(({ mode }) => ({
  server: {
    host: "::",
    port: 8080,
    hmr: {
      overlay: false,
    },
  },
  plugins: [fontesDaMarcaSobDemanda, react(), mode === "development" && componentTagger()].filter(Boolean),
  build: {
    // MF-AUD-048: a divisão manual por pacote (19/09/2026) DERRUBOU a aplicação — tela branca
    // com "Cannot access 'P' before initialization" vindo de vendor-charts. Causa: separar
    // pacotes em chunks manuais cria ciclo de importação ENTRE chunks (recharts depende de
    // módulos que ficaram noutro chunk, e aquele chunk depende de volta), e o ciclo vira
    // violação de TDZ na hora de avaliar — coisa que `tsc`, `vite build` e os testes de
    // componente não pegam, porque só existe no bundle final avaliado pelo navegador.
    //
    // O chunk único de 2,26 MB é o preço de uma aplicação que abre. Se voltarmos a dividir,
    // a regra é: provar por RENDER (abrir o build no navegador e exigir #root preenchido)
    // antes de publicar — ver scripts/verifica-build-renderiza.mjs.
  },
  resolve: {
    alias: {
      "@": path.resolve(__dirname, "./src"),
    },
    dedupe: ["react", "react-dom", "react/jsx-runtime", "react/jsx-dev-runtime", "@tanstack/react-query", "@tanstack/query-core"],
  },
}));
