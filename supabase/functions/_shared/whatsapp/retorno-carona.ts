// Retorno rápido, F2 (P11): a carona do retorno, 1 linha no fim da resposta do assistente ao dono.
//
// Quem decide é o banco (retorno_carona). A da agenda tem prioridade: uma carona por resposta, e o ai-agent só pergunta aqui
// quando a dela não veio. Nunca age com cartão de "sim", opções, fluxo ou erro no turno (turnoSemCarona).
//
// Fica fora de _shared/retorno/ de propósito: importa _shared/agenda/carona.ts, e o isolamento_test.ts proíbe isso lá.
//
// Reverter: tirar as duas chamadas do ai-agent. Sem deploy: update public.retorno_config set carona_ligada = false.

import { type TurnoDaCarona, turnoSemCarona } from "../agenda/carona.ts";

// deno-lint-ignore no-explicit-any
type Cliente = any;

const PREFIXO = "Retorno: ";

/** A carona pronta do banco, ou null. Nunca lança: erro do banco é sem carona, e a resposta sai igual. */
export async function caronaDoRetorno(
  admin: Cliente,
  autorId: string,
  turno: TurnoDaCarona | null | undefined,
  opcoes: { agora?: string } = {},
): Promise<string | null> {
  if (turnoSemCarona(turno) || !autorId) return null;
  try {
    const params: Record<string, unknown> = { p_autor: autorId };
    if (opcoes.agora) params.p_agora = opcoes.agora;
    const { data, error } = await admin.rpc("retorno_carona", params);
    if (error) return null;
    const texto = (data as { texto?: unknown } | null)?.texto;
    return typeof texto === "string" && texto.startsWith(PREFIXO) ? texto : null;
  } catch {
    return null;
  }
}
