// Poda de contexto — economia de tokens no histórico enviado ao LLM.
//
// Resultados de ferramenta de turnos ANTIGOS são blobs JSON grandes (uma busca devolve 20
// produtos com todos os campos). O modelo já agiu sobre eles e o texto do assistant já resume
// o que importou. Trocamos o conteúdo cru por um marcador — MENOS as mensagens recentes, que o
// turno atual ainda pode precisar. NUNCA remove a mensagem (mantém o pareamento tool_use/
// tool_result exigido pela API), só encurta o texto do resultado.

export type PrunableMessage =
  | { role: "user"; content: string }
  | { role: "assistant"; content: string; tool_calls?: unknown }
  | { role: "tool"; tool_call_id: string; content: string };

export const PODAR_APOS = 8; // nº de mensagens finais mantidas intactas
export const TOOL_RESULT_MAX = 600; // teto de caracteres de um resultado de tool antigo

export function podarHistoricoParaLLM<T extends PrunableMessage>(msgs: T[]): T[] {
  const corte = Math.max(0, msgs.length - PODAR_APOS);
  return msgs.map((m, i) => {
    if (i >= corte) return m; // recentes: intactas
    if (m.role === "tool" && typeof m.content === "string" && m.content.length > TOOL_RESULT_MAX) {
      return { ...m, content: m.content.slice(0, TOOL_RESULT_MAX) + " …[resultado antigo abreviado]" };
    }
    return m;
  });
}
