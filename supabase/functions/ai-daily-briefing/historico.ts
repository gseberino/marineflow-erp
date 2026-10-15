// O resumo da manhã no histórico da conversa do assistente — lógica pura, sem banco.
//
// ═══ POR QUE EXISTE ═══
//
// O resumo ia direto para a fila de envio e nada ficava em ai_operator_messages (0 de 12 resumos
// entregues desde 02/10/2026). Quando o dono respondia "cobra esse" ou "o 2", o assistente não
// sabia de que lista ele falava.
//
// Vai em par, como no lembretes-de-revisao: a janela do histórico (history-window.ts, aparaJanela)
// começa na primeira fala "user" — uma linha "assistant" sozinha numa conversa nova sumiria. A fala
// "user" é uma marca do sistema que diz que não foi o dono quem escreveu. Os horários são
// explícitos (+1 ms) porque linhas do mesmo created_at voltam do banco em ordem indefinida.
//
// Limite conhecido: a conversa do WhatsApp encerra com 4 h sem mensagem (whatsapp-channel.ts);
// "cobra esse" às 11:40 já cai numa conversa nova.

import { horaBR } from "../_shared/pdf/datas.ts";

export interface LinhaDoHistoricoDoResumo {
  session_id: string;
  role: "user" | "assistant";
  content: string;
  source: "system";
  created_at: string;
}

/**
 * `oQue` (secretário, Passo 3, 15/10/2026): o nome da mensagem — a tarde passa "o fechamento das 17:30" ou "a
 * revisão da semana". O padrão é o da manhã, letra por letra (o resumo de sempre não muda).
 */
export function linhasDoHistorico(sessionId: string, texto: string, agora: Date, oQue = "o resumo da manhã"): LinhaDoHistoricoDoResumo[] {
  const t0 = agora.getTime();
  return [
    {
      session_id: sessionId,
      role: "user",
      source: "system",
      created_at: new Date(t0).toISOString(),
      // Gravado quando o resumo ENTRA na fila, não quando chega: em 09 e 13/10/2026 a fila desistiu.
      // A marca não afirma a entrega, para o assistente não teimar que o dono recebeu.
      content: `[Mensagem automática do sistema, não é do dono] Às ${horaBR(agora)} o sistema mandou para o WhatsApp do dono ${oQue} abaixo (a entrega não é confirmada aqui: se ele disser que não chegou, é possível). Se ele citar um item ("cobra esse", "o 2"), é deste resumo.`,
    },
    {
      session_id: sessionId,
      role: "assistant",
      source: "system",
      created_at: new Date(t0 + 1).toISOString(),
      content: texto,
    },
  ];
}
