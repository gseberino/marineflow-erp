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
//
// Ajustes do dono (11/10/2026 — spec-ajustes-dono.md, 3): o SIM no WhatsApp já APROVA a linha que o
// CMP ligou e classificou ("ligar = classificar + aprovar"), pelo mesmo `aprovar` da tela, uma
// proposta por vez, com o dono como quem decidiu:
//   - aprovarDoComprovante (R11 comprovante_a_aprovar → aprovar → R12 comprovante_aprovado): a ação
//     interna approve_cmp (o comprovantes-whatsapp chama logo depois do sim) e o "gerar" (as ligadas
//     cuja proposta só apareceu depois e as aprovações que falharam antes: a chave `aprovar` da R1).
//   - Linha que já tem lançamento só é anexada (a R11 não a devolve: nada aprovado nem trocado).
// Nunca lança: erro vira { ok: false, motivo } e o log leva só o código.

// deno-lint-ignore no-explicit-any
type Admin = any;

export type LinhaDeComprovante = { codigo: string; papel: "ligada" | "candidata"; conta_aberta_id: string | null };

/** Uma ligada a aprovar (a chave `aprovar` da Varredura): o CMP, a proposta classificada e o dono que disse sim. */
export type ItemAAprovar = { cmp_id: string; proposta_id: string; autor: string };

export type Reavaliacao = {
  ok: boolean;
  reservadas: Set<string>;
  classificadas: number;
  ligados: number;
  /** Ajustes do dono: as linhas que o sim do dono autorizou e que ainda falta aprovar. */
  aprovar: ItemAAprovar[];
};

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

/** A chave `aprovar` da Varredura: só itens com os três uuids, sem repetir o CMP. */
function itensAAprovar(v: unknown): ItemAAprovar[] {
  const vistos = new Set<string>();
  const itens: ItemAAprovar[] = [];
  for (const x of (Array.isArray(v) ? v : []) as Array<Record<string, unknown>>) {
    const cmp = typeof x?.cmp_id === "string" ? x.cmp_id : "";
    const proposta = typeof x?.proposta_id === "string" ? x.proposta_id : "";
    const autor = typeof x?.autor === "string" ? x.autor : "";
    if (!UUID.test(cmp) || !UUID.test(proposta) || !UUID.test(autor) || vistos.has(cmp)) continue;
    vistos.add(cmp);
    itens.push({ cmp_id: cmp, proposta_id: proposta, autor });
  }
  return itens;
}

/** R1. Nunca lança: erro → { ok: false, reservadas: vazio, classificadas: 0, ligados: 0, aprovar: [] } e log só com o código. */
export async function reavaliarComprovantes(admin: Admin): Promise<Reavaliacao> {
  const falhou = (codigo: string): Reavaliacao => {
    logDosComprovantes("reavaliar_falhou", codigo);
    return { ok: false, reservadas: new Set(), classificadas: 0, ligados: 0, aprovar: [] };
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
      aprovar: itensAAprovar(d.aprovar),
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

/**
 * A parte da mensagem da rodada: "2 comprovante(s) ligado(s) ao extrato · 1 linha(s) de comprovante
 * aprovada(s)" (vazio sem ligação nem aprovação).
 */
export function mensagemDosComprovantes(ligados: number, aprovadas = 0): string {
  return [
    ligados > 0 ? `${ligados} comprovante(s) ligado(s) ao extrato` : "",
    aprovadas > 0 ? `${aprovadas} linha(s) de comprovante aprovada(s)` : "",
  ].filter(Boolean).join(" · ");
}

// ---------------------------------------------------------------------------------------------
// Ajustes do dono: o sim aprova a linha no Extrato (R11 → aprovar → R12)
// ---------------------------------------------------------------------------------------------

/**
 * Aprovar UMA proposta pelo caminho da tela (o `aprovar` do index.ts, com o dono como quem decidiu)
 * e devolver o lançamento criado. Injetado para o teste e para não importar o index (que serve).
 */
export type AprovarUma = (propostaId: string, autor: string) => Promise<{ ok: boolean; payable_id?: string | null; motivo?: string | null }>;

/** ok = lançada (registrado = o CMP guardou o lançamento); nada = não havia o que aprovar; ok false = falhou (o "gerar" tenta de novo). */
export type ResultadoDaAprovacao = {
  ok: boolean;
  nada?: boolean;
  motivo?: string | null;
  proposta_id?: string | null;
  payable_id?: string | null;
  registrado?: boolean;
};

function codigoDe(e: unknown): string {
  return String((e as { code?: unknown })?.code ?? (e as Error)?.name ?? "erro").slice(0, 40);
}

/**
 * Aprova a linha que o CMP ligou e classificou, no sim do dono: R11 diz qual proposta (null = nada a
 * aprovar: a linha já tem lançamento, a proposta ainda não está na fila, o CMP não está ligado);
 * só o dono do CMP aprova (autor ≠ quem disse sim → recusa); o `aprovar` da tela lança; R12 grava no
 * CMP (idempotente; uma segunda tentativa se falhar — a linha já está lançada mesmo assim). Nunca
 * lança; o log leva só o código.
 */
export async function aprovarDoComprovante(admin: Admin, cmpId: string, autor: string, aprovarUma: AprovarUma): Promise<ResultadoDaAprovacao> {
  const falhou = (motivo: string, log: string = motivo): ResultadoDaAprovacao => {
    logDosComprovantes("aprovar_cmp_falhou", log);
    return { ok: false, motivo };
  };
  if (!UUID.test(String(cmpId ?? "")) || !UUID.test(String(autor ?? ""))) return falhou("entrada_invalida");

  let alvo: Record<string, unknown> | null;
  try {
    const { data, error } = await admin.rpc("comprovante_a_aprovar", { p_cmp: cmpId });
    if (error) return falhou("sem_resposta", `r11:${codigoDe(error)}`);
    alvo = data && typeof data === "object" ? data as Record<string, unknown> : null;
  } catch (e) {
    return falhou("sem_resposta", `r11:${codigoDe(e)}`);
  }
  if (!alvo) return { ok: true, nada: true };
  const proposta = typeof alvo.proposta_id === "string" && UUID.test(alvo.proposta_id) ? alvo.proposta_id : null;
  if (!proposta) return falhou("sem_resposta", "r11_sem_proposta");
  if (String(alvo.autor ?? "") !== autor) return falhou("autor_diferente");

  let r: Awaited<ReturnType<AprovarUma>>;
  try {
    r = await aprovarUma(proposta, autor);
  } catch (e) {
    return falhou("nao_aprovada", `aprovar:${codigoDe(e)}`);
  }
  if (!r?.ok || typeof r.payable_id !== "string" || !UUID.test(r.payable_id)) {
    logDosComprovantes("aprovar_cmp_falhou", "aprovar_recusou");
    return { ok: false, motivo: String(r?.motivo ?? "nao_aprovada").slice(0, 200), proposta_id: proposta };
  }

  let ultimo = "";
  for (let tentativa = 0; tentativa < 2; tentativa++) {
    try {
      const { error } = await admin.rpc("comprovante_aprovado", { p_cmp: cmpId, p_proposta: proposta, p_payable: r.payable_id });
      if (!error) return { ok: true, proposta_id: proposta, payable_id: r.payable_id, registrado: true };
      ultimo = codigoDe(error);
    } catch (e) {
      ultimo = codigoDe(e);
    }
  }
  // a linha está lançada (o aprovar deu certo); só o CMP não guardou o lançamento
  logDosComprovantes("aprovar_cmp_nao_registrado", `r12:${ultimo}`);
  return { ok: true, proposta_id: proposta, payable_id: r.payable_id, registrado: false };
}

/** O "gerar": aprova, uma por vez, as ligadas que a R1 trouxe em `aprovar`. Nunca lança. */
export async function aprovarOsDaVarredura(admin: Admin, itens: ItemAAprovar[], aprovarUma: AprovarUma): Promise<{ aprovadas: number; falhas: number }> {
  let aprovadas = 0;
  let falhas = 0;
  for (const item of itens) {
    const r = await aprovarDoComprovante(admin, item.cmp_id, item.autor, aprovarUma);
    if (r.ok && !r.nada) aprovadas += 1;
    else if (!r.ok) falhas += 1;
  }
  return { aprovadas, falhas };
}

/**
 * A ação approve_cmp: só chamada interna (x-cron-secret certo E acting_user_id = o dono que disse
 * sim); sem eles, 401 — nem um usuário logado aprova por aqui. Corpo: { action, cmp_id, acting_user_id }.
 */
export async function responderApproveCmp(
  admin: Admin,
  p: { isCron: boolean; actingUserId: unknown; cmpId: unknown },
  aprovarUma: AprovarUma,
): Promise<{ status: number; corpo: Record<string, unknown> }> {
  if (!p.isCron || typeof p.actingUserId !== "string" || !UUID.test(p.actingUserId)) {
    return { status: 401, corpo: { error: "unauthorized" } };
  }
  if (typeof p.cmpId !== "string" || !UUID.test(p.cmpId)) return { status: 400, corpo: { ok: false, motivo: "entrada_invalida" } };
  return { status: 200, corpo: await aprovarDoComprovante(admin, p.cmpId, p.actingUserId, aprovarUma) as Record<string, unknown> };
}
