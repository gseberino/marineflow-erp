// O interruptor do fluxo de comprovantes (F1, 11/10/2026): app_settings.comprovante_fluxo.
//
//   off    → webhook, assistente e cotação idênticos a hoje (é o valor com que a chave nasce);
//   sombra → o assistente recebe tudo como hoje e, em paralelo, o fluxo guarda, lê e arquiva;
//   dono   → o fluxo assume foto/PDF do dono, com avisos só informativos.
//
// Valor desconhecido, chave ausente ou erro de leitura = "off": um interruptor que liga por engano
// mexeria no caminho de todo o WhatsApp do dono. A pasta do Dropbox NÃO mora aqui (é constante no
// código, nucleo.ts): o financeiro escreve em app_settings e não pode desviar arquivo nenhum.

export type Modo = "off" | "sombra" | "dono";

export const CHAVE_DO_MODO = "comprovante_fluxo";

/** "sombra", " Dono ", "\"dono\"" → o modo; qualquer outra coisa → "off". */
export function modoDoValor(v: unknown): Modo {
  if (typeof v !== "string") return "off";
  const s = v.trim().replace(/^"(.*)"$/, "$1").trim().toLowerCase();
  return s === "sombra" || s === "dono" ? s : "off";
}

/** Lê o modo atual. Nunca lança: erro ou chave ausente = "off". */
// deno-lint-ignore no-explicit-any
export async function lerModoDoComprovante(admin: any): Promise<Modo> {
  try {
    const { data, error } = await admin
      .from("app_settings")
      .select("value")
      .eq("key", CHAVE_DO_MODO)
      .maybeSingle();
    if (error) return "off";
    return modoDoValor(data?.value);
  } catch {
    return "off";
  }
}
