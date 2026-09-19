// Run: deno test supabase/functions/_shared/cors_test.ts
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { aplicarCors, corsHeadersPara, ORIGEM_PADRAO, origemPermitida } from "./cors.ts";

Deno.test("origens do ERP passam: produção, vercel.app do projeto, previews e dev local", () => {
  for (const o of [
    "https://hbrmarine.online",
    "https://www.hbrmarine.online",
    "https://marineflow-erp.vercel.app",
    "https://marineflow-erp-git-main-gseberino-s-projects.vercel.app",
    "https://marineflow-5fpis8wh0-gseberino-s-projects.vercel.app",
    "https://app.hbrmarine.online",
    "http://localhost:5173",
    "http://127.0.0.1:8080",
  ]) {
    assertEquals(origemPermitida(o), o, o);
  }
});

Deno.test("origens alheias e formas parecidas não passam", () => {
  for (const o of [
    "https://malicioso.example",
    "https://hbrmarine.online.evil.com",
    "https://outro-projeto-abc.vercel.app",
    "http://hbrmarine.online", // sem TLS
    "https://localhost:5173", // dev é http
    "null",
    "",
    null,
    undefined,
  ]) {
    assertEquals(origemPermitida(o as string), null, String(o));
  }
});

Deno.test("resposta pronta ganha o Allow-Origin da origem permitida e Vary: Origin", () => {
  const req = new Request("https://x.supabase.co/functions/v1/whatsapp-send", {
    headers: { origin: "https://marineflow-erp.vercel.app" },
  });
  const res = aplicarCors(req, new Response("ok", { status: 201, headers: { "Access-Control-Allow-Origin": "*", "X-Outro": "1" } }));
  assertEquals(res.status, 201);
  assertEquals(res.headers.get("Access-Control-Allow-Origin"), "https://marineflow-erp.vercel.app");
  assertEquals(res.headers.get("Vary"), "Origin");
  assertEquals(res.headers.get("X-Outro"), "1");
});

Deno.test("origem alheia recebe a origem padrão (o navegador bloqueia); sem Origin também", () => {
  const alheia = new Request("https://x/f", { headers: { origin: "https://malicioso.example" } });
  assertEquals(aplicarCors(alheia, new Response(null)).headers.get("Access-Control-Allow-Origin"), ORIGEM_PADRAO);
  const semOrigin = new Request("https://x/f");
  assertEquals(aplicarCors(semOrigin, new Response(null)).headers.get("Access-Control-Allow-Origin"), ORIGEM_PADRAO);
});

Deno.test("corsHeadersPara inclui os cabeçalhos extras e o cron secret", () => {
  const h = corsHeadersPara(null, { headersExtra: ["x-fiscal-signature"] });
  assertEquals(h["Access-Control-Allow-Origin"], ORIGEM_PADRAO);
  assertEquals(h["Access-Control-Allow-Headers"].includes("x-cron-secret"), true);
  assertEquals(h["Access-Control-Allow-Headers"].endsWith("x-fiscal-signature"), true);
});
