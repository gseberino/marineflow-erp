// A rodada do lembrete ANTES do vencimento (dono, 26/11/2026: "2. A" — o lembrete passa a pedir o "sim" dele).
// Nada sai para o cliente aqui:
//  1. as contas que vencem de HOJE até daqui a N dias (receivable_reminder_days_before, padrão 3), abertas, que não são
//     sinal e sem lembrete (reminder_sent_at vazio: a marca de quem já recebeu e de quem nasceu dispensado, como o saldo
//     que nasce do sinal);
//  2. sem pedido já feito ao dono para a mesma conta e o mesmo vencimento — decidido (aprovado, recusado, executado, falhou)
//     ou ainda esperando resposta: um pedido por conta e vencimento; vencimento novo, pedido novo. O pedido que VENCEU sem
//     resposta (24 h) não conta: a rodada do dia seguinte pergunta de novo, enquanto a conta não vence;
//  3. cada uma passa pela conferência de montarLembreteDeVencimento; a que não passa fica de fora, com o motivo no log;
//  4. cada lembrete vira uma pendência da tool enviar_lembrete_de_vencimento na conversa de WhatsApp do dono, com o
//     retrato; a primeira é perguntada agora, as outras encadeiam no "sim"/"não" (comAProximaPendencia, ai-agent).
// A janela [hoje, hoje + N] (antes era o dia exato): o dia em que o dono estava ocupado, o domingo e o feriado não perdem a
// conta — a rodada seguinte a pega ("vence em 2 dias").
import {
  ACAO_DO_LEMBRETE_DE_VENCIMENTO,
  cartaoDoLembreteDeVencimento,
  type LembreteDeVencimento,
  lembreteRecusado,
  lerPreLeituraDoVencimento,
  montarLembreteDeVencimento,
  retratoDoLembreteDeVencimento,
  somarDias,
} from "../_shared/receivables/lembrete-de-vencimento.ts";
import { CHAVE_DO_RETRATO } from "../_shared/ai/tools/registry.ts";
import { enviarComRegistro, notaDeConfirmacao } from "../_shared/ai/whatsapp-channel.ts";

// deno-lint-ignore no-explicit-any
type Db = any;

/** No máximo 10 pedidos por rodada (o resto fica para a rodada seguinte, que ainda está na janela). */
export const MAX_LEMBRETES_POR_RODADA = 10;

export interface ContaPulada {
  conta: string;
  motivo: string;
}

export interface RodadaDoVencimento {
  propostas: LembreteDeVencimento[];
  pulados: ContaPulada[];
  /** Contas da janela que já tiveram pedido ao dono (não se pergunta de novo). */
  jaPedidas: number;
}

async function ler<T>(consulta: PromiseLike<{ data: unknown; error: unknown }>, oQue: string): Promise<T> {
  const { data, error } = await consulta;
  if (error) throw new Error(`Não consegui ler ${oQue}: ${(error as { message?: string })?.message ?? error}`);
  return data as T;
}

/** As contas da janela, menos as já pedidas, conferidas. Leitura que falha LANÇA (a rodada não pergunta nada). */
export async function proporLembretesDeVencimento(admin: Db, p: { hoje: string; diasAntes: number; agora?: Date }): Promise<RodadaDoVencimento> {
  const ate = somarDias(p.hoje, Math.max(0, p.diasAntes));
  const contas = await ler<Array<{ id: string; due_date: string }>>(
    admin.from("receivables").select("id, due_date")
      .in("status", ["pending", "partially_paid"])
      .is("is_deposit", false)
      .is("reminder_sent_at", null)
      .gte("due_date", p.hoje)
      .lte("due_date", ate)
      .order("due_date", { ascending: true })
      .limit(200),
    "as contas que vencem nos próximos dias",
  ) ?? [];
  if (!contas.length) return { propostas: [], pulados: [], jaPedidas: 0 };

  // Os pedidos já feitos para estas contas, pelo vencimento do retrato. O que venceu sem resposta não conta.
  const pedidos = await ler<Array<{ payload: Record<string, unknown> | null; status: string | null; expires_at: string | null }>>(
    admin.from("ai_operator_pending_actions").select("payload, status, expires_at")
      .eq("action_name", ACAO_DO_LEMBRETE_DE_VENCIMENTO)
      .in("payload->>receivable_id", contas.map((c) => c.id)),
    "os pedidos de lembrete já feitos",
  ) ?? [];
  const agora = (p.agora ?? new Date()).toISOString();
  const jaPedido = new Set<string>();
  for (const x of pedidos) {
    if (x.status === "expired" || (x.status === "pending" && !!x.expires_at && x.expires_at < agora)) continue;
    const conta = String(x.payload?.receivable_id ?? "");
    const venc = String((x.payload?.[CHAVE_DO_RETRATO] as Record<string, unknown> | undefined)?.vencimento ?? "");
    if (conta) jaPedido.add(`${conta}:${venc}`);
  }
  const novas = contas.filter((c) => !jaPedido.has(`${c.id}:${String(c.due_date).slice(0, 10)}`));
  if (!novas.length) return { propostas: [], pulados: [], jaPedidas: contas.length };

  const pre = await lerPreLeituraDoVencimento(admin);
  const propostas: LembreteDeVencimento[] = [];
  const pulados: ContaPulada[] = [];
  for (const c of novas) {
    const l = await montarLembreteDeVencimento(admin, admin, { receivable_id: c.id }, pre);
    if (lembreteRecusado(l)) pulados.push({ conta: c.id, motivo: l.error });
    else propostas.push(l);
  }
  return { propostas: propostas.slice(0, MAX_LEMBRETES_POR_RODADA), pulados, jaPedidas: contas.length - novas.length };
}

/** O título da pendência (o que o sino e o "próximo pedido" mostram). */
export function tituloDoLembreteDeVencimento(l: LembreteDeVencimento): string {
  return `Lembrete de vencimento para ${l.nomeDoCliente}`;
}

/** A pergunta que vai ao dono no WhatsApp (a primeira da leva; as outras encadeiam no "sim"/"não"). */
export function perguntaDoVencimento(l: LembreteDeVencimento, teste: boolean, total: number): string {
  const cabeca = total > 1 ? `Lembretes antes do vencimento para aprovar hoje: ${total}. O primeiro:\n\n` : "";
  // Sem "sim" no exemplo de ajuste: "sim mas troca…" (sem vírgula) é lido como aprovação pelo canal.
  return `${cabeca}Posso mandar este lembrete a ${l.nomeDoCliente}?\n\n${cartaoDoLembreteDeVencimento(l, { teste })}\n\n` +
    `Para mudar a mensagem, diga só o que mudar (ex.: "tira o emoji").${notaDeConfirmacao("high")}`;
}

/** A referência que fica no histórico da conversa: o assistente precisa do id da conta para refazer o pedido. */
export function referenciaDoVencimento(l: LembreteDeVencimento): string {
  return `[lembrete de vencimento — ${ACAO_DO_LEMBRETE_DE_VENCIMENTO}: receivable_id=${l.conta.id}]`;
}

/** Cria as pendências (na ordem), guarda a primeira na sessão, deixa o histórico e pergunta a primeira ao dono. */
export async function pedirSimAoDono(
  admin: Db,
  dono: { id: string; phone: string },
  sessao: string,
  metadata: Record<string, unknown>,
  propostas: LembreteDeVencimento[],
  p: { teste: boolean; conversaLigada: boolean; agora: Date },
): Promise<string[]> {
  const expira = new Date(p.agora.getTime() + 24 * 60 * 60 * 1000).toISOString();
  // Um insert só (tudo ou nada): pendência criada sem a pergunta contaria como "já pedida" e a conta não seria perguntada.
  const { data, error } = await admin.from("ai_operator_pending_actions").insert(propostas.map((l) => ({
    session_id: sessao,
    requested_by_user_id: dono.id,
    action_name: ACAO_DO_LEMBRETE_DE_VENCIMENTO,
    risk_level: "high",
    risk_reason: "Mensagem a cliente em nome da empresa, com valor (lembrete antes do vencimento).",
    title: tituloDoLembreteDeVencimento(l),
    summary: cartaoDoLembreteDeVencimento(l, { teste: p.teste }),
    payload: { receivable_id: l.conta.id, [CHAVE_DO_RETRATO]: retratoDoLembreteDeVencimento(l) },
    status: "pending",
    expires_at: expira,
  }))).select("id");
  const ids = ((data ?? []) as Array<{ id: string }>).map((x) => x.id);
  if (error || ids.length !== propostas.length) throw new Error(`Falha ao criar os pedidos do lembrete: ${error?.message ?? "sem id"}`);

  const primeira = propostas[0];
  const pergunta = perguntaDoVencimento(primeira, p.teste, propostas.length);
  const { error: eS } = await admin.from("ai_operator_sessions").update({
    metadata: { ...metadata, pending_confirm_action_id: ids[0], pin_attempts: 0, pendencia_herdada: false },
    last_activity_at: p.agora.toISOString(),
  }).eq("id", sessao);
  if (eS) throw new Error(`Falha ao guardar o pedido na conversa do dono: ${eS.message}`);
  // No histórico, com os ids: se o dono pedir ajuste, o assistente refaz o pedido. Em par (a janela do histórico começa
  // numa fala "user"); a marca 🤖 diz que não foi o dono que escreveu. Horários explícitos para a ordem não empatar.
  const t0 = p.agora.getTime();
  const { error: eH } = await admin.from("ai_operator_messages").insert([
    {
      session_id: sessao, role: "user", source: "whatsapp", created_at: new Date(t0).toISOString(),
      content: `🤖 Lembretes antes do vencimento (aviso automático da rotina receivable-reminders): ${propostas.length} para aprovar.`,
    },
    {
      session_id: sessao, role: "assistant", source: "whatsapp", created_at: new Date(t0 + 1).toISOString(),
      content: `${pergunta}\n\n${propostas.map(referenciaDoVencimento).join("\n")}`,
    },
  ]);
  if (eH) console.error("[receivable-reminders] histórico não gravado", eH.message);
  // A pergunta é a confirmação de uma pendência do assistente: entra no registro como tal (o "sim"/"não" vai para ela).
  await enviarComRegistro(
    admin, dono.phone, pergunta,
    { acao: "registrar", tipo: "confirmacao", referencia_id: ids[0], titulo: tituloDoLembreteDeVencimento(primeira) },
    { ligada: p.conversaLigada, origem: "assistente" },
  );
  await admin.from("ai_operator_audit").insert({
    session_id: sessao, actor_user_id: dono.id, actor_kind: "system", event_type: "lembretes_de_vencimento:propostos",
    event_category: "data", payload: { pendencias: ids, contas: propostas.map((l) => l.conta.id) },
  });
  return ids;
}
