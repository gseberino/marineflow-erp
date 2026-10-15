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
import { verificarCronSecret } from "../_shared/cron-auth.ts";
import { ORIGEM_PADRAO, servirComCors } from "../_shared/cors.ts";
import { ultimoDiaDaValidade } from "../_shared/pdf/documento.ts";
import { diaBR, somarDiasAoDia } from "../_shared/pdf/datas.ts";
import { historicoSemIdentidade } from "../_shared/banking/proposals.ts";
import { normalizeText } from "../_shared/banking/matching.ts";
import { linhasDoExtratoNoResumo } from "./extrato.ts";
import { canceladasSemComprovante, debitosSemComprovante, linhasDosComprovantes } from "./comprovantes.ts";
import { lerAnalise } from "../_shared/financeiro/vigia-do-negocio.ts";
import { chaveDoAviso, montarSecaoEmail, type EmailDigestItem } from "../_shared/email/digest.ts";
import { resumoDosDados } from "../_shared/email/dados.ts";
import { embarcacoesComPlano, secaoDeRevisoes, type PlanoDoResumo, type SecaoDeRevisoes } from "./revisoes.ts";
import { linhasDasEntradas, separarEntradas, type EntradaDoBanco, type EntradasSeparadas, type PagamentoSemExtrato } from "./entradas.ts";
import { despesasPendentesDoMes, faturamentoPorCliente, notaDoMes } from "./mes.ts";
import { linhaDasPropostas, linhaDoOrcamento, linhaSeHouver, nomeDeContato, tentativasAte } from "./linhas.ts";
import { linhasDoHistorico } from "./historico.ts";
import { conversaEncerradaPeloContato } from "../_shared/whatsapp/contato-encerrou.ts";
import { resolveOrCreateWhatsAppSession } from "../_shared/ai/whatsapp-channel.ts";

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

servirComCors(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });

  // Era fail-OPEN (`if (cronSecret) { ... }`): sem o env var, a função ficava aberta.
  const recusa = verificarCronSecret(req, corsHeaders, "ai-daily-briefing");
  if (recusa) return recusa;

  try {
    const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

    const { data: cfgRows } = await admin
      .from("app_settings")
      .select("key, value")
      .in("key", ["company_name", "digest_show_low_stock", "quote_validity_days"]);
    const cfg: Record<string, string> = {};
    for (const r of (cfgRows as any[]) || []) if (r?.key) cfg[String(r.key)] = String(r.value ?? "");
    const companyName = cfg["company_name"] || "MarineFlow";
    // "Estoque crítico" fica DESLIGADO por padrão: a operação é compra sob demanda (sem estoque),
    // então alerta de mínimo é ruído. Para religar quando houver estoque de fato, basta gravar
    // app_settings.digest_show_low_stock = 'true' — sem precisar de deploy.
    const showLowStock = cfg["digest_show_low_stock"] === "true";

    // Destinatários: quem DECIDE (admin/financeiro), com canal habilitado, ativo e com número.
    // O resumo traz caixa, propostas, fila de aprovações e clientes — técnico não recebe
    // (19/09/2026: filtro por cargo adicionado depois de dois técnicos entrarem no canal).
    const { data: recipients } = await admin
      .from("app_users")
      .select("id, full_name, phone_normalized")
      .eq("ai_whatsapp_enabled", true)
      .eq("active", true)
      .not("phone_normalized", "is", null)
      .in("role", ["admin", "financial"]);

    if (!recipients || recipients.length === 0) return jr({ ok: true, sent: 0, reason: "no_recipients" });

    const now = new Date();
    // O dia de Brasília: a edge roda em UTC, e depois das 21h o dia UTC já é o seguinte. Até
    // 15/10/2026 os agendamentos de "hoje" iam de 00:00 a 00:00 sem fuso (o banco lia como UTC:
    // das 21h de ontem às 21h de hoje em Brasília). Brasília não tem horário de verão desde 2019.
    const hojeBR = diaBR(now);
    const todayISO = hojeBR;
    const dayStart = new Date(`${hojeBR}T00:00:00-03:00`).toISOString();
    const dayEnd = new Date(new Date(dayStart).getTime() + 86400000).toISOString();
    const fmt = new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL" });

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

    // ── Revisões: planos de manutenção com lembretes (07/10/2026) ──
    // Planos primeiro (view v_maintenance_plans_due): vencendo em 30 dias, vencidas, quem respondeu
    // ao lembrete nas últimas 24h e lembretes esperando o "sim" do dono. Até regerar os tipos
    // (07/10/2026) a view e a tabela de eventos vão por nome. Falha de leitura vira linha de aviso,
    // não silêncio — e a heurística abaixo segue valendo para tudo, como antes.
    let revisoes: SecaoDeRevisoes = { linhas: [], sugestao: null, acao: null };
    let comPlano = new Set<string>();
    try {
      const { data: planosDue, error: pErr } = await admin
        .from("v_maintenance_plans_due")
        .select("plan_id, vessel_id, vessel_name, client_name, name, estimated_value, next_due_on, dias_para_vencer, situacao")
        .limit(1000);
      if (pErr) throw pErr;
      const desde24h = new Date(now.getTime() - 24 * 3600000).toISOString();
      const { data: respostas, error: rErr } = await admin
        .from("maintenance_plan_events")
        .select("plan_id, detalhe")
        .eq("tipo", "client_replied")
        .gte("created_at", desde24h)
        .limit(50);
      if (rErr) throw rErr;
      const { count: aguardandoSim, error: aErr } = await admin
        .from("ai_operator_pending_actions")
        .select("id", { count: "exact", head: true })
        .eq("status", "pending")
        .eq("action_name", "enviar_lembrete_de_revisao");
      if (aErr) throw aErr;
      const planosLidos = ((planosDue as any[]) || []) as PlanoDoResumo[];
      comPlano = embarcacoesComPlano(planosLidos);
      const fmtRev = new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL" });
      revisoes = secaoDeRevisoes(
        planosLidos,
        ((respostas as any[]) || []).map((r) => ({ plan_id: String(r.plan_id), texto: r.detalhe?.texto ?? null })),
        aguardandoSim ?? 0,
        (v) => fmtRev.format(v),
        diaBR(now),
      );
    } catch (e) {
      console.warn("[ai-daily-briefing] revisões falharam:", (e as Error).message);
      revisoes = { linhas: ["", "🛠️ Revisões: não deu para ler os planos de manutenção agora."], sugestao: null, acao: null };
    }

    // Manutenção preventiva (CRM proativo): ativos com serviço concluído há 12+ meses.
    // Num negócio náutico de serviço, cada um destes é um orçamento em potencial — e todo
    // orçamento novo cai no loop de cotação. Best-effort: nunca derruba o digest.
    // 07/10/2026: só para embarcações SEM plano — as com plano estão na seção Revisões acima.
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
        if (comPlano.has(k)) continue;
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
          manutLines.push(`🔧 Sem plano, último serviço há 12+ meses: *${manutCandidatos.length}*`);
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
    // 06/10/2026: whatsapp_esperando_resposta separa cliente (inclusive pelo telefone do cadastro),
    // fornecedor e outros contatos, e marca as que terminaram num "ok/obrigado" — essas só contam.
    // Janela de 7 dias para o resumo ficar quieto e acionável; "quem me mandou?" continua mostrando tudo.
    const since7d = new Date(now.getTime() - 7 * 86400000).toISOString();
    const { data: waitingRows } = await admin.rpc("whatsapp_esperando_resposta", { _since: since7d, _limit: 60 });
    const todasEsperando = ((waitingRows as any[]) || []);
    const encerradas = todasEsperando.filter((w: any) => w.encerrada);
    let waiting = todasEsperando.filter((w: any) => !w.encerrada);
    // Quem disse que fechou com outra empresa ou desistiu (15/10/2026, regra de palavras sem IA, em
    // _shared/whatsapp/contato-encerrou.ts) sai da lista: a RPC só olha a ÚLTIMA mensagem, e o "Sim,
    // já fechei" do Miguel (07/10) sozinho é ambíguo — a regra olha as 5 últimas recebidas em 7 dias.
    // Erro na leitura = a lista como antes (nada some por engano).
    let desistiram = 0;
    try {
      const fones = waiting.map((w: any) => String(w.phone ?? "")).filter(Boolean);
      if (fones.length > 0) {
        const { data: recebidas, error: rErr } = await admin.from("whatsapp_messages")
          .select("phone_normalized, body, occurred_at")
          .eq("direction", "inbound").in("phone_normalized", fones).gte("occurred_at", since7d)
          .order("occurred_at", { ascending: false }).limit(1000);
        if (rErr) throw rErr;
        const porFone = new Map<string, string[]>();
        for (const m of (recebidas as any[]) || []) {
          const l = porFone.get(m.phone_normalized) ?? [];
          l.push(m.body);
          porFone.set(m.phone_normalized, l);
        }
        const antes = waiting.length;
        waiting = waiting.filter((w: any) => !conversaEncerradaPeloContato(porFone.get(String(w.phone)) ?? []));
        desistiram = antes - waiting.length;
      }
    } catch (e) {
      console.warn("[ai-daily-briefing] leitura de quem desistiu falhou:", (e as Error).message);
    }
    const porCategoria = (c: string) => waiting.filter((w: any) => w.categoria === c);
    const clientesEsperando = porCategoria("cliente");
    const fornecedoresEsperando = porCategoria("fornecedor");
    const outrosEsperando = porCategoria("contato");
    const haQuanto = (iso: string) => {
      const mins = Math.max(0, Math.round((now.getTime() - new Date(iso).getTime()) / 60000));
      return mins < 60 ? `${mins} min` : mins < 1440 ? `${Math.round(mins / 60)} h` : `${Math.round(mins / 1440)} d`;
    };
    const waitingLines: string[] = [];
    if (waiting.length > 0) {
      const partes = [
        clientesEsperando.length ? `${clientesEsperando.length} cliente(s)` : "",
        outrosEsperando.length ? `${outrosEsperando.length} outro(s)` : "",
        fornecedoresEsperando.length ? `${fornecedoresEsperando.length} fornecedor(es)` : "",
      ].filter(Boolean).join(" · ");
      waitingLines.push(`💬 Esperando resposta: *${waiting.length}* (${partes})`);
      for (const w of clientesEsperando.slice(0, 5)) {
        waitingLines.push(`   • *${nomeDeContato(w.contato)}* (cliente) — há ${haQuanto(w.last_inbound_at)}${mediaHint(w.last_body)}`);
      }
      for (const w of outrosEsperando.slice(0, Math.max(0, 6 - Math.min(5, clientesEsperando.length)))) {
        waitingLines.push(`   • ${nomeDeContato(w.contato)} — há ${haQuanto(w.last_inbound_at)}${mediaHint(w.last_body)}`);
      }
      const mostrados = Math.min(5, clientesEsperando.length) + Math.min(Math.max(0, 6 - Math.min(5, clientesEsperando.length)), outrosEsperando.length);
      const resto = clientesEsperando.length + outrosEsperando.length - mostrados;
      if (resto > 0) waitingLines.push(`   …e mais ${resto}`);
      if (fornecedoresEsperando.length) waitingLines.push(`   🏭 Fornecedores: ${fornecedoresEsperando.map((w: any) => nomeDeContato(w.contato)).slice(0, 4).join(", ")}${fornecedoresEsperando.length > 4 ? "…" : ""}`);
    } else {
      waitingLines.push(`💬 Esperando resposta: *0* ✅`);
    }
    if (encerradas.length) waitingLines.push(`   (+${encerradas.length} só disseram "ok/obrigado" — não precisam de resposta)`);
    if (desistiram) {
      waitingLines.push(desistiram === 1
        ? `   (+1 disse que fechou com outra empresa ou desistiu — saiu da lista)`
        : `   (+${desistiram} disseram que fecharam com outra empresa ou desistiram — saíram da lista)`);
    }

    // Conversas que o dono pediu para acompanhar e promessas dele para hoje (06/10/2026).
    try {
      const fimDoDia = new Date(now.getTime() + 24 * 3600000).toISOString();
      const { data: acomp } = await admin.from("whatsapp_acompanhamentos")
        .select("contato, phone_normalized, modo, lembrar_em").eq("status", "ativo").limit(50);
      const lista = (acomp as any[]) || [];
      const acompanhando = lista.filter((a) => a.modo === "acompanhar");
      const promessasHoje = lista.filter((a) => a.modo === "promessa" && a.lembrar_em && a.lembrar_em <= fimDoDia);
      if (acompanhando.length) waitingLines.push(`👁️ Acompanhando: ${acompanhando.map((a) => nomeDeContato(a.contato || a.phone_normalized)).slice(0, 5).join(", ")}`);
      if (promessasHoje.length) waitingLines.push(`🤝 Promessas suas para hoje: *${promessasHoje.length}* (${promessasHoje.map((a) => nomeDeContato(a.contato || a.phone_normalized)).slice(0, 4).join(", ")})`);
    } catch (_e) {
      // Enriquecimento: nunca derruba o resumo.
    }

    // ── Caixa de entrada financeira: propostas de lançamento esperando o gestor ──
    // O extrato vira despesa só quando alguém aprova; fila esquecida é DRE errado. Só aparece
    // quando há algo, com o valor somado para dar noção do tamanho.
    const filaFinanceiraLines: string[] = [];
    let filaFinanceiraCount = 0;
    try {
      const { data: propostas } = await admin
        .from("finance_review_queue")
        .select("suggested_amount, kind, title")
        .eq("status", "pending")
        .limit(1000);
      const todas = (propostas as any[]) || [];
      const rows = todas.filter((p) => p.kind !== "anomaly");
      const alertas = todas.filter((p) => p.kind === "anomaly");
      filaFinanceiraCount = rows.length;
      // 15/10/2026: saída, entrada e transferência separadas — somar tudo em valor absoluto dava um
      // número que não era nada (51 = 46 saídas + 4 entradas + 1 transferência).
      const linhaPropostas = linhaDasPropostas(rows, (v) => fmt.format(v));
      if (linhaPropostas) filaFinanceiraLines.push(linhaPropostas);
      // Vigilante de despesas (módulo IV, decisão do dono de 14/09): só avisa, e avisa aqui.
      if (alertas.length > 0) {
        filaFinanceiraLines.push(`⚠️ Vigilante de despesas: *${alertas.length}* alerta(s)`);
        for (const a of alertas.slice(0, 3)) filaFinanceiraLines.push(`   • ${String(a.title).slice(0, 110)}`);
        if (alertas.length > 3) filaFinanceiraLines.push(`   …e mais ${alertas.length - 3} na caixa de entrada`);
      }
      // Regras que o sistema aprendeu e esperam o dono conferir (07/10/2026: "sempre registrar e
      // notificar"). Propostas não lançam nada até serem aceitas.
      const { count: regrasEsperando } = await admin
        .from("finance_rules").select("id", { count: "exact", head: true })
        .eq("origin", "ai").eq("status", "proposed");
      if ((regrasEsperando ?? 0) > 0) {
        filaFinanceiraLines.push(`🧠 Regras que aprendi esperando você conferir: *${regrasEsperando}* (Extrato › Regras)`);
      }
    } catch (e) {
      console.warn("[ai-daily-briefing] bloco da fila financeira falhou:", (e as Error).message);
    }

    // ── Extrato: o que foi lançado sozinho e a pergunta do débito sem loja ──
    // Decisões do dono de 26/09/2026 (respostas 15 e 17): o lançar sozinho só vale porque é
    // visível e desfazível — o resumo diz o que foi lançado nas últimas 24h e como desfazer;
    // e a compra no débito que o banco não diz onde foi vira pergunta, uma vez por dia.
    let extratoNoResumo: { linhas: string[]; acoes: string[] } = { linhas: [], acoes: [] };
    try {
      const desde24h = new Date(Date.now() - 24 * 3600_000).toISOString();
      const [{ data: sozinhos }, { data: pendentes }, { data: canceladas }] = await Promise.all([
        admin.from("finance_review_queue")
          .select("title, suggested_amount, suggested_category, automatica")
          .not("automatica", "is", null).eq("status", "approved").gte("decided_at", desde24h)
          .order("decided_at", { ascending: false }).limit(200),
        admin.from("finance_review_queue")
          .select(`suggested_amount, suggested_date, evidencia, bank_transaction_id,
                   bank_transactions!finance_review_queue_bank_transaction_id_fkey ( description, counterparty_name, counterparty_document )`)
          .eq("status", "pending").eq("kind", "create_payable")
          .order("suggested_date", { ascending: false }).limit(1000),
        // Anotações que a VARREDURA cancelou nas últimas 24h (as canceladas na hora já foram
        // respondidas na conversa): valor, quem e o motivo. A que o dono desfez ao cancelar um
        // comprovante (motivo "CMP-00124 cancelado: …", F2 de 11/10/2026) não é "não aplicada": fica fora.
        admin.from("anotacoes_do_extrato")
          .select("id, valor, criada_em, cancelada_em, motivo_cancelamento, nome, suppliers(name), payees(name), clients(name)")
          .eq("status", "cancelada").not("motivo_cancelamento", "is", null).not("motivo_cancelamento", "like", "CMP-%")
          .gte("cancelada_em", desde24h)
          .order("cancelada_em", { ascending: false }).limit(50),
      ]);
      // Compra no débito (ou no cartão) sem loja: o banco só escreveu o meio de pagamento.
      const semLoja = ((pendentes as any[]) || []).filter((l) => {
        const t = l.bank_transactions;
        if (!t || String(t.counterparty_document ?? "").replace(/\D/g, "").length >= 11) return false;
        return historicoSemIdentidade(t.counterparty_name || t.description)
          && /^(DEBITO|COMPRA)/.test(normalizeText(String(t.description ?? "")));
      });
      // O que o dono já respondeu (anotação) não é perguntado de novo: só falta aprovar. F3 (11/10/2026,
      // só remoção): nem a linha que um comprovante (CMP) já ligou ou que a pergunta do extrato espera;
      // e a anotação de um CMP vivo não é "não aplicada". Erro na consulta = o bloco como antes.
      const listaCanceladas = ((canceladas as any[]) || []);
      const doCmp = semLoja.length || listaCanceladas.length
        ? await linhasDosComprovantes(admin)
        : { linhas: new Set<string>(), anotacoes: new Set<string>() };
      const { debitos, anotadosEsperando } = debitosSemComprovante(semLoja, doCmp);
      const fmtExtrato = new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL" });
      const naoAplicadas = canceladasSemComprovante(listaCanceladas, doCmp)
        .filter((a) => new Date(a.cancelada_em).getTime() - new Date(a.criada_em).getTime() > 60_000)
        .map((a) => ({
          valor: a.valor,
          quem: a.suppliers?.name ?? a.payees?.name ?? a.clients?.name ?? a.nome ?? null,
          motivo: String(a.motivo_cancelamento),
        }));
      extratoNoResumo = linhasDoExtratoNoResumo((sozinhos as any[]) || [], debitos, (v) => fmtExtrato.format(v),
        { anoAtual: new Date(Date.now() - 3 * 3600_000).getUTCFullYear(), anotadosEsperando, naoAplicadas });
    } catch (e) {
      console.warn("[ai-daily-briefing] bloco do extrato falhou:", (e as Error).message);
    }

    // ── Extrato por identificar (varredura de conciliação) ─────────────────────
    // Só reporta: dinheiro que entrou na conta e ainda não foi ligado a nada. Não concilia
    // nada sozinho aqui — a conciliação automática só acontece na camada de certeza, e
    // por ação explícita na tela ou no agente.
    // 15/10/2026: era `.limit(4)` e a linha contava o que voltava — travada em 4 (eram 10). Agora
    // conta todas e separa (./entradas.ts): as do mês; os Pix que já são um sinal lançado à mão
    // (pagamento confirmado sem linha do extrato, mesmo valor e data — nunca pelo nome de quem
    // pagou); e as antigas/centavos. As duas últimas viram UMA linha de escritório. Fica antes do
    // conselheiro: o "Mês até aqui" usa as entradas do mês.
    const conciliaLines: string[] = [];
    let entradasSeparadas: EntradasSeparadas | null = null;
    try {
      const { data: pendentesBanco, error: bErr } = await admin
        .from("bank_transactions")
        .select("id, transaction_date, description, amount")
        .eq("reconciled", false)
        .eq("transaction_type", "credit")
        .eq("source_type", "bank")
        .is("dismissed_at", null)
        .order("amount", { ascending: false })
        .limit(1000);
      if (bErr) throw bErr;

      // Pagamentos já lançados sem linha do extrato (a mesma leitura dos candidatos do motor,
      // _shared/banking/candidatos.ts). Erro aqui = sem reconhecer sinais (a linha de antes), não silêncio.
      let pagamentos: PagamentoSemExtrato[] = [];
      try {
        const { data: pags, error: pErr } = await admin
          .from("payments")
          .select("id, amount, payment_date, payment_method, receivables(description, bank_transaction_id, clients(name))")
          .eq("status", "confirmed")
          .is("bank_transaction_id", null)
          .not("receivable_id", "is", null)
          .gte("payment_date", somarDiasAoDia(hojeBR, -60))
          .limit(1000);
        if (pErr) throw pErr;
        const lidos = ((pags as any[]) || []).filter((p) => !p.receivables?.bank_transaction_id);
        const ids = lidos.map((p) => String(p.id));
        const ligados = new Set<string>();
        if (ids.length > 0) {
          const { data: lig, error: lErr } = await admin
            .from("bank_transactions").select("reconciled_payment_id").in("reconciled_payment_id", ids);
          if (lErr) throw lErr;
          for (const r of (lig as any[]) || []) ligados.add(String(r.reconciled_payment_id));
        }
        pagamentos = lidos.filter((p) => !ligados.has(String(p.id))).map((p) => {
          const desc = p.receivables?.description ?? "Pagamento já lançado";
          const cliente = p.receivables?.clients?.name;
          return {
            id: String(p.id), amount: p.amount, payment_date: String(p.payment_date),
            rotulo: cliente ? `${desc} (${cliente})` : desc, forma: p.payment_method ?? null,
          };
        });
      } catch (e) {
        console.warn("[ai-daily-briefing] leitura dos pagamentos sem extrato falhou:", (e as Error).message);
      }

      const separadas = separarEntradas(((pendentesBanco as any[]) || []) as EntradaDoBanco[], pagamentos, hojeBR);
      entradasSeparadas = separadas;

      // Roda o motor para dizer o que as entradas do mês provavelmente são, em vez de só
      // apontar que existem. Só sugere — conciliar continua sendo ação explícita.
      const sugestoesPorTx = new Map<string, string>();
      if (separadas.doMes.length > 0) {
        try {
          const resp = await fetch(`${Deno.env.get("SUPABASE_URL")}/functions/v1/banking-reconcile`, {
            method: "POST",
            headers: {
              "Content-Type": "application/json",
              "x-cron-secret": Deno.env.get("CRON_SECRET") ?? "",
            },
            body: JSON.stringify({ action: "suggest", limit: 20 }),
          });
          if (resp.ok) {
            const dados = await resp.json();
            for (const item of dados.transactions || []) {
              const melhor = (item.suggestions || [])[0];
              if (melhor) {
                sugestoesPorTx.set(
                  item.transaction.id,
                  `${melhor.candidate.label}${melhor.candidate.clientName ? ` (${melhor.candidate.clientName})` : ""} · ${melhor.score}%`,
                );
              }
            }
          }
        } catch (e) {
          console.warn("[ai-daily-briefing] motor de conciliação indisponível:", e);
        }
      }
      conciliaLines.push(...linhasDasEntradas(separadas, (v) => fmt.format(v), sugestoesPorTx, hojeBR));
    } catch (e) {
      console.warn("[ai-daily-briefing] varredura de conciliação falhou:", e);
    }

    // ── Conselheiro (Executivo Financeiro, módulo V — decisão do dono de 14/09/2026) ──
    // No máximo três CONSTATAÇÕES: resultado do mês até aqui, concentração do faturamento e
    // a próxima semana no vermelho. A SUGESTÃO fica separada, no bloco "Sugestão de hoje".
    // Mesmo cálculo da tool resultado_do_periodo; best-effort, nunca derruba o briefing.
    const conselheiroLines: string[] = [];
    let semanaNoVermelho: { inicio: string; saldo: number } | null = null;
    try {
      const fmtBRL0 = new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL", maximumFractionDigits: 0 });
      const deMes = `${hojeBR.slice(0, 7)}-01`;
      const [cats, pays, recs, filaDoMes] = await Promise.all([
        admin.from("financial_categories").select("name, type, dre_group"),
        // Despesa cancelada não entra no resultado (a receita cancelada já era filtrada).
        admin.from("payables").select("amount, expense_category").neq("status", "cancelled").gte("issue_date", deMes).lte("issue_date", hojeBR),
        admin.from("receivables").select("amount, status, client_id, clients(name)").gte("issue_date", deMes).lte("issue_date", hojeBR),
        // 15/10/2026: as despesas do mês que ainda estão na fila de propostas (27, R$ 11.143,82
        // naquele dia) ficavam fora do resultado — que saía otimista com a nota de "pessimista".
        admin.from("finance_review_queue").select("suggested_amount, dre_group, suggested_category")
          .eq("status", "pending").eq("kind", "create_payable")
          .gte("suggested_date", deMes).lte("suggested_date", hojeBR).limit(1000),
      ]);
      const grupoDe = new Map<string, string>();
      for (const c of (cats.data as any[]) || []) if (c.dre_group) grupoDe.set(`payable:${c.name}`, c.dre_group);
      const somaGrupo = (g: string) => ((pays.data as any[]) || [])
        .filter((p) => grupoDe.get(`payable:${p.expense_category}`) === g)
        .reduce((s, p) => s + Number(p.amount || 0), 0);
      const receita = ((recs.data as any[]) || []).filter((r) => r.status !== "cancelled").reduce((s, r) => s + Number(r.amount || 0), 0);
      const saidas = somaGrupo("custo_direto") + somaGrupo("despesa_operacional") + somaGrupo("financeiro");
      if (receita > 0 || saidas > 0) {
        const grupoDaCategoria = new Map<string, string>();
        for (const c of (cats.data as any[]) || []) if (c.dre_group && c.type === "payable") grupoDaCategoria.set(String(c.name), c.dre_group);
        // Fila ilegível = sem a parte das despesas na nota (nunca "faltam 0").
        const despesasPendentes = filaDoMes.error
          ? { n: 0, soma: 0 }
          : despesasPendentesDoMes((filaDoMes.data as any[]) || [], grupoDaCategoria);
        if (filaDoMes.error) console.warn("[ai-daily-briefing] fila do mês ilegível:", filaDoMes.error.message);
        const doMes = entradasSeparadas?.doMes ?? [];
        const entradasSemReceita = { n: doMes.length, soma: doMes.reduce((s, e) => s + Number(e.amount || 0), 0) };
        conselheiroLines.push(
          `📊 Mês até aqui: receita ${fmtBRL0.format(receita)} · custos e despesas ${fmtBRL0.format(saidas)} · resultado *${fmtBRL0.format(receita - saidas)}*`
          + notaDoMes({ despesasPendentes, entradasSemReceita }, (v) => fmtBRL0.format(v)),
        );
      }

      // O faturado do mês por cliente (os mesmos recebíveis da receita acima). Até 15/10/2026 vinha
      // da rpc bi_top_clients, que soma as OS CRIADAS no mês ("Nelson 100%" com o faturado real em
      // Marcelo 44% · Nelson 27% · Giancarlo 15%). Um cliente só não vira linha.
      if (!recs.error) {
        const linhaFat = faturamentoPorCliente(((recs.data as any[]) || []).map((r) => ({
          amount: r.amount, status: r.status, client_id: r.client_id ?? null,
          nome: (Array.isArray(r.clients) ? r.clients[0]?.name : r.clients?.name) ?? null,
        })));
        if (linhaFat) conselheiroLines.push(linhaFat);
      }

      // Quatro semanas à frente: a receber (pendente) menos a pagar (pendente), por semana.
      const fim28 = new Date(now.getTime() + 28 * 86400000).toISOString().slice(0, 10);
      const [recFut, payFut] = await Promise.all([
        admin.from("receivables").select("balance_amount, amount, due_date").in("status", ["pending", "partially_paid"]).eq("is_deposit", false).gte("due_date", todayISO).lt("due_date", fim28),
        admin.from("payables").select("balance_amount, amount, due_date").in("status", ["pending", "partially_paid", "overdue"]).gte("due_date", todayISO).lt("due_date", fim28),
      ]);
      const semanas = [0, 0, 0, 0];
      const idx = (d: string) => Math.min(3, Math.max(0, Math.floor((new Date(`${d}T12:00:00Z`).getTime() - new Date(`${todayISO}T12:00:00Z`).getTime()) / (7 * 86400000))));
      for (const r of (recFut.data as any[]) || []) semanas[idx(r.due_date)] += Number(r.balance_amount ?? r.amount ?? 0);
      for (const p of (payFut.data as any[]) || []) semanas[idx(p.due_date)] -= Number(p.balance_amount ?? p.amount ?? 0);
      const negativa = semanas.findIndex((s) => s < 0);
      if (negativa >= 0) {
        const inicio = new Date(new Date(`${todayISO}T12:00:00Z`).getTime() + negativa * 7 * 86400000).toISOString().slice(0, 10);
        semanaNoVermelho = { inicio, saldo: semanas[negativa] };
        conselheiroLines.push(`📉 Semana de ${inicio.slice(8, 10)}/${inicio.slice(5, 7)} prevista no vermelho: ${fmtBRL0.format(semanas[negativa])} (a receber − a pagar)`);
      }
    } catch (e) {
      console.warn("[ai-daily-briefing] bloco do conselheiro falhou:", (e as Error).message);
    }

    // ── "Deixar a IA acompanhar": o que espera o dono, quem respondeu, o que voltou ──
    // Só aparece quando há missão em andamento; devolvidas só nos 3 primeiros dias, para o
    // digest não repetir a mesma pendência todo dia. Best-effort: não derruba o briefing.
    const missaoLines: string[] = [];
    try {
      const { data: missoes } = await admin
        .from("ai_followup_missions")
        .select("id, contraparte_label, status, toques_feitos, max_toques, resolucao, resolvida_em")
        .in("status", ["active", "waiting_reply", "escalated"]);
      const ms = ((missoes as any[]) || []).filter((m) =>
        m.status !== "escalated" || (m.resolvida_em && now.getTime() - new Date(m.resolvida_em).getTime() < 3 * 86400000));
      if (ms.length > 0) {
        const { count: rascunhos } = await admin
          .from("ai_operator_pending_actions")
          .select("id", { count: "exact", head: true })
          .eq("status", "pending")
          .eq("action_name", "followup_send_touch");
        missaoLines.push(`🤖 IA acompanhando: *${ms.length}*`);
        if ((rascunhos ?? 0) > 0) missaoLines.push(`   • ${rascunhos} mensagem(ns) redigida(s) esperando seu sim no sino`);
        for (const m of ms.filter((x) => x.status === "waiting_reply").slice(0, 3)) {
          missaoLines.push(`   • *${m.contraparte_label}* respondeu — leia antes de tocar de novo`);
        }
        for (const m of ms.filter((x) => x.status === "escalated").slice(0, 3)) {
          missaoLines.push(`   • *${m.contraparte_label}* voltou para você: ${m.resolucao ?? "sem resposta"}`);
        }
      }
    } catch (e) {
      console.warn("[ai-daily-briefing] bloco IA acompanhando falhou:", (e as Error).message);
    }

    const dateBR = now.toLocaleDateString("pt-BR", { weekday: "long", day: "2-digit", month: "long" });

    // ── Orçamentos parados / expirando (Fase 2 do piloto) ──
    // Só lista os que pedem ação: parados há ≥2 dias OU perto de expirar / expirados.
    // Orçamento recém-mexido não polui o digest. Ordena pelos mais parados primeiro.
    const { data: openQuotes } = await admin
      .from("service_orders")
      .select("service_order_number, grand_total, updated_at, quote_status, created_at, quote_validity_days, quote_validity_date, clients(name), vessels(name)")
      .eq("status", "draft")
      .in("quote_status", ["sent", "awaiting_approval", "awaiting_deposit"])
      .order("updated_at", { ascending: true })
      .limit(20);
    const todayMid = new Date(`${todayISO}T00:00:00`).getTime();
    const daqui3Dias = somarDiasAoDia(hojeBR, 3);
    const quoteLines: string[] = [];
    const flaggedQuotes = ((openQuotes as any[]) || [])
      .map((q: any) => {
        const dias = Math.floor((now.getTime() - new Date(q.updated_at).getTime()) / 86400000);
        // O mesmo "até" do PDF e da R19 (ultimoDiaDaValidade). Até 26/09/2026 só a data fixa
        // contava, e ela quase nunca existe: nenhum orçamento aparecia expirado. Aprovado
        // aguardando sinal não expira — o cliente já disse sim (a R19 também o deixa de fora).
        const fim = q.quote_status === "awaiting_deposit" ? null : ultimoDiaDaValidade(q, cfg);
        const expired = !!fim && hojeBR > fim;
        const expiringSoon = !!fim && !expired && fim <= daqui3Dias;
        const nome = Array.isArray(q.clients) ? q.clients[0]?.name : q.clients?.name;
        const barco = Array.isArray(q.vessels) ? q.vessels[0]?.name : q.vessels?.name;
        // 15/10/2026: sempre com o número (ORÇ-xxxxx) e o barco — "Cliente Final" sozinho não diz qual é.
        return {
          numero: String(q.service_order_number || "Orçamento"),
          nome: nomeDeContato(nome) || "(sem cliente)",
          barco: barco ? nomeDeContato(barco) : null,
          valor: Number(q.grand_total || 0), dias, expired, expiringSoon,
        };
      })
      .filter((q: any) => q.dias >= 2 || q.expired || q.expiringSoon)
      .slice(0, 5);
    if (flaggedQuotes.length > 0) {
      for (const q of flaggedQuotes) {
        quoteLines.push(linhaDoOrcamento({ ...q, cliente: q.nome }, (v) => fmt.format(v)));
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
      recebLines.push(`   • ${nomeDeContato(nome) || "(sem cliente)"} — ${fmt.format(Number(r.balance_amount ?? r.amount ?? 0))} · vencido ${dias}d`);
    }

    // ── E-mail (08/10/2026): o que chegou nas caixas financeiro@ e gustavo@ nas últimas 24 h, já
    // classificado pela triagem do email-imap. Pouco de propósito (_shared/email/digest.ts): urgente,
    // esperando resposta e documentos em linha; informativo e filtrado só em número. Best-effort.
    const emailLines: string[] = [];
    try {
      const desde = new Date(now.getTime() - 24 * 3600_000).toISOString();
      const { data: emails, error: eErr } = await admin.from("email_messages")
        .select("id, from_name, from_address, subject, received_at, triage_class, triage_fraud_alert, alerted_at, muted, dados_extraidos, clients(name), suppliers(name), email_attachments(kind)")
        .gte("received_at", desde).not("triage_class", "is", null).order("received_at", { ascending: false }).limit(200);
      if (eErr) throw eErr;
      // Urgente já avisado na hora (email-imap grava alerted_at) ANTES de hoje não volta como
      // "Urgente": vira número no rodapé (15/10/2026 — o mesmo golpe avisado em 13 e 14/10 voltou
      // nos resumos de 14 e 15/10). Aviso de hoje de madrugada continua aparecendo. Erro = como antes.
      const avisadosAntes = new Set<string>();
      if (((emails ?? []) as any[]).some((m) => m.triage_class === "urgent")) {
        const { data: avisos, error: avErr } = await admin.from("email_messages")
          .select("from_address, subject")
          .gte("alerted_at", new Date(now.getTime() - 30 * 86400000).toISOString())
          .lt("alerted_at", dayStart)
          .limit(1000);
        if (avErr) console.warn("[ai-daily-briefing] avisos de e-mail anteriores ilegíveis:", avErr.message);
        for (const a of (avisos as any[]) || []) avisadosAntes.add(chaveDoAviso(a.from_address, a.subject));
      }
      const itens: EmailDigestItem[] = ((emails ?? []) as any[]).filter((m) => !m.muted).map((m) => {
        const kinds = ((m.email_attachments ?? []) as { kind: string }[]).map((a) => a.kind);
        // NF-e e boleto conferidos por DV (etapa 4); sem dado extraído, só o tipo do anexo.
        const resumoAnexo = resumoDosDados(m.dados_extraidos, (v) => fmt.format(v))
          ?? (kinds.includes("nfe_xml") ? "NF-e anexa" : kinds.includes("boleto_pdf") ? "boleto anexo" : null);
        return {
          classe: m.triage_class,
          remetente: m.clients?.name ?? m.suppliers?.name ?? m.from_name ?? m.from_address,
          assunto: m.subject,
          recebidoEm: m.received_at,
          resumoAnexo,
          alertaFraude: !!m.triage_fraud_alert,
          jaAvisado: m.triage_class === "urgent" && avisadosAntes.has(chaveDoAviso(m.from_address, m.subject)),
        };
      });
      const secao = montarSecaoEmail(itens);
      if (secao) emailLines.push("", secao);
    } catch (e) {
      console.warn("[ai-daily-briefing] bloco de e-mail falhou:", (e as Error).message);
    }

    // ── Vigia do negócio (07/10/2026, pedido do dono) ─────────────────────────────────────
    // Segunda-feira e dia 1 (ou ?vigia=1 para pré-visualizar): ponto de equilíbrio × último mês
    // fechado, despesa por categoria em alta, concentração/margem por sistema. Leitura em
    // _shared/financeiro/vigia-do-negocio.ts; números da rpc analise_do_negocio. Best-effort.
    const vigiaLines: string[] = [];
    let vigiaSugestao: string | null = null;
    const hojeBRT = new Date(now.getTime() - 3 * 3600_000);
    const diaDoVigia = hojeBRT.getUTCDay() === 1 || hojeBRT.getUTCDate() === 1 || new URL(req.url).searchParams.get("vigia") === "1";
    if (diaDoVigia) {
      try {
        const { data: analise, error: aErr } = await admin.rpc("analise_do_negocio", { p_meses: 6 });
        if (aErr) throw aErr;
        const lido = lerAnalise(analise ?? {}, (v) => fmt.format(v));
        if (lido.constatacoes.length) vigiaLines.push("", lido.titulo, ...lido.constatacoes.map((c) => `• ${c}`));
        vigiaSugestao = lido.sugestao;
      } catch (e) {
        console.warn("[ai-daily-briefing] vigia do negócio falhou:", (e as Error).message);
      }
    }

    // Sugestão do dia (Onda 1): 1 sugestão acionável, rotativa por dia — reusa os candidatos
    // já levantados (orçamentos parados, recebíveis vencidos, OS paradas). Uma por dia, sem spam.
    const sugestoes: string[] = [];
    if (conciliaLines.length > 0) {
      sugestoes.push("conciliar as entradas do extrato que ainda não foram identificadas. Me peça *conciliar extrato* que eu analiso e sugiro as correspondências.");
    }
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
    if (revisoes.sugestao) sugestoes.push(revisoes.sugestao); // planos de manutenção (07/10/2026)
    for (const c of manutCandidatos.slice(0, 3)) {
      sugestoes.push(`oferecer revisão do *${c.ativo}* (${c.cliente}) — ${c.meses} meses sem serviço. Me peça que eu preparo o orçamento.`);
    }
    if (semanaNoVermelho) {
      const d = semanaNoVermelho.inicio;
      sugestoes.push(`olhar a semana de *${d.slice(8, 10)}/${d.slice(5, 7)}*: os pagamentos previstos passam dos recebimentos em ${fmt.format(-semanaNoVermelho.saldo)}. Antecipar uma cobrança ou combinar um vencimento resolve.`);
    }
    const diaDoAno = Math.floor((now.getTime() - new Date(now.getFullYear(), 0, 0).getTime()) / 86400000);
    // No dia do vigia, a sugestão é a dele (margem ou marketing); nos outros, a rotativa.
    const sugestaoLine = vigiaSugestao
      ? `💡 *Sugestão de hoje:* ${vigiaSugestao}`
      : sugestoes.length > 0 ? `💡 *Sugestão de hoje:* ${sugestoes[diaDoAno % sugestoes.length]}` : "";

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
    if (missaoLines.length > 0) quickActions.push(`   • *Como estão os acompanhamentos da IA?*`);
    if (filaFinanceiraCount > 0) quickActions.push(`   • *O que está esperando na caixa de entrada financeira?*`);
    quickActions.push(...extratoNoResumo.acoes);
    if (revisoes.acao) quickActions.push(revisoes.acao);
    const quickActionLines = quickActions.length > 0
      ? ["", "⚡ *Ações rápidas* (responda com uma):", ...quickActions]
      : [];

    const linhas = [
      `☀️ *Bom dia! Resumo de ${dateBR}*`,
      "",
      // Contador zerado não ocupa linha (15/10/2026); o `metrics` do retorno segue com os números.
      ...[linhaSeHouver("📅 Agendamentos hoje", scheduledCount)].filter((l): l is string => !!l),
      `📄 Orçamentos aguardando resposta: *${quotesCount ?? 0}*`,
      ...quoteLines,
      `💸 Recebíveis vencidos: *${overdueCount}*${overdueCount > 0 ? ` (${fmt.format(overdueSum)})` : ""}`,
      ...recebLines,
      ...(upcomingCount > 0 ? [`🔜 A vencer (próx. 3 dias): *${upcomingCount}* (${fmt.format(upcomingSum)})`] : []),
      ...[linhaSeHouver("✅ Aprovações da IA pendentes", pendingCount)].filter((l): l is string => !!l),
      ...filaFinanceiraLines,
      ...extratoNoResumo.linhas,
      ...conselheiroLines,
      ...vigiaLines,
      ...emailLines,
      ...conciliaLines,
      ...stuckLines,
      ...revisoes.linhas,
      ...manutLines,
      ...stockLines,
      ...waitingLines,
      ...missaoLines,
      ...(sugestaoLine ? ["", sugestaoLine] : []),
      ...quickActionLines,
      "",
      `_Enviado pelo assistente de ${companyName}. Responda por aqui para pedir qualquer coisa._`,
    ];
    const message = linhas.join("\n");

    // ── "📋 Sua agenda hoje" (Agenda & Tarefas 2.0): bloco PESSOAL por destinatário ──
    // Tarefas vivas de todos os destinatários numa consulta só; agrupa por responsável.
    const recIds = recipients.map((r: any) => r.id).filter(Boolean);
    const personalBlocks = new Map<string, string>();
    if (recIds.length > 0) {
      const hoje = new Date(now.getTime() - 3 * 3600000).toISOString().slice(0, 10);
      const dayStart = new Date(`${hoje}T00:00:00-03:00`).toISOString();
      const dayEnd = new Date(new Date(dayStart).getTime() + 86400000).toISOString();
      const { data: liveTasks } = await admin
        .from("agenda_tasks")
        .select("assignee_user_id, title, priority, due_at, scheduled_start_at, scheduled_end_at, kind, created_at")
        .in("status", ["pending", "in_progress"])
        .in("assignee_user_id", recIds)
        .limit(300);
      // Segunda-feira (BRT): revisão semanal guiada (padrão OmniFocus weekly review)
      const isMondayBRT = new Date(now.getTime() - 3 * 3600000).getUTCDay() === 1;
      const fmtHora = (iso: string) => new Date(iso).toLocaleTimeString("pt-BR", {
        hour: "2-digit", minute: "2-digit", timeZone: "America/Sao_Paulo",
      });
      for (const uid of recIds) {
        const mine = (liveTasks || []).filter((t: any) => t.assignee_user_id === uid);
        const anchor = (t: any) => t.due_at || t.scheduled_start_at;
        const atrasadas = mine.filter((t: any) => anchor(t) && anchor(t) < dayStart);
        const doDia = mine
          .filter((t: any) => anchor(t) && anchor(t) >= dayStart && anchor(t) < dayEnd)
          .sort((a: any, b: any) => String(anchor(a)).localeCompare(String(anchor(b))));
        if (atrasadas.length === 0 && doDia.length === 0) continue;
        const bloco: string[] = ["", "📋 *Sua agenda hoje*"];
        if (atrasadas.length > 0) {
          bloco.push(`   ⚠️ Atrasadas: *${atrasadas.length}*`);
          for (const t of atrasadas.slice(0, 3)) bloco.push(`   • ${t.title}`);
        }
        for (const t of doDia.slice(0, 5)) {
          const hora = t.scheduled_start_at ? `${fmtHora(t.scheduled_start_at)} ` : "";
          bloco.push(`   • ${hora}${t.title}${t.priority === "urgent" ? " ‼️" : ""}`);
        }
        if (doDia.length > 5) bloco.push(`   …e mais ${doDia.length - 5}`);
        // Risco de prazo (padrão Motion, sem o auto-scheduling): amanhã apertado?
        const d2Start = new Date(new Date(dayStart).getTime() + 86400000).toISOString();
        const d2End = new Date(new Date(dayStart).getTime() + 2 * 86400000).toISOString();
        const amanha = mine.filter((t: any) => anchor(t) && anchor(t) >= d2Start && anchor(t) < d2End);
        const amanhaBusyH = amanha.reduce((s: number, t: any) => {
          if (!t.scheduled_start_at || !t.scheduled_end_at) return s;
          return s + Math.max(0, (new Date(t.scheduled_end_at).getTime() - new Date(t.scheduled_start_at).getTime()) / 3600000);
        }, 0);
        if (amanha.length >= 3 || amanhaBusyH >= 6) {
          bloco.push(`   ⏳ Amanhã: ${amanha.length} item(ns)${amanhaBusyH > 0 ? ` · ~${amanhaBusyH.toFixed(1).replace(".0", "")}h ocupadas` : ""} — risco de aperto, antecipe o que der.`);
        }
        if (isMondayBRT) {
          const paradas = mine.filter((t: any) =>
            t.created_at && new Date(t.created_at) < new Date(now.getTime() - 7 * 86400000));
          if (paradas.length > 0) {
            bloco.push(`   🔁 Revisão semanal: *${paradas.length}* tarefa(s) aberta(s) há 7+ dias — decida: fazer, delegar ou descartar.`);
            for (const t of paradas.slice(0, 3)) bloco.push(`      • ${t.title}`);
          }
        }
        personalBlocks.set(uid, bloco.join("\n"));
      }
      // Caixa de entrada (Fase 9): sugestões esperando decisão — 1 linha, sem interromper.
      // Só as de produtor ATIVO (05/10/2026, decisão do dono): o detector de conversas do WhatsApp
      // está pausado desde 30/09 e as 176 sugestões dele, paradas há semanas, faziam o resumo
      // anunciar todo dia "186 sugestões esperando". Conta a cobrança de saldo (manual_text), que
      // segue gravando. Se o detector voltar, tirar o filtro de origem.
      const { count: pendingSuggestions } = await admin
        .from("agenda_suggestions")
        .select("id", { count: "exact", head: true })
        .eq("status", "pending")
        .neq("origin", "whatsapp");
      if ((pendingSuggestions ?? 0) > 0) {
        for (const uid of recIds) {
          const atual = personalBlocks.get(uid) || "\n📋 *Sua agenda hoje*";
          personalBlocks.set(uid, `${atual}\n   📥 *${pendingSuggestions}* sugestão(ões) na caixa de entrada esperando sua decisão.`);
        }
      }
      // Rotina madura para virar automação: oferece UMA por vez, sem insistir
      const { data: maduras } = await admin
        .from("ai_learned_routines")
        .select("title, observations, suggested_automation")
        .eq("status", "observed").gte("observations", 3)
        .not("suggested_automation", "is", null)
        .order("observations", { ascending: false }).limit(1);
      const madura = ((maduras as any[]) || [])[0];
      if (madura) {
        for (const uid of recIds) {
          const atual = personalBlocks.get(uid) || "\n📋 *Sua agenda hoje*";
          personalBlocks.set(uid,
            `${atual}\n   🤖 Já reparei ${madura.observations}x: _${String(madura.title).toLowerCase()}_. Quer que eu passe a fazer sozinho? Responda *automatizar*.`);
        }
      }
    }
    const messageFor = (rec: any) => {
      const bloco = rec.id ? personalBlocks.get(rec.id) : undefined;
      if (!bloco) return message;
      // injeta o bloco pessoal antes do rodapé (última linha em itálico)
      const idx = linhas.length - 2; // linha em branco + rodapé
      return [...linhas.slice(0, idx), bloco, ...linhas.slice(idx)].join("\n");
    };

    // Dry-run (?dry=1): monta a mensagem mas NÃO enfileira — para pré-visualizar com segurança.
    if (new URL(req.url).searchParams.get("dry") === "1") {
      return jr({ ok: true, dry: true, recipients: recipients.length, preview: messageFor(recipients[0] || {}) });
    }

    // Enfileira uma mensagem por destinatário. O whatsapp-queue-worker entrega e, se falhar, tenta de
    // novo ~10 min depois (reagenda +5 min, mas roda de 5 em 5). Até 15/10/2026 eram 3 tentativas
    // (07:35, 07:45, 07:55): em 09 e 13/10 a fila desistiu e o WhatsApp voltou às 08:28 e às 08:56 —
    // a manhã não chegou. Agora tenta até ~09:05 (10 tentativas às 07:30).
    const maxTentativas = tentativasAte("09:00", now);
    const rows = recipients.map((rec: any) => ({
      phone_normalized: String(rec.phone_normalized),
      message: messageFor(rec),
      source: "ai_briefing",
      priority: 4,
      max_attempts: maxTentativas,
    }));
    const { data: inserted, error: qErr } = await admin.from("whatsapp_send_queue").insert(rows).select("id");
    if (qErr) throw qErr;

    // O resumo entra no histórico da conversa do assistente (15/10/2026): sem isso, "cobra esse" ou
    // "o 2" não tinha a que se referir. Duas linhas (./historico.ts) e a conversa marcada como ativa.
    // Falha aqui só loga: o resumo já está na fila.
    let historicoGravado = 0;
    for (const rec of recipients as any[]) {
      if (!rec.id || !rec.phone_normalized) continue;
      try {
        const agoraHist = new Date();
        const sessao = await resolveOrCreateWhatsAppSession(admin, String(rec.phone_normalized), String(rec.id));
        const { error: hErr } = await admin.from("ai_operator_messages").insert(linhasDoHistorico(sessao, messageFor(rec), agoraHist));
        if (hErr) throw hErr;
        const { error: sErr } = await admin.from("ai_operator_sessions").update({ last_activity_at: agoraHist.toISOString() }).eq("id", sessao);
        if (sErr) console.warn("[ai-daily-briefing] conversa não marcada como ativa:", sErr.message);
        historicoGravado++;
      } catch (e) {
        console.warn("[ai-daily-briefing] resumo fora do histórico do assistente:", rec.id, (e as Error).message);
      }
    }

    // O vigia também fica no sino de quem decide (admin e financeiro), para consultar depois.
    if (vigiaLines.length) {
      const { data: quemDecide } = await admin.from("app_users").select("id").eq("active", true).in("role", ["admin", "financial"]);
      const corpo = vigiaLines.slice(2).join("\n").replace(/\*/g, "").slice(0, 900);
      const { error: nErr } = await admin.from("app_notifications").insert(((quemDecide ?? []) as any[]).map((u) => ({
        user_id: u.id, type: "vigia_negocio", title: "Vigia do negócio", body: corpo, navigate_to: "/v2/financial",
      })));
      if (nErr) console.warn("[ai-daily-briefing] sino do vigia falhou:", nErr.message);
    }

    return jr({
      ok: true,
      queued: inserted?.length ?? 0,
      historico: historicoGravado,
      metrics: { scheduled: scheduledCount ?? 0, quotes: quotesCount ?? 0, overdue: overdueCount, overdue_sum: overdueSum, pending: pendingCount ?? 0 },
    });
  } catch (e: any) {
    console.error("[ai-daily-briefing] fatal", e);
    return jr({ error: e?.message || "internal error" }, 500);
  }
});
