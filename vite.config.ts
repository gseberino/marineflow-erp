import { defineConfig } from "vite";
import react from "@vitejs/plugin-react-swc";
import path from "path";
import { componentTagger } from "lovable-tagger";

// https://vitejs.dev/config/
export default defineConfig(({ mode }) => ({
  server: {
    host: "::",
    port: 8080,
    hmr: {
      overlay: false,
    },
  },
  plugins: [react(), mode === "development" && componentTagger()].filter(Boolean),
  build: {
    // MF-AUD-048 (19/09/2026): mesmo com 71 páginas em lazy, o chunk principal tinha 2,26 MB
    // porque todas as bibliotecas compartilhadas caíam nele. Separar por pacote faz o
    // navegador guardar em cache o que não muda entre deploys (React, Radix, Supabase,
    // gráficos, ícones) e baixar de novo só o código do app. Nenhum efeito funcional.
    rollupOptions: {
      output: {
        manualChunks(id) {
          if (!id.includes("node_modules")) return undefined;
          if (/[\\/]node_modules[\\/](react|react-dom|react-router|react-router-dom|scheduler)[\\/]/.test(id)) return "vendor-react";
          if (id.includes("/node_modules/@radix-ui/") || id.includes("\\node_modules\\@radix-ui\\")) return "vendor-radix";
          if (/[\\/]node_modules[\\/]@supabase[\\/]/.test(id)) return "vendor-supabase";
          if (/[\\/]node_modules[\\/]@tanstack[\\/]/.test(id)) return "vendor-query";
          if (/[\\/]node_modules[\\/](recharts|d3-[a-z-]+|victory-vendor)[\\/]/.test(id)) return "vendor-charts";
          if (/[\\/]node_modules[\\/]lucide-react[\\/]/.test(id)) return "vendor-icons";
          if (/[\\/]node_modules[\\/](date-fns|framer-motion|zod)[\\/]/.test(id)) return "vendor-utils";
          return undefined;
        },
      },
    },
  },
  resolve: {
    alias: {
      "@": path.resolve(__dirname, "./src"),
    },
    dedupe: ["react", "react-dom", "react/jsx-runtime", "react/jsx-dev-runtime", "@tanstack/react-query", "@tanstack/query-core"],
  },
}));
