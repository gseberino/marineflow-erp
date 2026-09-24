// A validade padrão do orçamento — uma fonte só.
//
// POR QUE ISTO EXISTE: até 24/09/2026 havia TRÊS respostas concorrentes para "quantos dias
// vale um orçamento":
//
//   · `app_settings.quote_validity_days`, que é o que o dono configura na tela;
//   · `?? 30` fixo no construtor de orçamento do assistente;
//   · `DEFAULT 15` na coluna `service_orders.quote_validity_days`, que vale sempre que o
//     insert omite o campo.
//
// O dono configurou 3 dias e viu orçamentos nascendo com 30 (os criados pelo assistente) e
// com 15 (os criados antes de a chave existir em app_settings). A queixa dele foi
// literalmente "nunca consegui deixar isso padrão para 3 dias" — e ele estava certo: a
// configuração era só uma das três vozes.
//
// Agora quem cria orçamento pergunta aqui.

import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";

/**
 * Último recurso, usado só se a configuração não existir nem puder ser lida.
 *
 * 15 e não 30: é o mesmo número que o DEFAULT da coluna e que o fallback do formulário,
 * então uma falha de leitura mantém o comportamento que o resto do sistema já tinha, em
 * vez de introduzir um terceiro valor.
 */
export const VALIDADE_PADRAO_DE_RESERVA = 15;

/**
 * Quantos dias vale um orçamento novo, segundo a configuração da empresa.
 *
 * @param explicita Valor que quem chamou informou de propósito (o usuário pediu "vale 7
 *                  dias"). Vence a configuração, porque é uma decisão para aquele caso.
 */
export async function validadePadraoDoOrcamento(
  // deno-lint-ignore no-explicit-any
  db: SupabaseClient<any, "public", any>,
  explicita?: number | null,
): Promise<number> {
  const pedida = Number(explicita);
  if (Number.isFinite(pedida) && pedida > 0) return Math.floor(pedida);

  try {
    const { data } = await db
      .from("app_settings")
      .select("value")
      .eq("key", "quote_validity_days")
      .maybeSingle();
    const dias = Number((data as { value?: string } | null)?.value);
    if (Number.isFinite(dias) && dias > 0) return Math.floor(dias);
  } catch {
    // Configuração ilegível não pode impedir a criação do orçamento: cai na reserva.
  }
  return VALIDADE_PADRAO_DE_RESERVA;
}
