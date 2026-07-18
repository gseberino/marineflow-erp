// Edge Function: ai-daily-briefing (Fase 5)
// Envia um resumo matinal por WhatsApp para os usuários com o canal de IA habilitado
// (app_users.ai_whatsapp_enabled = true). Determinístico: junta os números-chave do dia
// (recebíveis vencidos, orçamentos aguardando, agendamentos de hoje, aprovações pendentes)
// e enfileira a mensagem em whatsapp_send_queue (o whatsapp-queue-worker entrega).
//
// Destinatários são INTERNOS (a própria equipe), então o envio direto pela fila é adequado.
// Agendado via pg_cron (jobid 6, ai-daily-briefing, 10:30 UTC = 07:30 BRT) — ATIVO.
// Inclui a seção "Esperando resposta" (Fase 1 do piloto): mensagens sem resposta via RPC
// whatsapp_pending_inbox. Use ?dry=1 para pré-visualizar a mensagem sem enfileirar/enviar.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-cron-secret",
  "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
};

function jr(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

// "Identificar e encaminhar" (mídia): sem gastar token/vision, sinaliza o tipo do último
// conteúdo recebido para o humano saber que há um áudio/imagem/arquivo para abrir.
function mediaHint(body?: string | null): string {
  const b = (body || "").trim();
  switch (b) {
    case "[audio]": return " · 🎤 áudio (ouça)";
    case "[image]": return " · 📷 imagem (veja)";
    case "[video]": return " · 🎬 vídeo";
    case "[document]": return " · 📎 arquivo";
  }
  // Áudio já transcrito ("🎤 <texto>") → mostra um trecho no digest.
  if (b.startsWith("🎤 ")) {
    const snip = b.slice(2).trim();
    return ` · 🎤 "${snip.slice(0, 40)}${snip.length > 40 ? "…" : ""}"`;
  }
  return "";
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });

  const cronSecret = Deno.env.get("CRON_SECRET");
  if (cronSecret) {
    const incoming = req.headers.get("x-cron-secret");
    if (incoming !== cronSecret) return jr({ error: "Unauthorized" }, 401);
  }

  try {
    const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

    const { data: cn } = await admin.from("app_settings").select("value").eq("key", "company_name").maybeSingle();
    const companyName = (cn?.value as string) || "MarineFlow";

    // Destinatários: quem usa a IA (canal habilitado) e está ativo, com número.
    const { data: recipients } = await admin
      .from("app_users")
      .select("full_name, phone_normalized")
      .eq("ai_whatsapp_enabled", true)
      .eq("active", true)
      .not("phone_normalized", "is", null);

    if (!recipients || recipients.length === 0) return jr({ ok: true, sent: 0, reason: "no_recipients" });

    const now = new Date();
    const todayISO = now.toISOString().slice(0, 10);
    const dayStart = `${todayISO}T00:00:00`;
    const tomorrow = new Date(now.getTime() + 86400000).toISOString().slice(0, 10);
    const dayEnd = `${tomorrow}T00:00:00`;

    // ── Métricas do dia ──
    const { data: overdueRows } = await admin
      .from("receivables")
      .select("balance_amount, amount, due_date, clients(name)")
      .in("status", ["pending", "partially_paid"])
      .eq("is_deposit", false)
      .lt("due_date", todayISO);
    const overdueCount = overdueRows?.length ?? 0;
    const overdueSum = (overdueRows || []).reduce((a: number, r: any) => a + Number(r.balance_amount ?? r.amount ?? 0), 0);

    // Saúde do negócio (Frente 2): recebíveis A VENCER nos próximos 3 dias — heads-up do
    // caixa que entra, complementando os vencidos (visão de fluxo pra frente).
    const in3days = new Date(now.getTime() + 3 * 86400000).toISOString().slice(0, 10);
    const { data: upcomingRows } = await admin
      .from("receivables")
      .select("balance_amount, amount")
      .in("status", ["pending", "partially_paid"])
      .eq("is_deposit", false)
      .gte("due_date", todayISO)
      .lte("due_date", in3days);
    const upcomingCount = upcomingRows?.length ?? 0;
    const upcomingSum = (upcomingRows || []).reduce((a: number, r: any) => a + Number(r.balance_amount ?? r.amount ?? 0), 0);

    // Saúde operacional: OS ATIVA parada (trabalho em andamento sem movimento há +10 dias).
    const stuckCut = new Date(now.getTime() - 10 * 86400000).toISOString();
    const { data: stuckOs } = await admin
      .from("service_orders")
      .select("service_order_number, updated_at, clients(name)")
      .in("status", ["approved", "in_progress", "open", "scheduled", "awaiting_parts"])
      .lt("updated_at", stuckCut)
      .order("updated_at", { ascending: true })
      .limit(10);
    const stuckLines: string[] = [];
    if (stuckOs && stuckOs.length > 0) {
      stuckLines.push(`🔧 OS paradas (+10 dias): *${stuckOs.length}*`);
      for (const o of (stuckOs as any[]).slice(0, 3)) {
        const nome = Array.isArray(o.clients) ? o.clients[0]?.name : o.clients?.name;
        const dias = Math.floor((now.getTime() - new Date(o.updated_at).getTime()) / 86400000);
        stuckLines.push(`   • ${o.service_order_number}${nome ? ` — ${nome}` : ""} · parada ${dias}d`);
      }
    }

    // Saúde de estoque: itens no/abaixo do mínimo (comparação coluna-a-coluna feita em memória).
    const { data: prodRows } = await admin
      .from("products")
      .select("name, stock_quantity, minimum_stock")
      .gt("minimum_stock", 0)
      .limit(300);
    const lowStock = ((prodRows as any[]) || []).filter((p: any) => Number(p.stock_quantity ?? 0) <= Number(p.minimum_stock ?? 0));
    const stockLines: string[] = [];
    if (lowStock.length > 0) {
      stockLines.push(`📦 Estoque crítico: *${lowStock.length}*`);
      for (const p of lowStock.slice(0, 3)) {
        stockLines.push(`   • ${p.name} · ${p.stock_quantity}/${p.minimum_stock}`);
      }
    }

    const { count: quotesCount } = await admin
      .from("service_orders")
      .select("id", { count: "exact", head: true })
      .eq("status", "draft")
      .in("quote_status", ["sent", "awaiting_approval", "awaiting_deposit"]);

    const { count: scheduledCount } = await admin
      .from("service_orders")
      .select("id", { count: "exact", head: true })
      .gte("scheduled_start_at", dayStart)
      .lt("scheduled_start_at", dayEnd);

    const { count: pendingCount } = await admin
      .from("ai_operator_pending_actions")
      .select("id", { count: "exact", head: true })
      .eq("status", "pending");

    // ── Mensagens esperando resposta (Fase 1 · fatia Mensagens) ──
    // Fonte da verdade via RPC whatsapp_pending_inbox: já exclui listas de transmissão e a
    // equipe interna. Janela recente (7 dias) para manter o digest quieto e acionável;
    // a consulta sob demanda ("quem me mandou?") continua mostrando tudo. Clientes primeiro.
    const since7d = new Date(now.getTime() - 7 * 86400000).toISOString();
    const { data: waitingRows } = await admin.rpc("whatsapp_pending_inbox", { _since: since7d, _limit: 12 });
    const waiting = ((waitingRows as any[]) || []).slice();
    waiting.sort((a: any, b: any) => Number(b.is_client) - Number(a.is_client)); // sort estável preserva recência
    const topWaiting = waiting.slice(0, 6);
    const waitingLines: string[] = [];
    if (waiting.length > 0) {
      waitingLines.push(`💬 Esperando resposta: *${waiting.length}*`);
      for (const w of topWaiting) {
        const mins = Math.max(0, Math.round((now.getTime() - new Date(w.last_inbound_at as string).getTime()) / 60000));
        const ha = mins < 60 ? `${mins} min` : mins < 1440 ? `${Math.round(mins / 60)} h` : `${Math.round(mins / 1440)} d`;
        waitingLines.push(`   • ${w.contato}${w.is_client ? " (cliente)" : ""} — há ${ha}${mediaHint(w.last_body)}`);
      }
      if (waiting.length > topWaiting.length) waitingLines.push(`   …e mais ${waiting.length - topWaiting.length}`);
    } else {
      waitingLines.push(`💬 Esperando resposta: *0* ✅`);
    }

    const fmt = new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL" });
    const dateBR = now.toLocaleDateString("pt-BR", { weekday: "long", day: "2-digit", month: "long" });

    // ── Orçamentos parados / expirando (Fase 2 do piloto) ──
    // Só lista os que pedem ação: parados há ≥2 dias OU perto de expirar / expirados.
    // Orçamento recém-mexido não polui o digest. Ordena pelos mais parados primeiro.
    const { data: openQuotes } = await admin
      .from("service_orders")
      .select("service_order_number, grand_total, updated_at, quote_validity_date, clients(name)")
      .eq("status", "draft")
      .in("quote_status", ["sent", "awaiting_approval", "awaiting_deposit"])
      .order("updated_at", { ascending: true })
      .limit(20);
    const todayMid = new Date(`${todayISO}T00:00:00`).getTime();
    const quoteLines: string[] = [];
    const flaggedQuotes = ((openQuotes as any[]) || [])
      .map((q: any) => {
        const dias = Math.floor((now.getTime() - new Date(q.updated_at).getTime()) / 86400000);
        const vd = q.quote_validity_date ? new Date(`${q.quote_validity_date}T00:00:00`).getTime() : null;
        const expired = vd !== null && vd < todayMid;
        const expiringSoon = vd !== null && !expired && vd <= todayMid + 3 * 86400000;
        const nome = Array.isArray(q.clients) ? q.clients[0]?.name : q.clients?.name;
        return { nome: nome || "(sem cliente)", valor: Number(q.grand_total || 0), dias, expired, expiringSoon };
      })
      .filter((q: any) => q.dias >= 2 || q.expired || q.expiringSoon)
      .slice(0, 5);
    if (flaggedQuotes.length > 0) {
      for (const q of flaggedQuotes) {
        const tag = q.expired ? " · ⚠️ expirado" : q.expiringSoon ? " · ⏳ expira em breve" : "";
        quoteLines.push(`   • ${q.nome} — ${fmt.format(q.valor)} · parado ${q.dias}d${tag}`);
      }
    }

    // ── Recebíveis vencidos priorizados por VALOR (impacto de caixa) — top 4 (Fase 2) ──
    // Não trata todo vencido igual: os maiores primeiro (prática de AR 2026).
    const recebLines: string[] = [];
    const overdueSorted = ((overdueRows as any[]) || [])
      .slice()
      .sort((a: any, b: any) => Number(b.balance_amount ?? b.amount ?? 0) - Number(a.balance_amount ?? a.amount ?? 0))
      .slice(0, 4);
    for (const r of overdueSorted) {
      const nome = Array.isArray(r.clients) ? r.clients[0]?.name : r.clients?.name;
      const dias = r.due_date ? Math.floor((todayMid - new Date(`${r.due_date}T00:00:00`).getTime()) / 86400000) : 0;
      recebLines.push(`   • ${nome || "(sem cliente)"} — ${fmt.format(Number(r.balance_amount ?? r.amount ?? 0))} · vencido ${dias}d`);
    }

    const linhas = [
      `☀️ *Bom dia! Resumo de ${dateBR}*`,
      "",
      `📅 Agendamentos hoje: *${scheduledCount ?? 0}*`,
      `📄 Orçamentos aguardando resposta: *${quotesCount ?? 0}*`,
      ...quoteLines,
      `💸 Recebíveis vencidos: *${overdueCount}*${overdueCount > 0 ? ` (${fmt.format(overdueSum)})` : ""}`,
      ...recebLines,
      ...(upcomingCount > 0 ? [`🔜 A vencer (próx. 3 dias): *${upcomingCount}* (${fmt.format(upcomingSum)})`] : []),
      `✅ Aprovações da IA pendentes: *${pendingCount ?? 0}*`,
      ...stuckLines,
      ...stockLines,
      ...waitingLines,
      "",
      `_Enviado pelo assistente de ${companyName}. Responda por aqui para pedir qualquer coisa._`,
    ];
    const message = linhas.join("\n");

    // Dry-run (?dry=1): monta a mensagem mas NÃO enfileira — para pré-visualizar com segurança.
    if (new URL(req.url).searchParams.get("dry") === "1") {
      return jr({ ok: true, dry: true, recipients: recipients.length, preview: message });
    }

    // Enfileira uma mensagem por destinatário. O whatsapp-queue-worker (cron de 1min) entrega.
    const rows = recipients.map((rec: any) => ({
      phone_normalized: String(rec.phone_normalized),
      message,
      source: "ai_briefing",
      priority: 4,
    }));
    const { data: inserted, error: qErr } = await admin.from("whatsapp_send_queue").insert(rows).select("id");
    if (qErr) throw qErr;

    return jr({
      ok: true,
      queued: inserted?.length ?? 0,
      metrics: { scheduled: scheduledCount ?? 0, quotes: quotesCount ?? 0, overdue: overdueCount, overdue_sum: overdueSum, pending: pendingCount ?? 0 },
    });
  } catch (e: any) {
    console.error("[ai-daily-briefing] fatal", e);
    return jr({ error: e?.message || "internal error" }, 500);
  }
});
