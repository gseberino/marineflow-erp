// Os comprovantes (CMP) no finance-review — F3, 11/10/2026 (spec-f3.md, 5.1 e 2.6).
//
// O dono manda o cupom pelo WhatsApp; o CMP gravado espera a linha do banco e, quando ela aparece,
// liga a linha a ele (a classifica pela anotação, anexa ao lançamento ou casa com a conta aberta).
// Aqui o finance-review só CONSULTA o banco:
//   - reavaliarComprovantes (R1, comprovantes_reavaliar_banco): logo depois de aplicar as anotações,
//     a varredura dos CMPs que esperam o banco. Devolve as linhas RESERVADAS (ligadas a um CMP, ou
//     candidatas de uma pergunta do extrato que espera o dono): essas o "lançar sozinho" não toca.
//   - linhasDeComprovante (R2, comprovantes_linhas_da_conciliacao): de quem é cada linha, para o
//     aprovar recusar despesa nova na linha cujo CMP anexou uma conta a pagar em aberto.
// As duas nunca lançam: erro vira "como antes da F3" (nada reservado, nada recusado) e o log leva
// só o código do erro — nunca valor, nome ou descrição da linha.

// deno-lint-ignore no-explicit-any
type Admin = any;

export type LinhaDeComprovante = { codigo: string; papel: "ligada" | "candidata"; conta_aberta_id: string | null };

export type Reavaliacao = { ok: boolean; reservadas: Set<string>; classificadas: number; ligados: number };

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function logDosComprovantes(evento: string, codigo: string): void {
  console.warn(JSON.stringify({ fn: "finance-review", evento, codigo }));
}

function contagem(v: unknown): number {
  const n = Math.trunc(Number(v));
  return Number.isFinite(n) && n > 0 ? n : 0;
}

function idsValidos(v: unknown): string[] {
  return (Array.isArray(v) ? v : []).filter((x): x is string => typeof x === "string" && UUID.test(x));
}

/** R1. Nunca lança: erro → { ok: false, reservadas: vazio, classificadas: 0, ligados: 0 } e log só com o código. */
export async function reavaliarComprovantes(admin: Admin): Promise<Reavaliacao> {
  const falhou = (codigo: string): Reavaliacao => {
    logDosComprovantes("reavaliar_falhou", codigo);
    return { ok: false, reservadas: new Set(), classificadas: 0, ligados: 0 };
  };
  try {
    const { data, error } = await admin.rpc("comprovantes_reavaliar_banco", { p_origem: "finance_review" });
    if (error) return falhou(String(error.code ?? "erro"));
    const d = (data ?? {}) as Record<string, unknown>;
    return {
      ok: true,
      reservadas: new Set(idsValidos(d.reservadas)),
      classificadas: contagem(d.classificadas),
      ligados: contagem(d.ligados),
    };
  } catch (e) {
    return falhou((e as Error)?.name ?? "erro");
  }
}

/** R2. Erro → Map vazio (quem chama segue como antes da F3). Sem linhas, nem consulta. */
export async function linhasDeComprovante(
  admin: Admin,
  ids: string[],
): Promise<{ linhas: Map<string, LinhaDeComprovante>; anotacoes: Set<string> }> {
  const vazio = { linhas: new Map<string, LinhaDeComprovante>(), anotacoes: new Set<string>() };
  const pedidas = [...new Set(idsValidos(ids))];
  if (!pedidas.length) return vazio;
  try {
    const { data, error } = await admin.rpc("comprovantes_linhas_da_conciliacao", { p_transacoes: pedidas });
    if (error) {
      logDosComprovantes("linhas_falhou", String(error.code ?? "erro"));
      return vazio;
    }
    const d = (data ?? {}) as { linhas?: unknown; anotacoes?: unknown };
    const linhas = new Map<string, LinhaDeComprovante>();
    for (const l of (Array.isArray(d.linhas) ? d.linhas : []) as Array<Record<string, unknown>>) {
      const tx = typeof l?.bank_transaction_id === "string" ? l.bank_transaction_id : null;
      if (!tx || typeof l.codigo !== "string") continue;
      const papel = l.papel === "ligada" ? "ligada" : "candidata";
      const anterior = linhas.get(tx);
      // a ligada vale mais que a candidata (uma linha pode ser candidata de um CMP e ligada a outro)
      if (anterior?.papel === "ligada" && papel !== "ligada") continue;
      linhas.set(tx, { codigo: l.codigo, papel, conta_aberta_id: typeof l.conta_aberta_id === "string" ? l.conta_aberta_id : null });
    }
    return { linhas, anotacoes: new Set(idsValidos(d.anotacoes)) };
  } catch (e) {
    logDosComprovantes("linhas_falhou", (e as Error)?.name ?? "erro");
    return vazio;
  }
}

/**
 * As reservadas da rodada: as da R1; se ela falhou, as da R2 para as linhas novas desta rodada
 * (a ligação feita antes, pelo cron, continua valendo). As duas falhando, nenhuma: como antes da F3.
 */
export async function reservadasDaRodada(admin: Admin, r1: Reavaliacao, linhasNovas: string[]): Promise<Set<string>> {
  if (r1.ok) return r1.reservadas;
  const r2 = await linhasDeComprovante(admin, linhasNovas);
  return new Set(r2.linhas.keys());
}

/** As linhas que o "lançar sozinho" (por regra) ainda pode lançar: sem as anotadas agora e sem as reservadas por um CMP. */
export function foraDasReservadas<T extends { bank_transaction_id?: unknown }>(linhas: T[], ...fora: Set<string>[]): T[] {
  return linhas.filter((l) => !fora.some((s) => s.has(String(l.bank_transaction_id))));
}

/**
 * aprovar: a linha cujo CMP anexou uma conta a pagar em aberto não ganha despesa nova — o caminho é
 * casar a linha com a conta (Conciliação). A ligada É a do CMP; a candidata (a R2 só devolve a forte
 * de uma pergunta que espera o dono; as fracas de um azul nem vêm) PODE SER — o texto não afirma o
 * que o dono ainda não confirmou. null = pode lançar.
 */
export function recusaDaLinhaDoCmp(l: LinhaDeComprovante | undefined | null): string | null {
  if (!l?.conta_aberta_id) return null;
  if (l.papel === "ligada") {
    return `Esta linha é a do ${l.codigo}, que anexou uma conta a pagar em aberto: case pela Conciliação em vez de lançar outra`;
  }
  return `Esta linha pode ser a do ${l.codigo}, que tem uma conta a pagar em aberto: responda a pergunta do extrato no WhatsApp ou case pela Conciliação em vez de lançar outra`;
}

/** A parte da mensagem da rodada: "2 comprovante(s) ligado(s) ao extrato" (vazio sem ligação). */
export function mensagemDosComprovantes(ligados: number): string {
  return ligados > 0 ? `${ligados} comprovante(s) ligado(s) ao extrato` : "";
}
