import { defineConfig } from "vitest/config";
import react from "@vitejs/plugin-react-swc";
import path from "path";

export default defineConfig({
  plugins: [react()],
  test: {
    environment: "jsdom",
    globals: true,
    setupFiles: ["./src/test/setup.ts"],
    include: ["src/**/*.{test,spec}.{ts,tsx}"],
    // 15 s em vez dos 5 s padrão: com a suíte completa disputando CPU (várias sessões rodando
    // testes na mesma máquina), testes de tela estouravam o prazo e o que corria depois no mesmo
    // worker falhava em cascata com asserção falsa (texto digitado cortado) — 26/09/2026.
    testTimeout: 15_000,
  },
  resolve: {
    alias: { "@": path.resolve(__dirname, "./src") },
  },
});
