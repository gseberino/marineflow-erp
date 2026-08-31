// Janela de histórico da conversa — qual pedaço da sessão volta para o modelo.
//
// O BUG QUE ISTO CORRIGE (NOVO-agente-04): o histórico era lido com
// `.order("created_at", { ascending: true }).limit(30)`. Ascendente + limite não são as 30 últimas
// mensagens: são as 30 PRIMEIRAS. A janela congelava depois do primeiro turno grande e nunca mais
// avançava. Medido na sessão 3ac5b84a (31/08/2026): o agente enxergava até 12:43 de uma conversa
// que foi até 14:45 — 206 das 236 mensagens nunca voltaram ao modelo, e o orçamento que ele deveria
// corrigir nasceu na linha 36, fora da janela. A cada "continue" ele relia o pedido ORIGINAL e o
// executava de novo: seis orçamentos para um pedido só.
//
// POR QUE NÃO BASTA INVERTER: pegar as N mais recentes corta a conversa num ponto arbitrário, e a
// API da Anthropic rejeita (400) dois formatos:
//   - um `tool_result` cujo `tool_use` ficou fora da janela (órfão no INÍCIO);
//   - um `tool_use` cujo `tool_result` ficou fora da janela (órfão no FIM).
// Por isso a janela é APARADA nas duas pontas antes de virar contexto. É o que este módulo faz, e
// é a parte que precisa de teste — inverter a ordem é uma linha, não quebrar o protocolo não é.

/** Papéis gravados em `ai_operator_messages`. */
export type PapelMensagem = "user" | "assistant" | "tool" | "system";

/** Linha de `ai_operator_messages` como ela sai do banco.
 *
 *  O shape é IDÊNTICO ao `MessageRow` do ai-agent de propósito — mesmos campos, mesma
 *  obrigatoriedade — para que `rows.map(rowToChatMessage)` compile sem cast. Cast para fazer
 *  compilar é proibido neste repositório (CLAUDE.md, regra 7): foi assim que uma view sem as
 *  colunas de valor passou pelo compilador e quase zerou doze campos financeiros. Se este tipo
 *  divergir do banco, o certo é o `deno check` falhar aqui. */
export interface LinhaHistorico {
  role: PapelMensagem;
  content: string | null;
  tool_calls: Array<{ id: string; type: "function"; function: { name: string; arguments: string } }> | null;
  tool_call_id: string | null;
}

/** Quantas mensagens voltam ao modelo. Era 30 (e pelo lado errado). O dobro cabe folgado no
 *  contexto e cobre uma conversa longa de orçamento — a de 31/08 tinha 236 linhas, mas o que
 *  importa é alcançar o trabalho recente, não a conversa inteira. */
export const TAMANHO_DA_JANELA = 60;

function temToolCalls(linha: LinhaHistorico): boolean {
  return Array.isArray(linha.tool_calls) && linha.tool_calls.length > 0;
}

/**
 * Apara uma fatia cronológica de histórico até ela ser um contexto VÁLIDO para a API.
 *
 * Entrada: linhas em ordem cronológica (a mais antiga primeiro), já limitadas ao tamanho da janela.
 * Saída: a maior sub-fatia contígua que começa numa fala do usuário e não deixa `tool_use` pendente.
 *
 * Começar numa fala do usuário é o corte seguro: a partir dela o ciclo
 * user -> assistant(tool_use) -> tool(tool_result) fecha sozinho. Linhas `tool` e `assistant` no
 * começo da fatia pertencem a um turno cuja abertura ficou para trás.
 */
export function aparaJanela(linhas: LinhaHistorico[]): LinhaHistorico[] {
  // --- Ponta de trás: começar na primeira fala real do usuário. ---
  const inicio = linhas.findIndex((l) => l.role === "user");
  if (inicio === -1) return []; // nenhuma âncora: melhor começar limpo do que enviar fragmento.
  let janela = linhas.slice(inicio);

  // --- Ponta da frente: derrubar um turno que ficou pela metade. ---
  // Percorre de trás para frente enquanto o fim for um `assistant` com tool_use sem os
  // `tool_result` correspondentes (turno interrompido por timeout, erro ou short-circuit).
  while (janela.length > 0) {
    const ultimoAssistantComTool = (() => {
      for (let i = janela.length - 1; i >= 0; i--) {
        if (janela[i].role === "assistant") return temToolCalls(janela[i]) ? i : -1;
        if (janela[i].role === "user") return -1; // fala do usuário depois: turno anterior fechou.
      }
      return -1;
    })();
    if (ultimoAssistantComTool === -1) break;

    const temResultadoDepois = janela.slice(ultimoAssistantComTool + 1).some((l) => l.role === "tool");
    if (temResultadoDepois) break;

    janela = janela.slice(0, ultimoAssistantComTool);
    // Cortar o assistant pode expor outro turno pela metade — o laço reavalia.
    const novoInicio = janela.findIndex((l) => l.role === "user");
    if (novoInicio === -1) return [];
  }

  return janela;
}

/**
 * Monta a query da janela. Pede as N MAIS RECENTES (descendente) e devolve em ordem cronológica,
 * já aparada. Quem chama só passa o client e o id da sessão — não há como errar o sentido de novo.
 */
export async function carregarJanela(
  admin: any,
  sessionId: string,
  tamanho: number = TAMANHO_DA_JANELA,
): Promise<LinhaHistorico[]> {
  const { data: rows } = await admin
    .from("ai_operator_messages")
    .select("role, content, tool_calls, tool_call_id, created_at")
    .eq("session_id", sessionId)
    .order("created_at", { ascending: false }) // as MAIS RECENTES...
    .limit(tamanho);
  const cronologica = ((rows as LinhaHistorico[]) || []).slice().reverse(); // ...de volta à ordem de leitura.
  return aparaJanela(cronologica);
}
