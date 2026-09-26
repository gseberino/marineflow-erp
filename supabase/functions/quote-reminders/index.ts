// Edge Function: quote-reminders
// Runs daily via cron at 09:00 BRT (cron PAUSADO desde 26/09/2026 01h, a pedido do dono).
// 1. FOLLOW-UP: quotes stuck in sent/awaiting_approval for > quote_followup_days → queue WhatsApp follow-up
//
// ═══ A EXPIRAÇÃO SAIU DAQUI (26/09/2026) ═══
//
// Esta rotina também REJEITAVA sozinha todo orçamento em sent/awaiting_approval/
// awaiting_deposit com mais de `quote_expiry_days` (7) dias de CRIAÇÃO — sem audit_log, sem
// aviso, contando de uma data que não é a validade impressa no PDF e pegando inclusive
// orçamentos já aprovados aguardando sinal. Em 23-24/09 foram R$ 133 mil rejeitados assim.
//
// Decisão do dono (26/09/2026): vencer a validade gera um AVISO, e quem decide é ele. Isso é
// a regra R19 do motor de tarefas (task-automations/rules.ts, "Orçamento vencido: renovar ou
// rejeitar?"), que conta a validade como o PDF (do próprio orçamento, dia de Brasília) e
// nunca olha 'aguardando sinal'. Nada aqui muda o quote_status para 'rejected' — não volte
// a pôr: é a única rotina que fazia isso, e fazia em silêncio.
//
// O FOLLOW-UP abaixo NÃO foi consertado de propósito: ele nunca funcionou (grava colunas que
// a whatsapp_send_queue não tem e monta o link com a URL do Supabase), e consertá-lo passaria
// a mandar mensagem automática a clientes — decisão pendente do dono. Com o cron pausado,
// ele não roda.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import { ORIGEM_PADRAO, servirComCors } from "../_shared/cors.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": ORIGEM_PADRAO,
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-cron-secret",
};

function jr(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

servirComCors(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });

  try {
    const SUPABASE_URL    = Deno.env.get("SUPABASE_URL")!;
    const SERVICE_ROLE    = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const admin           = createClient(SUPABASE_URL, SERVICE_ROLE);

    // Load configurable thresholds from app_settings.
    // `quote_expiry_days` não é mais lido: a expiração virou aviso (R19, ver cabeçalho).
    const { data: settings } = await admin
      .from("app_settings")
      .select("key, value")
      .in("key", ["quote_followup_days"]);

    const sMap = Object.fromEntries((settings || []).map((s: any) => [s.key, Number(s.value)]));
    const followupDays = sMap["quote_followup_days"] ?? 7;

    const now = new Date();

    // Helper: date N days ago as ISO string
    const daysAgo = (n: number) => new Date(now.getTime() - n * 86400000).toISOString();

    const results = { followups: 0, errors: 0 };

    // ── EXPIRY: REMOVIDA em 26/09/2026 ─────────────────────────────────────────
    // Aqui ficava o laço que marcava quote_status = 'rejected' em todo orçamento com mais de
    // quote_expiry_days de criação (inclusive 'awaiting_deposit'). O vencimento agora é
    // AVISO: a R19 do task-automations cria a tarefa "Orçamento vencido: renovar ou
    // rejeitar?" e o dono decide. Decisão do dono de 26/09/2026.

    // ── FOLLOW-UP ──────────────────────────────────────────────────────────────
    // Quotes stuck in sent/awaiting_approval for > followup_days → queue reminder
    const { data: stuckQuotes, error: stuckErr } = await admin
      .from("service_orders")
      .select(`
        id, service_order_number, grand_total, share_token,
        clients(name, whatsapp, phone)
      `)
      .eq("status", "draft")
      .is("converted_to_os_at", null)
      .in("quote_status", ["sent", "awaiting_approval"])
      .lt("updated_at", daysAgo(followupDays));

    if (stuckErr) throw stuckErr;

    for (const q of stuckQuotes || []) {
      const client: any = q.clients;
      const phone = client?.whatsapp || client?.phone;
      if (!phone || !q.share_token) continue;

      const url     = `${SUPABASE_URL.replace("supabase.co", "supabase.co")}/view/${q.share_token}`;
      const message = `Olá${client?.name ? " " + client.name.split(" ")[0] : ""}! Passando para lembrar do orçamento *${q.service_order_number}* que enviamos. Ficou alguma dúvida ou podemos ajudar em algo? 😊\n${url}`;

      const { error: qErr } = await admin.from("whatsapp_send_queue").insert({
        service_order_id: q.id,
        phone,
        message,
        kind:    "text",
        context: "quote_followup",
        status:  "pending",
      });

      if (qErr) { results.errors++; console.error("queue insert failed", q.id, qErr); }
      else {
        results.followups++;
        // Advance quote_status so we don't send duplicate reminders today
        await admin
          .from("service_orders")
          .update({ quote_status: "awaiting_approval" } as any)
          .eq("id", q.id)
          .eq("quote_status" as any, "sent");
      }
    }

    console.log("quote-reminders done", results);
    return jr({ ok: true, ...results });

  } catch (err: any) {
    console.error("quote-reminders error", err);
    return jr({ error: err.message }, 500);
  }
});
