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
//
// Horário (15/10/2026): só avisa das 8h às 20h de Brasília, e o "dia" das chaves é o de Brasília
// (horario.ts). Antes o dia era o UTC e o aviso de orçamentos parados saía às 21:10, todo dia.
// Também avisa quando o resumo da manhã desistiu de chegar (WhatsApp fora do ar).
//
// Voz única (secretário, Passo 4, 15/10/2026): com app_settings.voz_unica em sombra, cada sinal que SAIU
// é registrado no portão (avisos_do_dono) com o destino que a spec dá a ele (_shared/uma-voz/fontes.ts:
// vence hoje e orçamentos parados acabam — a manhã já mostra; saldo, estoque e cota vão ao escritório;
// certificado e consentimento pela faixa de dias; NF-e rejeitada e a manhã que não chegou acordam). O
// que sai para a equipe não muda. Desligado (o padrão): nada é registrado.
// (16/10/2026, P4.2) O registro leva o texto do ACORDE (o que sairia com a voz única ligada, sem emoji): o
// certificado de 7 dias ou menos e uma NF-e rejeitada POR NOTA (chave nfe:<id>), no lugar da contagem do dia.
// A mensagem que sai hoje para a equipe continua a mesma (a contagem por dia).
// (20/10/2026, P4.5) Voz única LIGADA de verdade (a manhã nova e o fechamento ligado no ar): o DONO não recebe mais o
// "🔔 Alerta…" — cada sinal pergunta ao portão antes (./voz.ts) e só o acorde sai; o resto vai com as mensagens fixas.
// A equipe recebe o de sempre. O "resumo não chegou" também pergunta antes. E a manhã que quebrou ANTES de entrar na
// fila (nenhuma linha ai_briefing do dono depois das 08:00) passa a ser avisada (manhaSemLinha), com qualquer voz.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import { createFiscalProvider } from "../_shared/fiscal/factory.ts";
import { verificarCronSecret } from "../_shared/cron-auth.ts";
import { ORIGEM_PADRAO, servirComCors } from "../_shared/cors.ts";
import {
  diaDoAviso, inicioDoDiaBR, inicioDoMesBR, manhaSemLinha, podeAvisarAgora, type ResumoNaFila, resumoDeHojeCobre,
  telefonesSemResumo, tentativasAteAs20h, TEXTO_MANHA_QUEBROU, TEXTO_RESUMO_NAO_CHEGOU,
} from "./horario.ts";
import type { AvisoDaFonte } from "../_shared/uma-voz/portao.ts";
import { avisoDaNfe, avisoDoCertificado, avisoDoConsentimento, avisoDoVigia, avisoResumoNaoChegou } from "../_shared/uma-voz/fontes.ts";
import { textoDaNfe, textoDoCertificado } from "../_shared/uma-voz/acorde.ts";
import {
  enfileirarAcorde, falaPeloPortao, lerDonoDaVoz, lerPortao, perguntarAoPortao, registrarNoPortao, registrarParaTodos,
} from "../_shared/uma-voz/registrar.ts";
import { falarAoDono, type SinalDoVigia } from "./voz.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": ORIGEM_PADRAO,
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-cron-secret",
  "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
};
function jr(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } });
}

/**
 * (16/10/2026, P4.2) As NF-e rejeitadas desde `desde`, uma por nota, com o texto do acorde (número, cliente, motivo
 * e a OS para reemitir). null = não deu para ler (quem chama registra o aviso do dia, como antes). Só leitura.
 */
// deno-lint-ignore no-explicit-any
async function avisosDasNotasRejeitadas(admin: any, desde: string): Promise<AvisoDaFonte[] | null> {
  try {
    const { data, error } = await admin.from("issued_fiscal_documents")
      // client_id sem chave estrangeira para clients: o embed clients(…) dá PGRST200 — o nome vem numa 2ª leitura
      .select("id, number, status_message, origin_type, origin_id, client_id")
      .eq("status", "rejected").gte("updated_at", desde).limit(20);
    if (error) return null;
    const notas = (data ?? []) as Array<Record<string, unknown>>;
    const daOs = notas.filter((n) => n.origin_type === "service_order" && n.origin_id).map((n) => String(n.origin_id));
    const numeroDaOs = new Map<string, string>();
    if (daOs.length) {
      const { data: oss } = await admin.from("service_orders").select("id, service_order_number").in("id", daOs);
      for (const o of (oss ?? []) as Array<{ id: string; service_order_number: string }>) numeroDaOs.set(String(o.id), o.service_order_number);
    }
    const idsDosClientes = [...new Set(notas.map((n) => n.client_id).filter(Boolean).map(String))];
    const nomeDoCliente = new Map<string, string>();
    if (idsDosClientes.length) {
      const { data: cls } = await admin.from("clients").select("id, name, display_name").in("id", idsDosClientes);
      for (const c of (cls ?? []) as Array<{ id: string; name: string | null; display_name: string | null }>) {
        const nome = c.display_name || c.name;
        if (nome) nomeDoCliente.set(String(c.id), nome);
      }
    }
    return notas.map((n) => {
      const cliente = n.client_id ? nomeDoCliente.get(String(n.client_id)) ?? null : null;
      const texto = textoDaNfe({
        numero: (n.number as number | null) ?? null, cliente, valor: null, motivo: (n.status_message as string | null) ?? null,
        os: n.origin_id ? numeroDaOs.get(String(n.origin_id)) ?? null : null,
      });
      return avisoDaNfe({ id: String(n.id), numero: (n.number as number | null) ?? null, cliente }, texto);
    });
  } catch {
    return null;
  }
}

servirComCors(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });
  // Era fail-OPEN (`if (cronSecret && ...)`): sem o env var, a função ficava aberta.
  const recusa = verificarCronSecret(req, corsHeaders, "ai-business-monitor");
  if (recusa) return recusa;

  try {
    const now = new Date();
    // Fora das 8h–20h de Brasília não lê nem reivindica nada: a chave do dia fica livre e o que
    // aparecer sai na primeira rodada da manhã (08:05). Nada de mensagem às 21h nem às 6h.
    if (!podeAvisarAgora(now)) return jr({ ok: true, fora_do_horario: true });

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

    // O dia de Brasília: entre 21h e meia-noite o dia UTC já é o seguinte.
    const todayISO = diaDoAviso(now);
    const fmt = new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL" });

    async function claim(alert_key: string, meta: any): Promise<boolean> {
      const { data } = await admin.from("ai_operator_alerts_log")
        .upsert({ alert_key, meta }, { onConflict: "alert_key", ignoreDuplicates: true }).select("id");
      return (data?.length ?? 0) > 0;
    }

    // O resumo da manhã de hoje na fila (uma linha por destinatário). Serve a dois sinais: o aviso
    // de orçamentos parados fica de fora quando o resumo já os listou, e quem ficou sem resumo é
    // avisado. Erro na leitura = como se não houvesse resumo (o aviso sai; melhor repetir que calar).
    const { data: resumosLidos, error: resumosErr } = await admin.from("whatsapp_send_queue")
      .select("phone_normalized, status").eq("source", "ai_briefing").gte("created_at", inicioDoDiaBR(now));
    if (resumosErr) console.warn("[ai-business-monitor] não li o resumo de hoje na fila:", resumosErr.message);
    const resumosDeHoje = (resumosErr ? [] : resumosLidos ?? []) as ResumoNaFila[];

    const alerts: string[] = [];
    // Voz única: o que cada sinal pediria ao portão (na sombra, registrado só depois que o alerta entrar na fila; ligada,
    // o dono pergunta antes, sinal a sinal — ./voz.ts).
    const portao = await lerPortao(admin);
    // (20/10/2026) o dono da manhã (o mesmo de ai-daily-briefing): a voz ligada fala com ele pelo portão, e a manhã que
    // quebrou antes da fila é a dele. Erro de leitura = null (ninguém passa pelo portão; nada de "manhã sem linha").
    const dono = await lerDonoDaVoz(admin);
    const paraOPortao: AvisoDaFonte[] = [];
    const sinais: SinalDoVigia[] = [];
    const alertar = (texto: string, ...avisos: AvisoDaFonte[]) => {
      alerts.push(texto);
      paraOPortao.push(...avisos);
      sinais.push({ texto, avisos });
    };

    // (1) Recebíveis vencidos HOJE
    const { data: dueToday } = await admin
      .from("receivables").select("balance_amount, amount")
      .in("status", ["pending", "partially_paid"]).eq("is_deposit", false).eq("due_date", todayISO);
    if ((dueToday?.length ?? 0) > 0 && await claim(`overdue_today:${todayISO}`, { n: dueToday!.length })) {
      const sum = dueToday!.reduce((a: number, r: any) => a + Number(r.balance_amount ?? r.amount ?? 0), 0);
      const t = `💸 *${dueToday!.length}* recebível(is) vence(m) hoje — total ${fmt.format(sum)}. Vale acionar a cobrança.`;
      alertar(t, avisoDoVigia("vence_hoje", todayISO, t));
    }

    // (2) Orçamentos parados há mais de 7 dias
    const d7 = new Date(now.getTime() - 7 * 864e5).toISOString();
    const { count: staleQuotes } = await admin
      .from("service_orders").select("id", { count: "exact", head: true })
      .eq("status", "draft").in("quote_status", ["sent", "awaiting_approval", "awaiting_deposit"])
      .lt("created_at", d7);
    // Com o dia certo este aviso sairia às 08:05, meia hora depois do resumo que já lista os
    // orçamentos parados. Só sai quando o resumo de hoje não chegou (nem está a caminho); a chave
    // não é gasta antes disso, então a rodada seguinte ainda pode avisar.
    if ((staleQuotes ?? 0) > 0 && !resumoDeHojeCobre(resumosDeHoje) && await claim(`stale_quotes:${todayISO}`, { n: staleQuotes })) {
      const t = `📄 *${staleQuotes}* orçamento(s) parado(s) há mais de 7 dias sem resposta. Talvez valha um follow-up.`;
      alertar(t, avisoDoVigia("orcamentos_parados", todayISO, t));
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
          const t = `🔐 Certificado A1${urg}: ${quando} (${vu}). Renove na Contora para não parar a emissão de NF-e.`;
          // (16/10) ≤ 7 dias acorda: o portão guarda o texto do acorde; 8–30 dias (linha "Hoje") guarda o de sempre
          alertar(t, avisoDoCertificado(String(vu), days, todayISO, days <= 7 ? textoDoCertificado(days, String(vu)) : t));
        }
      }
    } catch (_e) {
      // Nunca deixa uma falha na Contora derrubar os demais sinais do monitor.
      console.warn("[ai-business-monitor] checagem de certificado falhou (ignorada)");
    }

    // (3b) Consentimento Open Finance vencendo (Pluggy: ~12 meses). Quando vence, o extrato
    // simplesmente para de chegar, sem erro — e o financeiro fica cego sem saber (Open Finance D2).
    try {
      // Só as conexões ativas: a desativada (27/09/2026, "Desativar" em Contas bancárias) não
      // busca extrato, e avisar que o consentimento dela vence é ruído.
      const { data: conexoes } = await admin
        .from("bank_connections").select("id, consent_expires_at")
        .eq("active", true)
        .not("consent_expires_at", "is", null);
      for (const c of (conexoes ?? []) as { id: string; consent_expires_at: string }[]) {
        const dias = Math.floor((new Date(c.consent_expires_at).getTime() - now.getTime()) / 864e5);
        if (dias <= 30 && await claim(`consent_expiry:${c.id}:${todayISO}`, { dias })) {
          const quando = dias < 0 ? "VENCEU" : `vence em ${dias} dia(s)`;
          const t = `🏦 Consentimento do extrato bancário ${quando} (${String(c.consent_expires_at).slice(0, 10)}). Renove a conexão no Pluggy antes que o extrato pare de chegar.`;
          alertar(t, avisoDoConsentimento(c.id, dias, todayISO, t));
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
          const t = `🏦 Extrato de ${c.label}: o saldo do banco (${brl(ult.saldo_do_provedor)}) não bate com a soma das transações importadas (${brl(ult.saldo_calculado)}), diferença ${brl(ult.diferenca)}. A diferença se repetiu nas duas últimas conferências: confira no app do banco se falta alguma transação no sistema (Financeiro › Conciliação › Fechar o mês).`;
          alertar(t, avisoDoVigia("saldo_divergente", todayISO, t, c.id));
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
        const t = `📦 ${lista.length} produto(s) com saldo diferente da soma dos movimentos: ${ex}${lista.length > 3 ? "…" : ""}. Algum caminho gravou estoque sem registrar movimento; confira em Estoque › Variância.`;
        alertar(t, avisoDoVigia("estoque_divergente", todayISO, t));
      }
    } catch (_e) {
      console.warn("[ai-business-monitor] checagem de saldo de estoque falhou (ignorada)");
    }

    // (4) Cota Contora do mês (plano Gratuito = 500 eventos/mês). Alerta em 80%.
    const monthStart = inicioDoMesBR(now);
    const { count: fiscalEvents } = await admin
      .from("issued_fiscal_documents").select("id", { count: "exact", head: true })
      .in("status", ["authorized", "rejected", "cancelled"]).gte("created_at", monthStart);
    if ((fiscalEvents ?? 0) > 400 && await claim(`fiscal_quota_high:${todayISO}`, { n: fiscalEvents })) {
      const t = `📊 Cota fiscal do mês: ~*${fiscalEvents}*/500 eventos usados. Fique de olho para não estourar o plano.`;
      alertar(t, avisoDoVigia("cota_fiscal", todayISO, t));
    }

    // (5) NF-e rejeitadas nas últimas 24h (não deixar uma rejeição passar batida).
    const d1 = new Date(now.getTime() - 864e5).toISOString();
    const { count: rejectedNfe } = await admin
      .from("issued_fiscal_documents").select("id", { count: "exact", head: true })
      .eq("status", "rejected").gte("updated_at", d1);
    if ((rejectedNfe ?? 0) > 0 && await claim(`fiscal_rejected:${todayISO}`, { n: rejectedNfe })) {
      const t = `❌ *${rejectedNfe}* NF-e rejeitada(s) nas últimas 24h. Confira o motivo no histórico e reemita.`;
      // (16/10) Com a voz única em sombra, o portão recebe UM aviso por nota (o acorde de cada uma); sem ela, nada é
      // lido a mais. Erro na leitura das notas = o aviso do dia, como antes.
      const porNota = portao.modo ? await avisosDasNotasRejeitadas(admin, d1) : null;
      alertar(t, ...(porNota && porNota.length ? porNota : [avisoDoVigia("nfe_rejeitada", todayISO, t)]));
    }

    // (6) O resumo das 07:30 que desistiu de chegar (09 e 13/10: WhatsApp fora do ar, a fila
    // desistiu e ninguém soube). Um aviso por telefone e por dia; a fila entrega quando o WhatsApp
    // voltar e para de tentar antes das 20h. Vai para quem ficou sem o resumo, não para a lista
    // do alerta. Falha aqui não derruba os outros sinais.
    let resumoNaoChegou = 0;
    let resumoGuardado = 0;
    try {
      const semResumo = [
        ...telefonesSemResumo(resumosDeHoje).map((phone) => ({ phone, texto: TEXTO_RESUMO_NAO_CHEGOU, motivo: "whatsapp_fora" as const })),
        // (20/10/2026) a manhã que quebrou ANTES de entrar na fila: nenhuma linha do dono depois das 08:00 (antes, ninguém
        // sabia). Com a leitura da fila falhando não se conclui nada (não é "sem linha").
        ...(!resumosErr && dono && !telefonesSemResumo(resumosDeHoje).includes(dono.phone) && manhaSemLinha(resumosDeHoje, dono.phone, now)
          ? [{ phone: dono.phone, texto: TEXTO_MANHA_QUEBROU, motivo: "erro_na_montagem" as const }]
          : []),
      ];
      for (const s of semResumo) {
        const phone = s.phone;
        if (!await claim(`resumo_nao_chegou:${phone}:${todayISO}`, { phone, motivo: s.motivo })) continue;
        const aviso = avisoResumoNaoChegou(todayISO, s.texto, s.motivo);
        // (20/10/2026, P4.5) voz ligada: o dono só recebe se o portão acordar (a volta do WhatsApp pode ter acordado
        // antes: aí vai com o fechamento); portão ilegível = como sempre.
        if (falaPeloPortao(portao, dono, phone)) {
          const fala = await perguntarAoPortao(admin, phone, aviso, now);
          if (!fala.manda) {
            resumoGuardado++;
            continue;
          }
          if (fala.acordou) {
            if (await enfileirarAcorde(admin, { phone, texto: s.texto, avisoId: fala.acordou, agora: now, source: "resumo_nao_chegou" })) resumoNaoChegou++;
            continue;
          }
        }
        const { error: nErr } = await admin.from("whatsapp_send_queue").insert({
          phone_normalized: phone, message: s.texto, source: "resumo_nao_chegou", priority: 2,
          max_attempts: tentativasAteAs20h(now),
        });
        if (nErr) throw nErr;
        resumoNaoChegou++;
        await registrarNoPortao(admin, portao.modo === "sombra" ? "sombra" : null, phone, aviso, now);
      }
    } catch (e) {
      console.warn("[ai-business-monitor] aviso de resumo que não chegou falhou:", (e as Error)?.message ?? e);
    }

    if (alerts.length === 0) {
      return jr({ ok: true, queued: 0, resumo_nao_chegou: resumoNaoChegou, ...(resumoGuardado ? { resumo_guardado: resumoGuardado } : {}), note: "sem sinais novos hoje" });
    }

    const mensagemCom = (linhas: string[]) =>
      [`🔔 *Alerta ${companyName}*`, "", ...linhas, "", "_Me chame aqui se quiser que eu ajude com qualquer um desses._"].join("\n");
    const message = mensagemCom(alerts);
    // (20/10/2026, P4.5) com a voz ligada, o dono não entra nesta mensagem: ele ouve sinal a sinal pelo portão (abaixo)
    const peloPortao = (recipients as any[]).filter((r) => falaPeloPortao(portao, dono, String(r.phone_normalized)));
    const rows = (recipients as any[]).filter((r) => !peloPortao.includes(r))
      .map((r: any) => ({ phone_normalized: String(r.phone_normalized), message, source: "ai_monitor", priority: 5 }));
    let enfileirados = 0;
    if (rows.length) {
      const { data: inserted, error: qErr } = await admin.from("whatsapp_send_queue").insert(rows).select("id");
      if (qErr) throw qErr;
      enfileirados = inserted?.length ?? 0;
    }
    // Voz única em sombra: o alerta já está na fila; registra o que o portão faria com cada sinal (ligada: não registra).
    const noPortao = await registrarParaTodos(admin, portao.modo, recipients.map((r: any) => r.phone_normalized), paraOPortao, now);
    const doDono = peloPortao.length && dono
      ? await falarAoDono(admin, { phone: dono.phone, sinais, mensagem: mensagemCom, agora: now })
      : null;

    return jr({
      ok: true, queued: enfileirados, signals: alerts.length, resumo_nao_chegou: resumoNaoChegou, no_portao: noPortao,
      ...(resumoGuardado ? { resumo_guardado: resumoGuardado } : {}), ...(doDono ? { dono_pelo_portao: doDono } : {}),
    });
  } catch (e: any) {
    console.error("[ai-business-monitor] fatal", e);
    return jr({ error: e?.message || "internal error" }, 500);
  }
});
