// O que identifica o ASSUNTO de cada ação que pede "sim" (aprovação em lote, Fase 1, 29/10/2026).
//
// Para que serve: quando chega uma pendência nova com outra ainda esperando, a da mesma ação e do mesmo assunto é o
// pedido CORRIGIDO ("sem o link", "não, só até quinta") e a anterior é cancelada; a de outro assunto fica guardada e
// volta depois (whatsapp-channel.ts, cancelarPendenciaSubstituida).
//
// POR QUE POR AÇÃO: até 28/10 a regra olhava uma lista fixa de campos (freelancer, numero, os, cliente, telefone…) que
// não tinha os campos que os pedidos de verdade usam — to_phone, client_id, service_order_id, receivable_id, name. Sem
// nenhum deles no pedido, quaisquer duas pendências da mesma ação contavam como "o mesmo pedido corrigido": em 08/10 e
// 24/10 uma mensagem para uma pessoa cancelou a mensagem para OUTRA pessoa. Os campos abaixo saem das chaves que os
// pedidos reais têm em produção (conferido em 29/10/2026).
//
// Regra: ação SEM declaração nunca é "o mesmo assunto" — a anterior fica guardada, nunca é cancelada (guardar custa um
// "não" a mais; cancelar errado perde o pedido calado). Lista vazia = a própria ação é o assunto (um lote novo da
// papelada substitui o anterior).

export const ASSUNTO_DAS_ACOES: Readonly<Record<string, readonly string[]>> = {
  // mensagens e envios: o destino (o texto pode mudar — é a correção)
  send_whatsapp_message: ["to_phone", "client_id"],
  schedule_whatsapp_message: ["phone", "client_id"],
  send_service_order_link: ["service_order_id"],
  send_fiscal_pdf_to_client: ["os", "nota", "cliente", "tipo"],
  send_supplier_quote_request: ["quote_request_id"],
  enviar_lembrete_de_revisao: ["embarcacao", "planos", "toque"],
  followup_send_touch: ["mission_id", "event_id"],
  // dinheiro: a conta
  register_payment: ["receivable_id"],
  register_deposit_and_convert: ["service_order_id"],
  update_payable: ["payable_id"],
  update_receivable: ["receivable_id"],
  anotar_transacao_do_banco: ["quem", "data", "sentido"],
  lancar_no_caixa: ["descricao", "sentido"],
  criar_regra_financeira: ["valor_de_busca", "reconhecer_por"],
  // OS: a OS (e, no item, o serviço)
  cancel_service_order: ["service_order_id"],
  reopen_service_order: ["service_order_id"],
  duplicate_service_order: ["service_order_id"],
  add_service_to_order: ["service_order_id", "service_name"],
  create_purchase_order: ["supplier_id", "service_order_id"],
  // cadastros: o nome
  create_service: ["name"],
  cadastrar_favorecido: ["nome"],
  cadastrar_freelancer: ["nome"],
  // diárias (27/10/2026): "Roberto de 19 a 24" e "Roberto dia 20" são pedidos diferentes
  registrar_diaria: ["freelancer", "data", "data_ate", "dias"],
  registrar_pagamento_freelancer: ["freelancer", "data"],
  // o lote semanal da papelada (secretário): um lote novo substitui o anterior
  aprovar_lote_da_papelada: [],
};

function valorDoAssunto(campo: string, v: unknown): string | null {
  if (v == null || v === "") return null;
  if (typeof v === "object") return JSON.stringify(v);
  const texto = String(v).trim().toLowerCase();
  // o mesmo telefone escrito de dois jeitos ("+55 (47) 9…" e "55479…") é o mesmo destino
  return /phone|telefone/.test(campo) ? texto.replace(/\D/g, "") || null : texto;
}

/**
 * A pendência nova é o MESMO pedido corrigido? Mesma ação, a ação declara o assunto (ASSUNTO_DAS_ACOES) e os campos
 * dele batem. Sem declaração, ou sem nenhum campo de assunto preenchido nas duas, é outro assunto (guardar).
 */
export function mesmoAssunto(
  a: { action_name?: string | null; payload?: unknown },
  b: { action_name?: string | null; payload?: unknown },
): boolean {
  if (!a.action_name || a.action_name !== b.action_name) return false;
  const campos = ASSUNTO_DAS_ACOES[a.action_name];
  if (!campos) return false;
  if (campos.length === 0) return true;
  const chave = (p: unknown) => campos.map((k) => valorDoAssunto(k, (p as Record<string, unknown> | null)?.[k]));
  const ka = chave(a.payload);
  const kb = chave(b.payload);
  if (ka.every((v) => v === null) || kb.every((v) => v === null)) return false;
  return JSON.stringify(ka) === JSON.stringify(kb);
}
