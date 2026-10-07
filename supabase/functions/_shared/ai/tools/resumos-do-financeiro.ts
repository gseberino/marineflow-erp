// O que o dono vê ao confirmar as ferramentas do financeiro de 07/10/2026 — título em português e o
// pedido JÁ RESOLVIDO (qual anotação, qual pagamento, qual cobrança, qual favorecido). Um lugar só,
// para o agent.ts (buildPendingSummary) acrescentar uma chamada em vez de seis.
import type { ToolCtx } from "./registry.ts";
import { resumirAnotacao } from "./anotacoes.ts";
import { resumirEstorno } from "./estorno.ts";
import { resumirCobranca } from "./cobrancas.ts";
import { resumirFavorecido } from "./favorecidos.ts";

export const TITULOS_DO_FINANCEIRO: Record<string, string> = {
  alterar_anotacao_do_extrato: "Cancelar ou corrigir anotação de Pix",
  estornar_pagamento: "Estornar pagamento",
  criar_cobranca: "Criar cobrança",
  registrar_contato_de_cobranca: "Registrar contato de cobrança",
  alterar_cobranca: "Alterar cobrança",
  alterar_favorecido: "Alterar favorecido",
};

/**
 * Ferramentas cujo resumo resolve o alvo: quando não acha (ou acha mais de um), o resumo é uma linha
 * "⚠️ …" e vira recusa (resumoQueRecusa), não pendência — o dono não aprova um pedido que não achou.
 */
export const RESUMO_QUE_RESOLVE_DO_FINANCEIRO = Object.keys(TITULOS_DO_FINANCEIRO);

// deno-lint-ignore no-explicit-any
export async function resumirDoFinanceiro(admin: any, nome: string, args: Record<string, unknown>): Promise<string | null> {
  const ctx = { admin } as unknown as ToolCtx;
  if (nome === "alterar_anotacao_do_extrato") return await resumirAnotacao(ctx, args);
  if (nome === "estornar_pagamento") return await resumirEstorno(ctx, args);
  if (nome === "criar_cobranca" || nome === "registrar_contato_de_cobranca" || nome === "alterar_cobranca") {
    return await resumirCobranca(ctx, nome, args);
  }
  if (nome === "alterar_favorecido") return await resumirFavorecido(ctx, args);
  return null;
}
