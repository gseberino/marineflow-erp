// "Me acorde se" — a coleta (secretário, Passo 4, P4.2, 16/10/2026). Spec: D:/IA-HBR/comprovantes-bancada/spec/
// spec-secretario-uma-voz.md §3. Roda na rodada do acompanhar-conversas (a cada 15 min: D10, sem cron novo), TODOS os
// dias das 08h às 20h (decisão do dono, 16/10/2026 — no domingo só ele roda: rodadaDeAgora), só com
// app_settings.voz_unica em sombra/ligado (desligado = esta função nem é chamada).
//
// Lê quem espera resposta (whatsapp_esperando_resposta, a mesma lista do resumo, sem "ok/obrigado"), as recebidas de
// HOJE e as saídas dos últimos 7 dias desses telefones, e os orçamentos abertos de quem é cliente. As regras e os
// textos são puros (_shared/uma-voz/acorde.ts). Cada disparo é REGISTRADO no portão (aviso_registrar, fonte
// 'cliente', assunto contato:<telefone>) com o texto exato que sairia e, nos dados, o cartão pronto (a pendência
// send_service_order_link em PDF que o *sim* executaria).
//
// EM SOMBRA NADA É ENVIADO, nada vira pendência, nada vai ao histórico do assistente.
// (20/10/2026, P4.5) Com a voz única LIGADA de verdade (a manhã nova e o fechamento ligado no ar), quem recebe
// 'acordar' ENVIA ao dono (enviarAcordeDeCliente): com o cartão — orçamento para mandar, o dono livre e depois das
// 09:30 — a mensagem é a própria confirmação (pendência send_service_order_link em PDF, alto risco: *sim <PIN>*,
// criada como a dos lembretes de revisão: pendência + pending_confirm_action_id + par 🤖 no histórico +
// enviarComRegistro); sem cartão, o texto vai pela fila (chave aviso:<id>) com o par 🤖 no histórico (o texto livre
// "manda a proposta pro X" funciona). O que não acordou (guardado, repetido) não sai. Envio que falhou = reabre.
// Nunca lança: erro = a contagem com o motivo, e a rodada do acompanhamento segue.

import { ultimoDiaDaValidade } from "../_shared/pdf/documento.ts";
import { diaBR } from "../_shared/pdf/datas.ts";
import { brl } from "../_shared/secretario/base.ts";
import { ehClienteGenerico } from "../_shared/secretario/palavras.ts";
import { expectedDepositAmount } from "../_shared/banking/quote-deposit.ts";
import { donoOcupadoParaPerguntar, enviarComRegistro, resolveOrCreateWhatsAppSession } from "../_shared/ai/whatsapp-channel.ts";
import { telefoneLegivel } from "../_shared/ai/tools/agendamento.ts";
import { hashCurto } from "../_shared/whatsapp/idempotencia.ts";
import {
  type AcordeDeCliente, avisoDoCliente, type ConversaDoAcorde, disparosDaConversa, mensagemNovaEFatoNovo, type OrcamentoAberto,
  textoDoAcordeDeCliente,
} from "../_shared/uma-voz/acorde.ts";
import { acordeComCartao, podeAcordar } from "../_shared/uma-voz/janela.ts";
import { horaDeAvisar } from "../_shared/ai/acompanhar.ts";
import type { PortaoDaRodada } from "../_shared/uma-voz/registrar.ts";
import { acordesDeHojeDoAssunto, enfileirarAcorde, reabrirNoPortao, registrarNoPortao } from "../_shared/uma-voz/registrar.ts";
import type { Dono } from "../_shared/whatsapp/dono.ts";

// deno-lint-ignore no-explicit-any
type Db = any;

/** O título da pendência do cartão: o mesmo que o assistente dá a send_service_order_link (agent.ts, tituloDaAcao). */
export const TITULO_DO_CARTAO = "Enviar orçamento/OS ao cliente (WhatsApp)";

/**
 * O payload da pendência do cartão (puro): o pedido de send_service_order_link em PDF com a legenda pronta, quem pediu
 * (o dono, admin — a tool revalida o cargo de quem pediu) e o retrato do que o dono aprova (o telefone do cadastro em
 * hash e o total: mudou até o *sim*, não envia). As mesmas chaves que o runAgentLoop grava (_solicitante, _retrato) e
 * o mesmo retrato de retratoDoEnvio (_shared/ai/tools/whatsapp.ts — o teste compara os dois).
 */
export function payloadDoCartao(p: {
  cartao: NonNullable<AcordeDeCliente["cartao"]>;
  dono: Dono;
  telefoneDoCadastro: string | null;
  total: number;
}): Record<string, unknown> {
  return {
    service_order_id: p.cartao.service_order_id,
    formato: "pdf",
    custom_message: p.cartao.legenda,
    _solicitante: { user_id: p.dono.id, nome: null, cargo: "admin" },
    _retrato: { telefone: hashCurto(String(p.telefoneDoCadastro ?? "").replace(/\D/g, "")), total: Number(p.total) || 0 },
  };
}

/** O resumo da pendência do cartão (o painel e a reapresentação mostram): para quem, qual número, quanto e a legenda. */
export function resumoDoCartao(p: { cliente: string | null; telefoneDoCadastro: string | null; numero: string; total: number; legenda: string }): string {
  const d = String(p.telefoneDoCadastro ?? "").replace(/\D/g, "");
  return [
    `Cliente: *${p.cliente || "—"}*`,
    d ? `WhatsApp: ${d.length >= 4 ? `••••${d.slice(-4)}` : "••••"} (do cadastro)` : "WhatsApp: ⚠️ cliente sem WhatsApp/telefone no cadastro — o envio vai falhar",
    `Orçamento: *${p.numero}* — Total *${brl(p.total)}*`,
    "Formato: *só o PDF*, sem link (o arquivo com preço e PIX vai na conversa)",
    `Legenda: "${p.legenda}"`,
    "Pedido por: *aviso automático* (me acorde se)",
  ].join("\n");
}

/** Cria a pendência do cartão na conversa do dono. null = não deu (o acorde vai sem cartão). Nunca lança. */
async function criarPendenciaDoCartao(admin: Db, p: {
  sessao: string;
  dono: Dono;
  cartao: NonNullable<AcordeDeCliente["cartao"]>;
}): Promise<string | null> {
  try {
    const { data: so, error } = await admin.from("service_orders").select("id, service_order_number, client_id, grand_total, status")
      .eq("id", p.cartao.service_order_id).maybeSingle();
    if (error || !so || so.status === "cancelled") return null;
    const { data: c } = so.client_id
      ? await admin.from("clients").select("name, whatsapp, phone").eq("id", so.client_id).maybeSingle()
      : { data: null };
    const telefone = c?.whatsapp || c?.phone || null;
    if (!telefone) return null; // a tool recusaria: melhor sem cartão
    const { data: pend, error: pErr } = await admin.from("ai_operator_pending_actions").insert({
      session_id: p.sessao,
      requested_by_user_id: p.dono.id,
      action_name: "send_service_order_link",
      risk_level: "high",
      title: TITULO_DO_CARTAO,
      summary: resumoDoCartao({ cliente: c?.name ?? null, telefoneDoCadastro: telefone, numero: so.service_order_number, total: Number(so.grand_total) || 0, legenda: p.cartao.legenda }),
      payload: payloadDoCartao({ cartao: p.cartao, dono: p.dono, telefoneDoCadastro: telefone, total: Number(so.grand_total) || 0 }),
      status: "pending",
      expires_at: new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString(),
    }).select("id").single();
    if (pErr || !pend?.id) return null;
    return String(pend.id);
  } catch {
    return null;
  }
}

/**
 * (20/10/2026, P4.5) Envia o acorde que o portão liberou. Com cartão (o texto tem a linha do *sim <PIN>*): a pendência,
 * a conversa apontando para ela, o par 🤖 no histórico e o envio com registro (a pergunta entra no registro único). Sem
 * cartão (ou a pendência não nasceu): o texto sem a linha do sim, pela fila (chave aviso:<id>; se a fila desistir, a
 * próxima mensagem fixa leva), e o par 🤖 no histórico. ok=false = não saiu (quem chama reabre). Nunca lança.
 */
export async function enviarAcordeDeCliente(admin: Db, p: {
  dono: Dono;
  nome: string;
  gatilho: string;
  acorde: AcordeDeCliente;
  /** o mesmo acorde sem a linha do sim (quando a pendência não nasce) */
  semCartao: AcordeDeCliente;
  avisoId: string;
  agora: Date;
  conversaLigada: boolean;
}): Promise<{ ok: boolean; cartao: boolean; pendencia: string | null }> {
  try {
    const sessao = await resolveOrCreateWhatsAppSession(admin, p.dono.phone, p.dono.id);
    const t0 = Date.now();
    const historico = (texto: string, nota = "") =>
      admin.from("ai_operator_messages").insert([
        { session_id: sessao, role: "user", source: "whatsapp", created_at: new Date(t0).toISOString(), content: `🤖 Me acorde se (aviso automático do acompanhar-conversas): ${p.nome} — ${p.gatilho}.` },
        { session_id: sessao, role: "assistant", source: "whatsapp", created_at: new Date(t0 + 1).toISOString(), content: `${texto}${nota}` },
      ]);
    if (p.acorde.cartao) {
      const pend = await criarPendenciaDoCartao(admin, { sessao, dono: p.dono, cartao: p.acorde.cartao });
      if (pend) {
        const { data: s } = await admin.from("ai_operator_sessions").select("metadata").eq("id", sessao).maybeSingle();
        await admin.from("ai_operator_sessions").update({
          metadata: { ...((s?.metadata ?? {}) as Record<string, unknown>), pending_confirm_action_id: pend, pin_attempts: 0, pendencia_herdada: false },
          last_activity_at: new Date().toISOString(),
        }).eq("id", sessao);
        const { error: hErr } = await historico(p.acorde.texto, `\n\n(pendência ${pend}: send_service_order_link do ${p.acorde.cartao.numero}, formato pdf)`);
        if (hErr) console.warn("[acompanhar-conversas] acorde fora do histórico:", hErr.message);
        await enviarComRegistro(admin, p.dono.phone, p.acorde.texto,
          { acao: "registrar", tipo: "confirmacao", referencia_id: pend, titulo: TITULO_DO_CARTAO },
          { ligada: p.conversaLigada, origem: "acompanhar_conversa" });
        return { ok: true, cartao: true, pendencia: pend };
      }
    }
    const texto = p.acorde.cartao ? p.semCartao.texto : p.acorde.texto;
    if (!await enfileirarAcorde(admin, { phone: p.dono.phone, texto, avisoId: p.avisoId, agora: p.agora, source: "me_acorde" })) {
      return { ok: false, cartao: false, pendencia: null };
    }
    const { error: hErr } = await historico(texto);
    if (hErr) console.warn("[acompanhar-conversas] acorde fora do histórico:", hErr.message);
    return { ok: true, cartao: false, pendencia: null };
  } catch (e) {
    console.warn("[acompanhar-conversas] acorde não enviado:", (e as Error)?.message ?? e);
    return { ok: false, cartao: false, pendencia: null };
  }
}

/**
 * (16/10/2026, decisão do dono) O que a rodada de 15 min faz agora: os avisos de acompanhamento e a detecção de promessas
 * seguem seg–sáb, 08–20h (horaDeAvisar, como sempre); o "me acorde se" vale TODOS os dias, 08–20h (podeAcordar, a mesma
 * janela do portão). O cron já roda a cada 15 min todos os dias: no domingo só o detector age.
 */
export function rodadaDeAgora(agora: Date): { avisos: boolean; acordes: boolean } {
  return { avisos: horaDeAvisar(agora), acordes: podeAcordar(agora) };
}

/** Os mesmos 8 últimos dígitos da whatsapp_esperando_resposta (cliente pelo telefone do cadastro). */
function final8(s: unknown): string | null {
  const d = String(s ?? "").replace(/\D/g, "");
  return d.length >= 8 ? d.slice(-8) : null;
}

/** Rascunho mais velho que isto está abandonado (a mesma régua da manhã, REGRAS.rascunhoMaxDias). */
const RASCUNHO_MAX_DIAS = 30;

/** Os orçamentos abertos de cada cliente, com o sinal (a conta do PDF) e a validade. */
export async function orcamentosAbertos(
  admin: Db, clientes: string[], settings: Record<string, string>, agora: Date,
): Promise<Map<string, OrcamentoAberto[]>> {
  const porCliente = new Map<string, OrcamentoAberto[]>();
  if (!clientes.length) return porCliente;
  const [{ data: orcs, error }, { data: presets }] = await Promise.all([
    admin.from("service_orders")
      .select(`id, service_order_number, quote_status, grand_total, client_id, created_at, updated_at, quote_validity_days,
               quote_validity_date, labor_cost_total, parts_cost_total, operational_cost_total, travel_cost_total,
               subcontract_cost_total, is_travel_billable, discount_amount, tax_amount, custom_payment_installments,
               payment_conditions, payment_condition_presets(label, installments)`)
      .eq("status", "draft").in("quote_status", ["draft", "sent", "awaiting_approval", "awaiting_deposit"]).in("client_id", clientes)
      .order("updated_at", { ascending: false }).limit(100),
    admin.from("payment_condition_presets").select("label, installments"),
  ]);
  if (error) throw error;
  const presetPorLabel = new Map<string, unknown>(((presets ?? []) as Array<{ label: string; installments: unknown }>).map((p) => [String(p.label), p.installments]));
  const pct = Number(settings.quote_deposit_percentage ?? 30) || 30;
  for (const q of (orcs ?? []) as Array<Record<string, unknown>>) {
    const status = String(q.quote_status);
    if (status === "draft" && agora.getTime() - Date.parse(String(q.created_at)) > RASCUNHO_MAX_DIAS * 86_400_000) continue;
    // deno-lint-ignore no-explicit-any
    const preset = (q.payment_condition_presets as any)?.installments ?? presetPorLabel.get(String(q.payment_conditions ?? ""));
    const parcelas = Array.isArray(preset) ? preset : Array.isArray(q.custom_payment_installments) ? q.custom_payment_installments : null;
    const sinal = expectedDepositAmount(q as never, parcelas as never, pct);
    const lista = porCliente.get(String(q.client_id)) ?? [];
    lista.push({
      id: String(q.id),
      numero: String(q.service_order_number || "Orçamento"),
      valor: Number(q.grand_total || 0),
      status,
      mexido_em: String(q.updated_at),
      sinal: sinal?.amount ?? null,
      // o mesmo "até" do PDF; aguardando sinal e rascunho não vencem
      validade: status === "awaiting_deposit" || status === "draft"
        ? null
        : ultimoDiaDaValidade(q as { created_at?: string | null; quote_validity_date?: string | null; quote_validity_days?: unknown }, settings),
    });
    porCliente.set(String(q.client_id), lista);
  }
  return porCliente;
}

export interface ResultadoDosAcordes {
  conversas: number;
  disparos: number;
  acordaria: number;
  guardados: number;
  repetidos: number;
  outros: number;
  /** (20/10/2026) voz ligada: os acordes que saíram (com cartão entre eles) e os que voltaram a guardado */
  enviados?: number;
  com_cartao?: number;
  reabertos?: number;
  erro?: string;
}

/** A rodada do detector. Nunca lança. */
export async function vigiarAcordes(admin: Db, p: {
  agora: Date;
  dono: Dono;
  portao: PortaoDaRodada;
  settings: Record<string, string>;
  internos: Set<string>;
  conversaLigada: boolean;
}): Promise<ResultadoDosAcordes> {
  const r: ResultadoDosAcordes = { conversas: 0, disparos: 0, acordaria: 0, guardados: 0, repetidos: 0, outros: 0 };
  const modo = p.portao.modo;
  if (!modo) return r;
  try {
    const { agora } = p;
    const hoje = diaBR(agora);
    const inicioDoDia = new Date(`${hoje}T00:00:00-03:00`).toISOString();
    const seteDias = new Date(agora.getTime() - 7 * 86_400_000).toISOString();

    // 1. quem espera resposta e escreveu hoje (fora a equipe e os fornecedores)
    const { data: lista, error } = await admin.rpc("whatsapp_esperando_resposta", { _since: seteDias, _limit: 60 });
    if (error) throw error;
    const vivos = ((lista ?? []) as Array<Record<string, unknown>>).filter((w) =>
      !w.encerrada && w.categoria !== "fornecedor" && !p.internos.has(String(w.phone)) &&
      Date.parse(String(w.last_inbound_at)) >= Date.parse(inicioDoDia)
    );
    r.conversas = vivos.length;
    if (!vivos.length) return r;
    const fones = vivos.map((w) => String(w.phone));

    // 2. as recebidas de hoje e as saídas de 7 dias (a "conversa de todo dia")
    const [rec, env] = await Promise.all([
      admin.from("whatsapp_messages").select("phone_normalized, body, occurred_at, client_id")
        .eq("direction", "inbound").in("phone_normalized", fones).gte("occurred_at", inicioDoDia)
        .order("occurred_at", { ascending: true }).limit(1000),
      admin.from("whatsapp_messages").select("phone_normalized, occurred_at")
        .eq("direction", "outbound").in("phone_normalized", fones).gte("occurred_at", seteDias).limit(3000),
    ]);
    if (rec.error) throw rec.error;
    if (env.error) throw env.error;
    const recebidas = new Map<string, Array<{ em: string; body: string | null }>>();
    const clienteDaMensagem = new Map<string, string>();
    for (const m of (rec.data ?? []) as Array<{ phone_normalized: string; body: string | null; occurred_at: string; client_id: string | null }>) {
      recebidas.set(m.phone_normalized, [...(recebidas.get(m.phone_normalized) ?? []), { em: m.occurred_at, body: m.body }]);
      if (m.client_id) clienteDaMensagem.set(m.phone_normalized, m.client_id);
    }
    const dias = new Map<string, Set<string>>();
    const ultimaSaida = new Map<string, number>();
    for (const m of (env.data ?? []) as Array<{ phone_normalized: string; occurred_at: string }>) {
      dias.set(m.phone_normalized, (dias.get(m.phone_normalized) ?? new Set()).add(diaBR(new Date(m.occurred_at))));
      const t = Date.parse(m.occurred_at);
      if (!ultimaSaida.has(m.phone_normalized) || ultimaSaida.get(m.phone_normalized)! < t) ultimaSaida.set(m.phone_normalized, t);
    }

    // 3. as conversas e os disparos (puros)
    const conversas: ConversaDoAcorde[] = vivos.map((w) => {
      const phone = String(w.phone);
      const nome = String(w.contato || phone);
      const generico = ehClienteGenerico(nome);
      const saida = ultimaSaida.get(phone) ?? (w.last_outbound_at ? Date.parse(String(w.last_outbound_at)) : NaN);
      return {
        phone, nome,
        cliente: w.categoria === "cliente" && !generico,
        fornecedor: w.categoria === "fornecedor",
        client_id: clienteDaMensagem.get(phone) ?? null,
        ultimaSaidaEm: Number.isNaN(saida) ? null : new Date(saida).toISOString(),
        recebidas: recebidas.get(phone) ?? [],
        diasComMensagemSua: dias.get(phone)?.size ?? 0,
      };
    });
    const comDisparo = conversas.map((c) => ({ c, ds: disparosDaConversa(c, agora, p.portao.regras.acorde_espera_min) }))
      .filter((x) => x.ds.length > 0);
    r.disparos = comDisparo.reduce((s, x) => s + x.ds.length, 0);
    if (!comDisparo.length) return r;

    // 4. o cliente pelo telefone do cadastro (quando a mensagem não traz o vínculo) e os orçamentos abertos
    const semVinculo = comDisparo.filter((x) => x.c.cliente && !x.c.client_id);
    if (semVinculo.length) {
      const { data: cls } = await admin.from("clients").select("id, phone, whatsapp").eq("active", true).limit(3000);
      const porFinal = new Map<string, string>();
      for (const c of (cls ?? []) as Array<Record<string, unknown>>) {
        for (const f of [final8(c.whatsapp), final8(c.phone)]) if (f && !porFinal.has(f)) porFinal.set(f, String(c.id));
      }
      for (const x of semVinculo) x.c.client_id = porFinal.get(final8(x.c.phone) ?? "") ?? null;
    }
    const clientes = [...new Set(comDisparo.map((x) => x.c.client_id).filter((id): id is string => !!id))];
    const orcamentos = await orcamentosAbertos(admin, clientes, p.settings, agora);

    // 5. o dono está livre para um cartão? (só se algum disparo pode ter cartão: depois das 09:30, com orçamento)
    let donoLivre: boolean | null = null;
    const precisaSaber = acordeComCartao(agora) &&
      comDisparo.some((x) => x.ds.some((d) => d.tipo === "pressa") && (orcamentos.get(x.c.client_id ?? "")?.length ?? 0) > 0);
    if (precisaSaber) {
      try {
        // só LÊ a conversa aberta (a sombra não cria sessão: resolveOrCreateWhatsAppSession gravaria uma nova)
        const { data: s, error: sErr } = await admin.from("ai_operator_sessions").select("metadata")
          .eq("channel", "whatsapp").eq("external_thread_key", p.dono.phone).eq("status", "open")
          .order("last_activity_at", { ascending: false }).limit(1).maybeSingle();
        if (sErr) throw sErr;
        donoLivre = !(await donoOcupadoParaPerguntar(admin, { phone: p.dono.phone, metadata: s?.metadata ?? {}, ligada: p.conversaLigada, agora })).ocupado;
      } catch {
        donoLivre = false; // na dúvida, sem cartão (só a informação)
      }
    }

    // 6. registra cada disparo no portão, com o texto que sairia; (20/10/2026) ligada, o que acordou SAI
    for (const { c, ds } of comDisparo) {
      const orcs = c.client_id ? orcamentos.get(c.client_id) ?? [] : [];
      for (const d of ds) {
        const acordes = await acordesDeHojeDoAssunto(admin, { phone: p.dono.phone, modo, dia: hoje, assunto: `contato:${c.phone}` });
        const novoFato = acordes !== null && mensagemNovaEFatoNovo(p.portao.regras, d.mensagem.em, acordes);
        const montar = (podeCartao: boolean) => textoDoAcordeDeCliente({
          nome: c.nome, disparo: d, orcamentos: orcs,
          telefone: p.portao.regras.telefone_no_aviso ? telefoneLegivel(c.phone) : null,
          podeCartao, agora,
        });
        const acorde = montar(donoLivre === true);
        const resp = await registrarNoPortao(admin, modo, p.dono.phone,
          avisoDoCliente({ conversa: c, disparo: d, orcamentos: orcs, acorde, regras: p.portao.regras, novoFato }), agora);
        if (resp?.decisao === "acordar") r.acordaria++;
        else if (resp?.decisao === "guardar") r.guardados++;
        else if (resp?.decisao === "repetido") r.repetidos++;
        else r.outros++;
        // Ligada: só o 'acordar' sai (sem resposta do portão o detector não manda nada — como antes dele existir). O
        // cartão vai só se o portão também o liberou (depois das 09:30).
        if (modo === "ligado" && resp?.decisao === "acordar" && typeof resp.id === "string") {
          const semCartao = montar(false);
          const envio = await enviarAcordeDeCliente(admin, {
            dono: p.dono, nome: c.nome, gatilho: d.gatilho, acorde: resp.cartao === true ? acorde : semCartao, semCartao,
            avisoId: resp.id, agora, conversaLigada: p.conversaLigada,
          });
          if (envio.ok) {
            r.enviados = (r.enviados ?? 0) + 1;
            if (envio.cartao) {
              r.com_cartao = (r.com_cartao ?? 0) + 1;
              donoLivre = false; // um cartão por vez: o próximo acorde da rodada vai só com a informação
            }
          } else if (await reabrirNoPortao(admin, resp.id, agora)) {
            r.reabertos = (r.reabertos ?? 0) + 1;
          }
        }
      }
    }
    return r;
  } catch (e) {
    console.warn("[acompanhar-conversas] me acorde se (sombra) falhou:", (e as Error)?.message ?? e);
    return { ...r, erro: String((e as { code?: unknown })?.code ?? (e as Error)?.name ?? "erro") };
  }
}
