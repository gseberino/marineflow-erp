// Edge Function: ai-business-monitor (Fase 5)
// Vigia sinais do negócio de hora em hora e avisa a EQUIPE (usuários com IA habilitada)
// por WhatsApp. Deduplicado por dia via ai_operator_alerts_log, então mesmo rodando de
// hora em hora, cada sinal alerta no máximo uma vez por dia.
//
// Sinais: (1) recebíveis que venceram HOJE; (2) orçamentos parados há 7+ dias; (3) certificado
// A1 vencendo; (4) cota fiscal do mês; (5) NF-e rejeitadas em 24h. Nenhum olha despesa,
// fornecedor ou extrato — o "Vigilante" do Executivo Financeiro (anomalias de despesa) NÃO é
// esta função e ainda não existe (plans/marineflow-executivo-financeiro.md, módulo IV).
// Destinatários são INTERNOS → envio pela fila (whatsapp_send_queue).
// *** ESTÁ NO AR: *** pg_cron `ai-business-monitor` de hora em hora, ATIVO (conferido no snapshot
// de produção em 14/09/2026 — supabase/schemas/producao/10-cron-e-storage.sql). O cabeçalho
// antigo dizia "DESATIVADO até validação" e estava errado desde a Fase 5.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import { createFiscalProvider } from "../_shared/fiscal/factory.ts";
import { verificarCronSecret } from "../_shared/cron-auth.ts";
import { ORIGEM_PADRAO, servirComCors } from "../_shared/cors.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": ORIGEM_PADRAO,
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-cron-secret",
  "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
};
function jr(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } });
}

servirComCors(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });
  // Era fail-OPEN (`if (cronSecret && ...)`): sem o env var, a função ficava aberta.
  const recusa = verificarCronSecret(req, corsHeaders, "ai-business-monitor");
  if (recusa) return recusa;

  try {
    const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

    const { data: cn } = await admin.from("app_settings").select("value").eq("key", "company_name").maybeSingle();
    const companyName = (cn?.value as string) || "MarineFlow";

    // Alerta de NEGÓCIO (orçamento parado, recebível vencido, cota da IA) é para quem decide:
    // admin e financeiro. Em 19/09/2026 dois técnicos recém-cadastrados no canal receberam
    // "orçamento parado há 7 dias" à meia-noite — o filtro por cargo não existia.
    const { data: recipients } = await admin
      .from("app_users").select("phone_normalized")
      .eq("ai_whatsapp_enabled", true).eq("active", true).not("phone_normalized", "is", null)
      .in("role", ["admin", "financial"]);
    if (!recipients || recipients.length === 0) return jr({ ok: true, sent: 0, reason: "no_recipients" });

    const now = new Date();
    const todayISO = now.toISOString().slice(0, 10);
    const fmt = new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL" });

    async function claim(alert_key: string, meta: any): Promise<boolean> {
      const { data } = await admin.from("ai_operator_alerts_log")
        .upsert({ alert_key, meta }, { onConflict: "alert_key", ignoreDuplicates: true }).select("id");
      return (data?.length ?? 0) > 0;
    }

    const alerts: string[] = [];

    // (1) Recebíveis vencidos HOJE
    const { data: dueToday } = await admin
      .from("receivables").select("balance_amount, amount")
      .in("status", ["pending", "partially_paid"]).eq("is_deposit", false).eq("due_date", todayISO);
    if ((dueToday?.length ?? 0) > 0 && await claim(`overdue_today:${todayISO}`, { n: dueToday!.length })) {
      const sum = dueToday!.reduce((a: number, r: any) => a + Number(r.balance_amount ?? r.amount ?? 0), 0);
      alerts.push(`💸 *${dueToday!.length}* recebível(is) vence(m) hoje — total ${fmt.format(sum)}. Vale acionar a cobrança.`);
    }

    // (2) Orçamentos parados há mais de 7 dias
    const d7 = new Date(now.getTime() - 7 * 864e5).toISOString();
    const { count: staleQuotes } = await admin
      .from("service_orders").select("id", { count: "exact", head: true })
      .eq("status", "draft").in("quote_status", ["sent", "awaiting_approval", "awaiting_deposit"])
      .lt("created_at", d7);
    if ((staleQuotes ?? 0) > 0 && await claim(`stale_quotes:${todayISO}`, { n: staleQuotes })) {
      alerts.push(`📄 *${staleQuotes}* orçamento(s) parado(s) há mais de 7 dias sem resposta. Talvez valha um follow-up.`);
    }

    // ── Sinais FISCAIS (NF-e) — reaproveitam o mesmo canal/dedup ──
    // (3) Certificado A1 vencendo (um A1 vencido trava TODA a emissão de NF-e).
    try {
      const provider = createFiscalProvider();
      const companies = await provider.listCompanies();
      const vu = companies.ok ? companies.data[0]?.certificateValidUntil : null;
      if (vu) {
        const days = Math.floor((new Date(`${vu}T23:59:59`).getTime() - now.getTime()) / 864e5);
        if (days <= 30 && await claim(`fiscal_cert_expiry:${todayISO}`, { days, vu })) {
          const urg = days <= 7 ? " *URGENTE*" : "";
          const quando = days < 0 ? "está VENCIDO" : `vence em ${days} dia(s)`;
          alerts.push(`🔐 Certificado A1${urg}: ${quando} (${vu}). Renove na Contora para não parar a emissão de NF-e.`);
        }
      }
    } catch (_e) {
      // Nunca deixa uma falha na Contora derrubar os demais sinais do monitor.
      console.warn("[ai-business-monitor] checagem de certificado falhou (ignorada)");
    }

    // (3b) Consentimento Open Finance vencendo (Pluggy: ~12 meses). Quando vence, o extrato
    // simplesmente para de chegar, sem erro — e o financeiro fica cego sem saber (Open Finance D2).
    try {
      const { data: conexoes } = await admin
        .from("bank_connections").select("id, consent_expires_at")
        .not("consent_expires_at", "is", null);
      for (const c of (conexoes ?? []) as { id: string; consent_expires_at: string }[]) {
        const dias = Math.floor((new Date(c.consent_expires_at).getTime() - now.getTime()) / 864e5);
        if (dias <= 30 && await claim(`consent_expiry:${c.id}:${todayISO}`, { dias })) {
          const quando = dias < 0 ? "VENCEU" : `vence em ${dias} dia(s)`;
          alerts.push(`🏦 Consentimento do extrato bancário ${quando} (${String(c.consent_expires_at).slice(0, 10)}). Renove a conexão no Pluggy antes que o extrato pare de chegar.`);
        }
      }
    } catch (_e) {
      console.warn("[ai-business-monitor] checagem de consentimento bancário falhou (ignorada)");
    }

    // (3c) Saldo do banco × soma das transações (Open Finance D4). A sincronização grava uma
    // conferência por conexão; se a mais recente não fecha por R$ 1 ou mais, alguém precisa
    // olhar o extrato — lançamento que não entrou não vira despesa nem receita em lugar nenhum.
    try {
      const { data: conexoes } = await admin.from("bank_connections").select("id, label").eq("active", true);
      for (const c of (conexoes ?? []) as { id: string; label: string }[]) {
        // Só avisa quando a diferença PERSISTE, igual, em duas conferências seguidas.
        //
        // O saldo do banco é do momento; as transações chegam com atraso de uma sincronização
        // (em 22/09 às 21:00 o saldo já tinha subido R$ 2.671 e as linhas só entraram na
        // rodada seguinte). Uma diferença que some na conferência seguinte é atraso, não
        // falta. Avisar na primeira gerou alerta falso — e, somado à conta com sinal
        // errado corrigida em 25/09/2026, quatro mensagens "pode faltar lançamento" sem
        // faltar nada. Verificador que grita sem motivo ensina a ignorar o aviso.
        const { data: duas } = await admin
          .from("bank_balance_checks").select("fecha, diferenca, saldo_do_provedor, saldo_calculado, conferido_em")
          .eq("bank_connection_id", c.id).order("conferido_em", { ascending: false }).limit(2);
        const [ult, anterior] = (duas ?? []) as Array<{ fecha: boolean; diferenca: number; saldo_do_provedor: number; saldo_calculado: number }>;
        if (!ult || !anterior) continue;
        if (ult.fecha || anterior.fecha || Math.abs(Number(ult.diferenca)) < 1) continue;
        if (Math.abs(Number(ult.diferenca) - Number(anterior.diferenca)) >= 1) continue;
        if (await claim(`saldo_divergente:${c.id}:${todayISO}`, { diferenca: ult.diferenca })) {
          const brl = (v: unknown) => Number(v).toLocaleString("pt-BR", { style: "currency", currency: "BRL" });
          alerts.push(`🏦 Extrato de ${c.label}: o saldo do banco (${brl(ult.saldo_do_provedor)}) não bate com a soma das transações importadas (${brl(ult.saldo_calculado)}), diferença ${brl(ult.diferenca)}. A diferença se repetiu nas duas últimas conferências: confira no app do banco se falta alguma transação no sistema (Financeiro › Fechamento).`);
        }
      }
    } catch (_e) {
      console.warn("[ai-business-monitor] checagem saldo × soma falhou (ignorada)");
    }

    // (3d) Estoque: saldo em tela ≠ soma dos movimentos (fase E do ledger). Depois do gatilho
    // de 20/09 isso só acontece quando algum caminho grava o saldo sem gravar movimento —
    // exatamente a porta que abriu o estoque fantasma. Aviso diário enquanto houver.
    try {
      const { data: div } = await admin.rpc("estoque_saldos_divergentes");
      const lista = (div ?? []) as Array<{ name: string; diferenca: number }>;
      if (lista.length > 0 && await claim(`estoque_divergente:${todayISO}`, { n: lista.length })) {
        const ex = lista.slice(0, 3).map((d) => `${d.name} (${Number(d.diferenca) > 0 ? "+" : ""}${Number(d.diferenca)})`).join(", ");
        alerts.push(`📦 ${lista.length} produto(s) com saldo diferente da soma dos movimentos: ${ex}${lista.length > 3 ? "…" : ""}. Algum caminho gravou estoque sem registrar movimento; confira em Estoque › Variância.`);
      }
    } catch (_e) {
      console.warn("[ai-business-monitor] checagem de saldo de estoque falhou (ignorada)");
    }

    // (4) Cota Contora do mês (plano Gratuito = 500 eventos/mês). Alerta em 80%.
    const monthStart = new Date(now.getFullYear(), now.getMonth(), 1).toISOString();
    const { count: fiscalEvents } = await admin
      .from("issued_fiscal_documents").select("id", { count: "exact", head: true })
      .in("status", ["authorized", "rejected", "cancelled"]).gte("created_at", monthStart);
    if ((fiscalEvents ?? 0) > 400 && await claim(`fiscal_quota_high:${todayISO}`, { n: fiscalEvents })) {
      alerts.push(`📊 Cota fiscal do mês: ~*${fiscalEvents}*/500 eventos usados. Fique de olho para não estourar o plano.`);
    }

    // (5) NF-e rejeitadas nas últimas 24h (não deixar uma rejeição passar batida).
    const d1 = new Date(now.getTime() - 864e5).toISOString();
    const { count: rejectedNfe } = await admin
      .from("issued_fiscal_documents").select("id", { count: "exact", head: true })
      .eq("status", "rejected").gte("updated_at", d1);
    if ((rejectedNfe ?? 0) > 0 && await claim(`fiscal_rejected:${todayISO}`, { n: rejectedNfe })) {
      alerts.push(`❌ *${rejectedNfe}* NF-e rejeitada(s) nas últimas 24h. Confira o motivo no histórico e reemita.`);
    }

    if (alerts.length === 0) return jr({ ok: true, queued: 0, note: "sem sinais novos hoje" });

    const message = [`🔔 *Alerta ${companyName}*`, "", ...alerts, "", "_Me chame aqui se quiser que eu ajude com qualquer um desses._"].join("\n");
    const rows = recipients.map((r: any) => ({ phone_normalized: String(r.phone_normalized), message, source: "ai_monitor", priority: 5 }));
    const { data: inserted, error: qErr } = await admin.from("whatsapp_send_queue").insert(rows).select("id");
    if (qErr) throw qErr;

    return jr({ ok: true, queued: inserted?.length ?? 0, signals: alerts.length });
  } catch (e: any) {
    console.error("[ai-business-monitor] fatal", e);
    return jr({ error: e?.message || "internal error" }, 500);
  }
});
