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

    const { data: cfgRows } = await admin
      .from("app_settings")
      .select("key, value")
      .in("key", ["company_name", "digest_show_low_stock"]);
    const cfg: Record<string, string> = {};
    for (const r of (cfgRows as any[]) || []) if (r?.key) cfg[String(r.key)] = String(r.value ?? "");
    const companyName = cfg["company_name"] || "MarineFlow";
    // "Estoque crítico" fica DESLIGADO por padrão: a operação é compra sob demanda (sem estoque),
    // então alerta de mínimo é ruído. Para religar quando houver estoque de fato, basta gravar
    // app_settings.digest_show_low_stock = 'true' — sem precisar de deploy.
    const showLowStock = cfg["digest_show_low_stock"] === "true";

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

    // Saúde de estoque: itens no/abaixo do mínimo. Só roda se digest_show_low_stock='true'
    // (ver acima) — a operação atual é compra sob demanda, sem estoque.
    const stockLines: string[] = [];
    if (showLowStock) {
      const { data: prodRows } = await admin
        .from("products")
        .select("name, stock_quantity, minimum_stock")
        .gt("minimum_stock", 0)
        .limit(300);
      const lowStock = ((prodRows as any[]) || []).filter((p: any) => Number(p.stock_quantity ?? 0) <= Number(p.minimum_stock ?? 0));
      if (lowStock.length > 0) {
        stockLines.push(`📦 Estoque crítico: *${lowStock.length}*`);
        for (const p of lowStock.slice(0, 3)) {
          stockLines.push(`   • ${p.name} · ${p.stock_quantity}/${p.minimum_stock}`);
        }
      }
    }

    // Manutenção preventiva (CRM proativo): ativos com serviço concluído há 12+ meses.
    // Num negócio náutico de serviço, cada um destes é um orçamento em potencial — e todo
    // orçamento novo cai no loop de cotação. Best-effort: nunca derruba o digest.
    const manutLines: string[] = [];
    const manutCandidatos: Array<{ ativo: string; cliente: string; meses: number }> = [];
    try {
      const { data: doneOs } = await admin
        .from("service_orders")
        .select("vessel_id, check_out_at, scheduled_end_at, updated_at")
        .in("status", ["completed", "invoiced"])
        .not("vessel_id", "is", null)
        .order("updated_at", { ascending: false })
        .limit(1000);
      const lastByVessel: Record<string, string> = {};
      for (const so of (doneOs as any[]) || []) {
        const when = so.check_out_at || so.scheduled_end_at || so.updated_at;
        if (!when) continue;
        const k = String(so.vessel_id);
        if (!lastByVessel[k] || new Date(when).getTime() > new Date(lastByVessel[k]).getTime()) lastByVessel[k] = when;
      }
      const vesselIds = Object.keys(lastByVessel);
      if (vesselIds.length > 0) {
        const { data: vs } = await admin
          .from("vessels")
          .select("id, name, clients(name)")
          .eq("active", true)
          .in("id", vesselIds)
          .limit(500);
        for (const v of (vs as any[]) || []) {
          const when = lastByVessel[String(v.id)];
          const m = Math.floor((now.getTime() - new Date(when).getTime()) / (30.44 * 86400000));
          if (m >= 12) {
            const nome = Array.isArray(v.clients) ? v.clients[0]?.name : v.clients?.name;
            manutCandidatos.push({ ativo: v.name, cliente: nome || "(sem cliente)", meses: m });
          }
        }
        manutCandidatos.sort((a, b) => b.meses - a.meses);
        if (manutCandidatos.length > 0) {
          manutLines.push(`🔧 Revisão vencida (12+ meses): *${manutCandidatos.length}*`);
          for (const c of manutCandidatos.slice(0, 3)) {
            manutLines.push(`   • ${c.ativo} — ${c.cliente} · ${c.meses} meses`);
          }
        }
      }
    } catch (_e) { /* não derruba o digest */ }

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

    // Sugestão do dia (Onda 1): 1 sugestão acionável, rotativa por dia — reusa os candidatos
    // já levantados (orçamentos parados, recebíveis vencidos, OS paradas). Uma por dia, sem spam.
    const sugestoes: string[] = [];
    for (const q of flaggedQuotes) {
      sugestoes.push(`dar um follow-up no orçamento de *${q.nome}* (${fmt.format(q.valor)}), parado há ${q.dias}d. Me peça que eu preparo.`);
    }
    for (const r of overdueSorted) {
      const nome = Array.isArray(r.clients) ? r.clients[0]?.name : r.clients?.name;
      const dias = r.due_date ? Math.floor((todayMid - new Date(`${r.due_date}T00:00:00`).getTime()) / 86400000) : 0;
      sugestoes.push(`cobrar *${nome || "um cliente"}* (${fmt.format(Number(r.balance_amount ?? r.amount ?? 0))}, vencido ${dias}d). Me peça que eu redijo a mensagem.`);
    }
    for (const o of ((stuckOs as any[]) || []).slice(0, 3)) {
      const nome = Array.isArray(o.clients) ? o.clients[0]?.name : o.clients?.name;
      const dias = Math.floor((now.getTime() - new Date(o.updated_at).getTime()) / 86400000);
      sugestoes.push(`retomar a *${o.service_order_number}*${nome ? ` (${nome})` : ""}, parada há ${dias}d.`);
    }
    for (const c of manutCandidatos.slice(0, 3)) {
      sugestoes.push(`oferecer revisão do *${c.ativo}* (${c.cliente}) — ${c.meses} meses sem serviço. Me peça que eu preparo o orçamento.`);
    }
    const diaDoAno = Math.floor((now.getTime() - new Date(now.getFullYear(), 0, 0).getTime()) / 86400000);
    const sugestaoLine = sugestoes.length > 0 ? `💡 *Sugestão de hoje:* ${sugestoes[diaDoAno % sugestoes.length]}` : "";

    // Ações rápidas (Bloco A' · Ciclo 2): o Evolution não tem botão nativo, então a versão
    // acionável no WhatsApp é um menu "tap-e-responde" — comandos concretos que o agente já
    // sabe executar. O dono só responde com um deles; envio a cliente ainda passa pelo card
    // de confirmação. Deriva dos mesmos candidatos do dia (não inventa trabalho).
    const quickActions: string[] = [];
    const topOverdue = overdueSorted[0] as any;
    if (topOverdue) {
      const nome = Array.isArray(topOverdue.clients) ? topOverdue.clients[0]?.name : topOverdue.clients?.name;
      if (nome) quickActions.push(`   • *Cobrar ${nome}*`);
    }
    if (flaggedQuotes[0]?.nome && flaggedQuotes[0].nome !== "(sem cliente)") {
      quickActions.push(`   • *Follow-up ${flaggedQuotes[0].nome}*`);
    }
    if (waiting.length > 0) quickActions.push(`   • *Quem está esperando resposta?*`);
    const quickActionLines = quickActions.length > 0
      ? ["", "⚡ *Ações rápidas* (responda com uma):", ...quickActions]
      : [];

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
      ...manutLines,
      ...stockLines,
      ...waitingLines,
      ...(sugestaoLine ? ["", sugestaoLine] : []),
      ...quickActionLines,
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
