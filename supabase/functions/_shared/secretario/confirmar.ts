// Abre a confirmação de um comando do secretário (Passo 5, 16/10/2026: o *lote* da papelada) como uma pendência do
// assistente — o MESMO mecanismo dos lembretes de revisão (lembretes-de-revisao/index.ts, proporAoDono):
//   1. ai_operator_pending_actions (status pending, expira);
//   2. a sessão do WhatsApp aponta para ela (pending_confirm_action_id, PIN zerado, não herdada) — é assim que a camada
//      de confirmação do ai-agent casa o "sim <PIN>" do dono, ANTES de qualquer comando;
//   3. a pendência anterior da conversa: cancelada se é o mesmo pedido (outro lote), guardada para voltar depois se
//      é outro assunto (cancelarPendenciaSubstituida, 27/10/2026);
//   4. o par no histórico da conversa e a pergunta ativa registrada (enviarComRegistro), para o desempate com o
//      comprovante continuar certo;
//   5. a auditoria.
// Nada é executado aqui: quem executa é o "sim", pelo caminho de sempre (approveAndExecutePendingAction).

import { cancelarPendenciaSubstituida, enviarComRegistro } from "../ai/whatsapp-channel.ts";
import type { PendenciaDoSecretario } from "./papelada.ts";

// deno-lint-ignore no-explicit-any
type Admin = any;

export interface AbrirConfirmacao {
  sessionId: string;
  // deno-lint-ignore no-explicit-any
  metadata: Record<string, any>;
  userId: string;
  phone: string;
  /** o que o dono escreveu ("lote sem 3") */
  pedido: string;
  texto: string;
  pendencia: PendenciaDoSecretario;
  /** a conversa dos comprovantes está ligada (registra a pergunta ativa) */
  ligada: boolean;
  agora?: Date;
  /** para teste: o envio (padrão enviarComRegistro) */
  enviar?: typeof enviarComRegistro;
}

/** Devolve o id da pendência aberta, ou null (falhou: o dono recebe o texto e o aviso de tentar de novo). */
export async function abrirConfirmacaoDoSecretario(admin: Admin, p: AbrirConfirmacao): Promise<string | null> {
  const agora = p.agora ?? new Date();
  const enviar = p.enviar ?? enviarComRegistro;
  const { data, error } = await admin.from("ai_operator_pending_actions").insert({
    session_id: p.sessionId,
    requested_by_user_id: p.userId,
    action_name: p.pendencia.action_name,
    risk_level: p.pendencia.risk_level,
    risk_reason: p.pendencia.risk_reason,
    title: p.pendencia.title,
    summary: p.pendencia.summary,
    payload: p.pendencia.payload,
    status: "pending",
    expires_at: new Date(agora.getTime() + p.pendencia.minutos * 60_000).toISOString(),
  }).select("id").single();
  if (error || !data?.id) {
    console.warn(JSON.stringify({ fn: "secretario", evento: "confirmacao_nao_aberta", codigo: String(error?.code ?? "sem_id") }));
    await enviar(admin, p.phone, `${p.texto}\n\n(Não consegui abrir a confirmação agora: escreva *lote* de novo daqui a pouco.)`, null, { ligada: false });
    return null;
  }
  const id = String(data.id);
  const nova = { ...p.metadata, pending_confirm_action_id: id, pin_attempts: 0, pendencia_herdada: false };
  const nota = await cancelarPendenciaSubstituida(admin, p.metadata, nova, p.userId);
  await admin.from("ai_operator_sessions").update({ metadata: nova, last_activity_at: agora.toISOString() }).eq("id", p.sessionId);
  try {
    await admin.from("ai_operator_messages").insert([
      { session_id: p.sessionId, role: "user", content: p.pedido, source: "whatsapp", created_at: agora.toISOString() },
      { session_id: p.sessionId, role: "assistant", content: p.texto, source: "whatsapp", created_at: new Date(agora.getTime() + 1).toISOString() },
    ]);
  } catch (e) {
    console.warn(JSON.stringify({ fn: "secretario", evento: "historico_da_confirmacao", codigo: (e as Error)?.name ?? "erro" }));
  }
  await enviar(admin, p.phone, `${p.texto}${nota}`,
    { acao: "registrar", tipo: "confirmacao", referencia_id: id, titulo: p.pendencia.title }, { ligada: p.ligada });
  try {
    await admin.from("ai_operator_audit").insert({
      session_id: p.sessionId, pending_action_id: id, actor_user_id: p.userId, actor_kind: "system",
      event_type: `secretario:${p.pendencia.action_name}:proposto`, event_category: "data",
      payload: { channel: "whatsapp", args: p.pendencia.payload },
    });
  } catch {
    /* auditoria é best-effort */
  }
  return id;
}
