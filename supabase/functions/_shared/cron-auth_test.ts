// Testes da autenticação de cron (MF-AUD-054).
//
// As três funções que usam este helper (whatsapp-queue-worker,
// whatsapp-status-worker, whatsapp-process-scheduled) rodam com
// verify_jwt=false e ENVIAM MENSAGEM DE VERDADE. Sem o segredo, a URL fica
// aberta: qualquer um dispara a fila fora de hora e esgota o limite horário.

import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { verificarCronSecret } from "./cron-auth.ts";

const SEGREDO = "cron-secret-de-teste-nao-real";
const CORS = { "Access-Control-Allow-Origin": "*" };
const URL_FN = "https://exemplo.supabase.co/functions/v1/whatsapp-queue-worker";

const req = (headers?: Record<string, string>) =>
  new Request(URL_FN, { method: "POST", body: "{}", headers });

Deno.test("sem cabeçalho x-cron-secret → 401", async () => {
  Deno.env.set("CRON_SECRET", SEGREDO);
  const res = verificarCronSecret(req(), CORS, "teste");
  assertEquals(res?.status, 401);
  assertEquals((await res!.json()).error, "unauthorized");
});

Deno.test("com segredo errado → 401", () => {
  Deno.env.set("CRON_SECRET", SEGREDO);
  const res = verificarCronSecret(req({ "x-cron-secret": "chute" }), CORS, "teste");
  assertEquals(res?.status, 401);
});

Deno.test("segredo de tamanho diferente → 401 (não quebra a comparação)", () => {
  Deno.env.set("CRON_SECRET", SEGREDO);
  const res = verificarCronSecret(req({ "x-cron-secret": "x" }), CORS, "teste");
  assertEquals(res?.status, 401);
});

Deno.test("com o segredo correto → autoriza (null)", () => {
  Deno.env.set("CRON_SECRET", SEGREDO);
  assertEquals(verificarCronSecret(req({ "x-cron-secret": SEGREDO }), CORS, "teste"), null);
});

Deno.test("sem CRON_SECRET configurado → 500, rejeita tudo (fail-closed)", async () => {
  Deno.env.delete("CRON_SECRET");
  try {
    const res = verificarCronSecret(req({ "x-cron-secret": "qualquer" }), CORS, "teste");
    assertEquals(res?.status, 500);
    assertEquals((await res!.json()).error, "not_configured");
  } finally {
    Deno.env.set("CRON_SECRET", SEGREDO);
  }
});

Deno.test("a recusa preserva os cabeçalhos de CORS", () => {
  Deno.env.set("CRON_SECRET", SEGREDO);
  const res = verificarCronSecret(req(), CORS, "teste");
  assertEquals(res?.headers.get("Access-Control-Allow-Origin"), "*");
});
