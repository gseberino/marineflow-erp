// O que entra pelo número do parceiro não vai ao assistente (retorno rápido, F4, P12.4).
//
// A regra do plano: dado pessoal que chega pelo número da MP não vai à IA. Com retorno_config.parceiro_historico_na_ia = false
// (o padrão), o assistente não lê a conversa dos números CONFIRMADOS de parceiro pelos 6 caminhos do inventário:
//   1. get_whatsapp_conversation, por contato (recusa antes da consulta);
//   2. get_whatsapp_conversation, busca em todas as conversas (as linhas da chave saem, sem contar quantas);
//   3. get_client_360 e 4. get_supplier_360 (mensagens vazias e a nota);
//   5. list_unanswered_messages (previa nula; contato e hora ficam);
//   6. o resumo da confirmação de send_whatsapp_message (sem a linha "Última mensagem dele").
// Com a chave verdadeira, a saída de cada um é a de hoje. A chave não alcança os crons inativos (ai-followup-runner e
// agenda-inbox-detector): eles são portão de publicação (8.3).
//
// parceiro_numeros_fora_da_ia() (P3) dá as chaves de 8 dígitos (vazio com a chave verdadeira). Função ausente (o ai-agent
// subindo antes das migrations) = conjunto vazio. Falha fecha: qualquer outro erro dá `falhou`, e os 6 caminhos se comportam
// como se o número fosse confirmado. Não lê corpo nem telefone do chamador. A RPC é só do service_role: chame com ctx.admin.

import { chaveTelefone } from "./phone.ts";

export const FRASE_FORA_DO_ASSISTENTE = "A conversa com esse número fica fora do assistente.";

export interface ForaDoAssistente {
  chaves: Set<string>;
  falhou: boolean;
}

function funcaoAusente(e: unknown): boolean {
  const code = (e as { code?: string } | null)?.code;
  return code === "PGRST202" || code === "42883";
}

// deno-lint-ignore no-explicit-any
export async function chavesForaDoAssistente(admin: any): Promise<ForaDoAssistente> {
  try {
    const { data, error } = await admin.rpc("parceiro_numeros_fora_da_ia");
    if (error) return { chaves: new Set(), falhou: !funcaoAusente(error) };
    if (!Array.isArray(data)) return { chaves: new Set(), falhou: true };
    return { chaves: new Set(data.map((k) => String(k)).filter((k) => /^\d{8}$/.test(k))), falhou: false };
  } catch {
    return { chaves: new Set(), falhou: true };
  }
}

/** O número fica fora do assistente? Pela chave de 8 dígitos; com a leitura falha, todo número fica de fora. */
export function foraDoAssistente(fora: ForaDoAssistente, telefone: string | null | undefined): boolean {
  if (fora.falhou) return true;
  const chave = chaveTelefone(telefone);
  return chave !== null && fora.chaves.has(chave);
}
