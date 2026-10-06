import { ORIGEM_PADRAO, servirComCors } from "../_shared/cors.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import { itemParaLer } from "../_shared/banking/aviso-do-pluggy.ts";
// Edge Function: pluggy-webhook
// Receptor dos webhooks do Pluggy (item/created, item/updated, item/error, ...).
// Chega SEM Authorization — verify_jwt=false no config.toml, como fiscal-webhook.
// Autenticação: token secreto na query string (?token=...), comparado com o
// secret PLUGGY_WEBHOOK_TOKEN (o Pluggy não assina o corpo com HMAC; o token na
// URL registrada no dashboard faz o papel de segredo compartilhado).
// Contrato do Pluggy: responder 2XX em até 5s — por isso este receptor só valida,
// loga e confirma; o trabalho pesado (buscar transações do item e gravar em
// bank_transactions) fica para a banking-sync da Fase 1, que será disparada daqui.

const corsHeaders = {
  "Access-Control-Allow-Origin": ORIGEM_PADRAO,
  "Access-Control-Allow-Headers": "content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function jr(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

// Comparação em tempo constante para não vazar o token por timing.
function timingSafeEqual(a: string, b: string): boolean {
  const enc = new TextEncoder();
  const ab = enc.encode(a);
  const bb = enc.encode(b);
  if (ab.length !== bb.length) return false;
  let diff = 0;
  for (let i = 0; i < ab.length; i++) diff |= ab[i] ^ bb[i];
  return diff === 0;
}

/** Acha a conexão do item e chama a banking-sync só para ela, com o segredo do cron. */
async function lerConexaoDoItem(itemId: string): Promise<void> {
  const url = Deno.env.get("SUPABASE_URL")!;
  const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
  const { data, error } = await admin.from("bank_connections").select("id, label")
    .eq("provider", "pluggy").eq("external_id", itemId).eq("active", true).maybeSingle();
  if (error) throw new Error(`não li a conexão do item: ${error.message}`);
  if (!data) {
    console.log("[pluggy-webhook] item sem conexão ativa no ERP:", itemId);
    return;
  }
  const segredo = Deno.env.get("CRON_SECRET");
  if (!segredo) throw new Error("CRON_SECRET ausente");
  const r = await fetch(`${url}/functions/v1/banking-sync`, {
    method: "POST",
    headers: { "Content-Type": "application/json", "x-cron-secret": segredo },
    body: JSON.stringify({ connection_id: data.id }),
  });
  console.log("[pluggy-webhook] leitura de", data.label, "→", r.status, (await r.text()).slice(0, 200));
}

servirComCors(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });
  if (req.method !== "POST") return jr({ error: "method_not_allowed" }, 405);

  const expected = Deno.env.get("PLUGGY_WEBHOOK_TOKEN");
  if (!expected) {
    console.error("[pluggy-webhook] PLUGGY_WEBHOOK_TOKEN ausente nos secrets — rejeitando tudo.");
    return jr({ error: "not_configured" }, 500);
  }
  const token = new URL(req.url).searchParams.get("token") ?? "";
  if (!timingSafeEqual(token, expected)) {
    console.warn("[pluggy-webhook] 401 — token da URL não confere.");
    return jr({ error: "unauthorized" }, 401);
  }

  const event = await req.json().catch(() => null);
  if (!event || typeof event.event !== "string") {
    return jr({ error: "invalid_payload" }, 400);
  }

  // Log estruturado para acompanhar o onboarding via get_logs enquanto a
  // persistência (bank_webhook_events) e o disparo da banking-sync não chegam.
  console.log("[pluggy-webhook] evento recebido:", JSON.stringify({
    event: event.event,
    eventId: event.eventId ?? null,
    itemId: event.itemId ?? null,
    triggeredBy: event.triggeredBy ?? null,
  }));

  switch (event.event) {
    case "item/created":
    case "item/updated": {
      // O Pluggy acabou de ir ao banco: lê ESTA conexão agora, em vez de esperar as buscas das 06h
      // e 15h (06/10/2026). Em segundo plano — o Pluggy quer a resposta em poucos segundos — e
      // pela mesma banking-sync do botão, que não duplica nada (dedupe por bank_ref_id).
      const itemId = itemParaLer(event);
      if (itemId) {
        const leitura = lerConexaoDoItem(itemId).catch((e) => console.error("[pluggy-webhook] leitura falhou:", e));
        // deno-lint-ignore no-explicit-any
        const rt = (globalThis as any).EdgeRuntime;
        if (rt?.waitUntil) rt.waitUntil(leitura);
      }
      break;
    }
    case "item/error":
      console.warn("[pluggy-webhook] item com erro:", event.itemId, JSON.stringify(event.error ?? {}));
      break;
    default:
      // Demais eventos (transactions/*, connector/*) são aceitos e apenas logados.
      break;
  }

  return jr({ received: true });
});
