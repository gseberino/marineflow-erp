// Testes de autenticação do whatsapp-webhook (MF-AUD-053).
//
// O que estes testes protegem: a função roda com verify_jwt=false — o segredo
// compartilhado é a ÚNICA autenticação. Antes desta correção, um GET anônimo
// devolvia telefone e corpo das últimas mensagens recebidas, e outro GET
// disparava um DELETE em whatsapp_leads.
//
// Os casos de recusa não tocam o banco de propósito: a verificação acontece
// antes de qualquer I/O, então o handler pode ser exercitado sem Supabase.

import { assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";

const SEGREDO = "segredo-de-teste-nao-real";
const URL_FN = "https://exemplo.supabase.co/functions/v1/whatsapp-webhook";

Deno.env.set("EVOLUTION_WEBHOOK_TOKEN", SEGREDO);
// Valores de fachada: os testes de recusa param antes de usar o client.
Deno.env.set("SUPABASE_URL", "https://exemplo.supabase.co");
Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "chave-de-fachada");

const { verificarSegredo, handler } = await import("./index.ts");

Deno.test("POST sem segredo é recusado com 401", async () => {
  const res = await handler(new Request(URL_FN, { method: "POST", body: "{}" }));
  assertEquals(res.status, 401);
  assertEquals((await res.json()).error, "unauthorized");
});

Deno.test("POST com segredo errado é recusado com 401", async () => {
  const res = await handler(
    new Request(`${URL_FN}?token=chute`, { method: "POST", body: "{}" }),
  );
  assertEquals(res.status, 401);
});

Deno.test("GET anônimo no healthcheck é recusado com 401 (não vaza mensagem)", async () => {
  const res = await handler(new Request(`${URL_FN}?healthcheck=1`, { method: "GET" }));
  assertEquals(res.status, 401);
  const corpo = await res.text();
  assertEquals(corpo.includes("recent_messages"), false);
  assertEquals(corpo.includes("phone"), false);
});

Deno.test("GET anônimo sem parâmetro é recusado com 401 (não apaga lead)", async () => {
  const res = await handler(new Request(URL_FN, { method: "GET" }));
  assertEquals(res.status, 401);
});

Deno.test("segredo correto passa pela verificação — por query string", () => {
  const req = new Request(`${URL_FN}?token=${SEGREDO}`, { method: "POST", body: "{}" });
  assertEquals(verificarSegredo(req), null);
});

Deno.test("segredo correto passa pela verificação — por cabeçalho", () => {
  const req = new Request(URL_FN, {
    method: "POST",
    body: "{}",
    headers: { "x-webhook-token": SEGREDO },
  });
  assertEquals(verificarSegredo(req), null);
});

Deno.test("requisição legítima ultrapassa a autenticação e chega ao processamento", async () => {
  // Payload vazio: passa da auth e é recusado pela validação de conteúdo (400),
  // o que prova que a autenticação não é mais o ponto de parada.
  const res = await handler(
    new Request(`${URL_FN}?token=${SEGREDO}`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: "nao-e-json",
    }),
  );
  assertEquals(res.status, 400);
  assertEquals((await res.json()).error, "No payload");
});

Deno.test("OPTIONS (preflight CORS) continua respondendo sem segredo", async () => {
  const res = await handler(new Request(URL_FN, { method: "OPTIONS" }));
  assertEquals(res.status, 200);
});

Deno.test("sem o secret configurado, rejeita tudo com 500 (fail-closed)", async () => {
  const anterior = Deno.env.get("EVOLUTION_WEBHOOK_TOKEN")!;
  Deno.env.delete("EVOLUTION_WEBHOOK_TOKEN");
  try {
    const res = await handler(new Request(`${URL_FN}?token=qualquer`, { method: "POST", body: "{}" }));
    assertEquals(res.status, 500);
    assertStringIncludes(await res.text(), "not_configured");
  } finally {
    Deno.env.set("EVOLUTION_WEBHOOK_TOKEN", anterior);
  }
});
