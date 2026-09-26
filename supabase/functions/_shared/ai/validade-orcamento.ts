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
//
// O que conta como "número que serve" (inteiro >= 1; senão passa ao próximo nível; nenhum,
// 15) mora em ../dias-de-validade.ts, o mesmo arquivo que o PDF e o aviso de vencimento (R19)
// usam: a validade com que o orçamento nasce e a que o documento imprime seguem uma regra só.

import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import { diasDeValidade, primeiraValidade, VALIDADE_PADRAO_DE_RESERVA } from "../dias-de-validade.ts";

/**
 * Último recurso, usado só se a configuração não existir nem puder ser lida. Reexportado de
 * ../dias-de-validade.ts (15, o DEFAULT da coluna) para quem já o importava daqui.
 */
export { VALIDADE_PADRAO_DE_RESERVA };

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
  // O pedido explícito vence sem nem ler a configuração.
  const pedida = diasDeValidade(explicita);
  if (pedida !== null) return pedida;

  let daEmpresa: unknown = null;
  try {
    const { data } = await db
      .from("app_settings")
      .select("value")
      .eq("key", "quote_validity_days")
      .maybeSingle();
    daEmpresa = (data as { value?: string } | null)?.value;
  } catch {
    // Configuração ilegível não pode impedir a criação do orçamento: cai na reserva.
  }
  return primeiraValidade(daEmpresa);
}
