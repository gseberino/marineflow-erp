// Quais ferramentas NÃO vão para o WhatsApp.
//
// POR QUE EXISTE: o prefixo enviado em toda chamada é de ~67,6k tokens, e 48k disso são as
// definições de 188 ferramentas. Cada ferramenta custa ~256 tokens só por existir — a maior
// parte overhead do formato JSON, que nenhuma reescrita alcança (a Fase 5 tentou e rendeu 370
// tokens). O único jeito de encolher o bloco é mandar menos ferramentas.
//
// REGRA INVIOLÁVEL — a lista tem que ser ESTÁVEL. As ferramentas são renderizadas ANTES do
// system prompt, então elas fazem parte do prefixo cacheado: um conjunto que varia por mensagem
// dá cache miss em 100% das chamadas. Foi por isso que o roteador de intenção
// (`ai_intent_router`, ai-agent/index.ts) nunca foi ligado — ele dobraria o custo. Esta lista é
// fixa por canal, então o WhatsApp passa a ter o seu próprio prefixo, também cacheável.
//
// CUSTO ACEITO: painel e WhatsApp deixam de compartilhar um único cache e passam a ter dois.
// Cada um se paga com poucas leituras; em compensação, toda chamada de WhatsApp fica menor.
//
// CRITÉRIO DE ENTRADA NA LISTA — as duas condições, não uma:
//   1. zero uso em 60 dias de auditoria (ai_operator_audit), E
//   2. inequivocamente trabalho de tela grande: relatório que se lê, lote que se confere,
//      cadastro estrutural, configuração.
//
// O QUE FICOU DE FORA DE PROPÓSITO, embora tenha zero uso:
//   - roteiro de execução (start/complete/block/skip_service_order_step...): o system prompt diz
//     que "o técnico fala por WhatsApp, muitas vezes por áudio" — são exatamente as ferramentas
//     que o canal existe para servir.
//   - levantamento (start_service_survey, record_survey_answer...): o prompt manda usar
//     mode='remoto' para "resolver o levantamento no WhatsApp".
//   - fiscal: emitir nota pelo celular é raro, mas consultar se a nota saiu não é — e o dono
//     pergunta isso pelo WhatsApp.
// Cortar qualquer um desses economizaria token e tiraria uma capacidade real do canal.

/** Ferramentas ausentes do WhatsApp. Ordem alfabética — nomes soltos aqui não quebram nada. */
export const FORA_DO_WHATSAPP: ReadonlySet<string> = new Set([
  // — Relatórios e BI: números que se lê numa tela, não numa conversa —
  "get_financial_dre",
  "get_margin_by_category",
  "get_revenue_by_brand",
  "get_top_clients",
  "resultado_do_periodo",

  // — Conciliação bancária em lote: conferência linha a linha contra o extrato —
  // (sugerir_conciliacao, conciliar_transacao e listar_transacoes_pendentes FICAM: têm uso real)
  "analisar_extrato_e_propor_lancamentos",
  "aprovar_propostas_de_lancamento",
  "recusar_propostas_de_lancamento",
  "listar_propostas_de_lancamento",
  "cadastrar_favorecido",
  "listar_favorecidos",

  // — Produto composto e produção: cadastro estrutural do catálogo —
  "create_composed_product",
  "produce_composed_product",
  "get_product_components",
  "apply_service_material_kit",

  // — Autonomia e automação: configuração do próprio agente —
  "set_tool_autonomy",
  "get_autonomy_settings",
  "get_autonomy_report",
  "confirm_automation",
  "propose_automation",

  // — Rascunho de roteiro (NÃO a execução, que fica) —
  "save_drafted_route_steps",
  "review_ai_step",
]);

/**
 * Filtra as ferramentas do canal. Determinístico: mesmo canal, mesma lista, sempre — é o que
 * mantém o prefixo cacheável. Qualquer canal que não seja "whatsapp" recebe tudo.
 */
export function filtrarPorCanal<T extends { name: string }>(tools: T[], canal: string | undefined): T[] {
  if (canal !== "whatsapp") return tools;
  return tools.filter((t) => !FORA_DO_WHATSAPP.has(t.name));
}
