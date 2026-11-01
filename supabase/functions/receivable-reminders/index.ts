// Edge Function: receivable-reminders
// Runs daily via pg_cron at 11:00 UTC (08:00 BRT).
// Sends WhatsApp reminders for receivables due in 3 days that haven't received a reminder yet.
// Só em dia útil (agenda_dia_util: sem domingo e feriado); o dia útil seguinte lembra também os
// vencimentos que cairiam nos dias pulados. Envia pelo whatsapp-send, como envio automático
// (Retorno F0a-1, 05/11/2026: ver enviar.ts).

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import { verificarCronSecret } from "../_shared/cron-auth.ts";
import { chaveDeEnvio, diaLocal } from "../_shared/whatsapp/idempotencia.ts";
import {
  descricaoDaCobranca,
  diasEntre,
  enviarLembrete,
  somarDias,
  textoDoPrazo,
  vencimentosDoDia,
} from "./enviar.ts";
import { ORIGEM_PADRAO, servirComCors } from "../_shared/cors.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": ORIGEM_PADRAO,
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-cron-secret",
  "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
};

function jr(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

servirComCors(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });

  // Era fail-OPEN (`if (cronSecret) { ... }`): sem o env var, a função ficava aberta.
  const recusa = verificarCronSecret(req, corsHeaders, "receivable-reminders");
  if (recusa) return recusa;

  try {
    const SUPABASE_URL  = Deno.env.get("SUPABASE_URL")!;
    const SERVICE_ROLE  = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const admin         = createClient(SUPABASE_URL, SERVICE_ROLE);

    // Carrega configurações operacionais (modo de teste)
    const { data: settings } = await admin
      .from("app_settings")
      .select("key, value")
      .in("key", ["wa_test_mode", "wa_test_number", "zapi_test_mode", "zapi_test_number",
                   "receivable_reminder_days_before", "company_name", "collection_min_amount"]);
    const settingsMap = Object.fromEntries((settings || []).map((s: any) => [s.key, s.value]));
    // D21 (dono, 17/09/2026): abaixo do piso de materialidade não se manda lembrete.
    const pisoCobranca = Number(settingsMap["collection_min_amount"]) || 0;

    const testMode   = (settingsMap["wa_test_mode"] ?? settingsMap["zapi_test_mode"]) === "true";
    const testNumber = ((settingsMap["wa_test_number"] ?? settingsMap["zapi_test_number"]) || "").replace(/\D/g, "");
    const companyName = settingsMap["company_name"] || "MarineFlow";

    // Modo de teste ativo sem número → aborta para não vazar dados
    if (testMode && !testNumber) {
      console.warn("[receivable-reminders] TEST MODE ativo mas sem número de redirecionamento. Abortando.");
      return jr({ ok: false, skipped: 0, reason: "test_mode_no_number" });
    }

    // Dia útil pela agenda. Sem resposta do banco, não envia (falha fechada).
    const hoje = diaLocal();
    const ehDiaUtil = async (dia: string): Promise<boolean> => {
      const { data, error } = await admin.rpc("agenda_dia_util", { p_dia: dia });
      if (error) throw new Error(`agenda_dia_util(${dia}): ${error.message}`);
      return data === true;
    };
    if (!(await ehDiaUtil(hoje))) {
      console.log(`[receivable-reminders] ${hoje} não é dia útil: nenhum lembrete hoje.`);
      return jr({ ok: true, sent: 0, skipped: 0, errors: 0, dia_util: false, hoje });
    }
    // O último dia útil antes de hoje. Duas semanas sem nenhum é dado errado: não envia, em vez
    // de lembrar de uma vez 15 dias de vencimentos.
    let ultimoDiaUtil = somarDias(hoje, -1);
    let voltas = 0;
    while (!(await ehDiaUtil(ultimoDiaUtil))) {
      if (++voltas > 14) throw new Error(`nenhum dia útil nas duas semanas antes de ${hoje}`);
      ultimoDiaUtil = somarDias(ultimoDiaUtil, -1);
    }

    const daysBefore = parseInt(settingsMap["receivable_reminder_days_before"] || "3", 10);
    const { de, ate } = vencimentosDoDia(hoje, ultimoDiaUtil, daysBefore);

    // Recebíveis que vencem nesse intervalo e ainda não receberam lembrete
    const { data: receivables, error } = await admin
      .from("receivables")
      .select(`
        id, amount, balance_amount, due_date, description, service_order_id,
        clients!receivables_client_id_fkey(name, whatsapp, phone),
        service_orders!receivables_service_order_id_fkey(service_order_number)
      `)
      .in("status", ["pending", "partially_paid"])
      .gte("due_date", de)
      .lte("due_date", ate)
      .is("reminder_sent_at", null)
      .is("is_deposit", false); // Não enviar lembrete para sinais/depósitos

    if (error) throw error;

    const fmt = new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL" });
    // O whatsapp-send desvia para o número de teste sozinho (numeroDeTesteAtivo).
    const chamarEnvio = async (corpo: Record<string, unknown>) => {
      const res = await fetch(`${SUPABASE_URL}/functions/v1/whatsapp-send`, {
        method: "POST",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${SERVICE_ROLE}` },
        body: JSON.stringify(corpo),
      });
      return { status: res.status, corpo: await res.json().catch(() => ({})) };
    };

    let sent = 0, skipped = 0, errors = 0;

    for (const rec of receivables || []) {
      const client: any = rec.clients;
      const originalPhone = (client?.whatsapp || client?.phone || "").replace(/\D/g, "");

      if (!originalPhone || originalPhone.length < 10) {
        skipped++;
        console.log(`[receivable-reminders] skipped ${rec.id} — sem telefone`);
        continue;
      }

      const dueDate  = new Date(rec.due_date + "T12:00:00");
      const dueDateBR = dueDate.toLocaleDateString("pt-BR");
      const clientFirstName = (client?.name || "").split(" ")[0] || "Cliente";
      const soNumber = (rec as any).service_orders?.service_order_number || "";
      const description = descricaoDaCobranca(rec.description, soNumber);
      const balanceValue = Number(rec.balance_amount || rec.amount);
      if (pisoCobranca > 0 && balanceValue < pisoCobranca) {
        console.info(`[receivable-reminders] ${rec.id}: R$ ${balanceValue} abaixo do piso de R$ ${pisoCobranca}, sem lembrete.`);
        continue;
      }

      const message =
        `Olá ${clientFirstName}! 👋 Lembramos que o pagamento de *${fmt.format(balanceValue)}* ` +
        `referente a *${description}* ${textoDoPrazo(diasEntre(hoje, rec.due_date))} ` +
        `(*${dueDateBR}*). Em caso de dúvidas, entre em contato. — *${companyName}*`;

      if (testMode) {
        console.log(`[receivable-reminders] TEST MODE: enviando para ${testNumber} (original: ${originalPhone})`);
      }

      // A mesma chave de antes (o vencimento é o dia-alvo): o que já saiu não sai de novo.
      const chave = chaveDeEnvio("lembrete-recebivel", rec.id, rec.due_date);
      const envio = await enviarLembrete({
        admin, chamarEnvio, chave, phone: originalPhone, message, recebivelId: rec.id, ordemId: rec.service_order_id,
      });
      if (envio.situacao === "enviado") {
        sent++;
      } else if (envio.situacao === "erro") {
        errors++;
        console.error(`[receivable-reminders] erro no envio ${rec.id}:`, envio.erro);
      } else {
        skipped++;
        console.info(`[receivable-reminders] ${rec.id}: ${envio.situacao === "recusado" ? envio.motivo : "já tinha saído"}`);
      }
    }

    console.log(`[receivable-reminders] done — sent:${sent} skipped:${skipped} errors:${errors}`);
    return jr({ ok: true, sent, skipped, errors, due_from: de, due_to: ate });

  } catch (err: any) {
    console.error("[receivable-reminders] fatal error", err);
    return jr({ error: err.message }, 500);
  }
});
