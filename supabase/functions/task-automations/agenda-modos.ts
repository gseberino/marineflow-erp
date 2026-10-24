// Os modos da Agenda de Produção, lidos uma vez por rodada do motor de 15 min (Fase 2, P3 — 24/10/2026).
//
// O interruptor da regra antiga é o mesmo da substituta (spec-fase2 §3.3 d8, decisão d13 do dono): com
// agenda_config.modo_proposta = 'ligado' a agenda marca as OS e diz o que comprar — a R1 e a R16 param de criar tarefa e
// as vivas se resolvem sozinhas; com modo_vigia = 'ligado' a vigia pergunta quando a OS para — a R2 para. Assim é
// impossível ficar com as duas (o dono ouviria a mesma coisa duas vezes) ou com nenhuma.
//
// Leitura que falha aqui NÃO desliga nada: erro, linha ausente ou valor estranho = 'desligado', ou seja, as regras ficam
// como hoje (o lado seguro: no máximo o dono recebe a tarefa antiga). O erro volta em `erro` para entrar no resumo da
// rodada; quem registra em app_error_logs é a vigia, que lê a mesma tabela e falha junto.

// deno-lint-ignore no-explicit-any
type Db = any;

export type ModoDaAgenda = "desligado" | "sombra" | "ligado";

export interface ModosDaAgenda {
  /** agenda_config.modo_proposta: o que o motor FAZ (publicar, replanejar, status, datas). */
  proposta: ModoDaAgenda;
  /** agenda_config.modo_vigia: o que o sistema DIZ sozinho (perguntas, acorde). */
  vigia: ModoDaAgenda;
  /** A leitura falhou (as regras ficam como hoje). */
  erro?: string;
}

export const MODOS_DESLIGADOS: Readonly<ModosDaAgenda> = Object.freeze({ proposta: "desligado", vigia: "desligado" });

/** 'ligado', ' Sombra ', '"sombra"' → o modo; qualquer outra coisa → 'desligado'. */
export function lerModo(v: unknown): ModoDaAgenda {
  const s = typeof v === "string" ? v.trim().replace(/^"(.*)"$/, "$1").trim().toLowerCase() : "";
  return s === "sombra" || s === "ligado" ? s : "desligado";
}

/** Um SELECT em agenda_config. Nunca lança: erro = desligado (com o motivo em `erro`). */
export async function lerModosDaAgenda(db: Db): Promise<ModosDaAgenda> {
  try {
    const { data, error } = await db.from("agenda_config").select("modo_proposta, modo_vigia").maybeSingle();
    if (error) return { ...MODOS_DESLIGADOS, erro: String(error.message ?? error.code ?? "erro na leitura") };
    if (!data) return { ...MODOS_DESLIGADOS, erro: "agenda_config sem a linha de parâmetros" };
    return { proposta: lerModo(data.modo_proposta), vigia: lerModo(data.modo_vigia) };
  } catch (e) {
    return { ...MODOS_DESLIGADOS, erro: String((e as Error)?.message ?? e) };
  }
}
