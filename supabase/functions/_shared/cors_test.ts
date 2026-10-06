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
  assertEquals(ORIGEM_PADRAO, "https://marineflow-erp.vercel.app");
  const semOrigin = new Request("https://x/f");
  assertEquals(aplicarCors(semOrigin, new Response(null)).headers.get("Access-Control-Allow-Origin"), ORIGEM_PADRAO);
});

Deno.test("corsHeadersPara inclui os cabeçalhos extras e o cron secret", () => {
  const h = corsHeadersPara(null, { headersExtra: ["x-fiscal-signature"] });
  assertEquals(h["Access-Control-Allow-Origin"], ORIGEM_PADRAO);
  assertEquals(h["Access-Control-Allow-Headers"].includes("x-cron-secret"), true);
  assertEquals(h["Access-Control-Allow-Headers"].endsWith("x-fiscal-signature"), true);
});

// ── Registro de falha de toda função (06/10/2026) ──
import { comCorsERegistro, type FalhaDaFuncao, nomeDaFuncao } from "./cors.ts";

function registro() {
  const falhas: FalhaDaFuncao[] = [];
  return { falhas, registrar: async (f: FalhaDaFuncao) => void falhas.push(f) };
}
const pedido = (caminho = "/functions/v1/banking-sync") =>
  new Request(`https://x.supabase.co${caminho}`, { method: "POST", headers: { origin: "https://marineflow-erp.vercel.app" } });

Deno.test("nomeDaFuncao: tira o nome do caminho, com ou sem /functions/v1", () => {
  assertEquals(nomeDaFuncao("https://x.supabase.co/functions/v1/banking-sync"), "banking-sync");
  assertEquals(nomeDaFuncao("https://x.supabase.co/functions/v1/erp-mcp/mcp"), "erp-mcp");
  assertEquals(nomeDaFuncao("http://localhost:54321/fiscal-emit"), "fiscal-emit");
});

Deno.test("exceção não tratada vira 500 com CORS e fica registrada com o nome da função", async () => {
  const r = registro();
  const res = await comCorsERegistro(() => { throw new Error("coluna x não existe"); }, r.registrar)(pedido());
  assertEquals(res.status, 500);
  assertEquals(res.headers.get("Access-Control-Allow-Origin"), "https://marineflow-erp.vercel.app");
  assertEquals((await res.json()).error, "Erro interno em banking-sync: coluna x não existe");
  assertEquals(r.falhas.length, 1);
  assertEquals(r.falhas[0].funcao, "banking-sync");
  assertEquals(r.falhas[0].mensagem, "Exceção não tratada: coluna x não existe");
});

Deno.test("resposta 5xx é registrada com o corpo; o corpo segue intacto para quem chamou", async () => {
  const r = registro();
  const res = await comCorsERegistro(() => new Response('{"error":"Pluggy fora"}', { status: 502 }), r.registrar)(pedido());
  assertEquals(res.status, 502);
  assertEquals(await res.text(), '{"error":"Pluggy fora"}');
  assertEquals(r.falhas.map((f) => [f.status, f.mensagem]), [[502, '{"error":"Pluggy fora"}']]);
});

Deno.test("o status real do X-Actual-Status (ai-agent) também conta; 2xx e 4xx não registram", async () => {
  const r = registro();
  await comCorsERegistro(() => new Response("{}", { status: 200, headers: { "X-Actual-Status": "500" } }), r.registrar)(pedido("/functions/v1/ai-agent"));
  await comCorsERegistro(() => new Response("ok"), r.registrar)(pedido());
  await comCorsERegistro(() => new Response("sem permissão", { status: 403 }), r.registrar)(pedido());
  assertEquals(r.falhas.map((f) => [f.funcao, f.status]), [["ai-agent", 500]]);
});
