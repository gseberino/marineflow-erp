// O interruptor do resumo da manhã (secretário, Passo 2, 15/10/2026): app_settings.resumo_formato.
//
//   antigo → o resumo de sempre, byte a byte (é o valor com que a chave nasce);
//   sombra → envia o de sempre e GUARDA o novo (resumo_manha), sem enviar, para a comparação;
//   novo   → o dono recebe o novo (até 3 itens com letra) e os comandos ficam ligados; "tudo" devolve o de sempre.
//
// Valor desconhecido, chave ausente ou erro de leitura = "antigo": voltar atrás é trocar a chave, sem
// publicar código. Três fontes do mesmo padrão: este "antigo", a linha da migration 20261015200000 e a
// ausência da chave.

export type FormatoDoResumo = "antigo" | "sombra" | "novo";

export const CHAVE_DO_FORMATO = "resumo_formato";

/** "novo", " Sombra ", "\"novo\"" → o formato; qualquer outra coisa → "antigo". */
export function lerFormatoDoResumo(v: unknown): FormatoDoResumo {
  if (typeof v !== "string") return "antigo";
  const s = v.trim().replace(/^"(.*)"$/, "$1").trim().toLowerCase();
  return s === "sombra" || s === "novo" ? s : "antigo";
}

/** Lê a chave no banco. Nunca lança: erro ou chave ausente = "antigo". */
// deno-lint-ignore no-explicit-any
export async function formatoDoResumoNoBanco(admin: any): Promise<FormatoDoResumo> {
  try {
    const { data, error } = await admin.from("app_settings").select("value").eq("key", CHAVE_DO_FORMATO).maybeSingle();
    if (error) return "antigo";
    return lerFormatoDoResumo(data?.value);
  } catch {
    return "antigo";
  }
}
