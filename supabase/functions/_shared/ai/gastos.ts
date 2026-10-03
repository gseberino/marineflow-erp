// "Quanto gastei com X?" — a resposta inteira, não só o que já foi lançado (02/10/2026).
//
// O que motivou: o dono perguntou pelo WhatsApp "quanto foi o gasto com combustível em setembro?"
// e o assistente respondeu R$ 0 — e depois "não há nenhuma despesa lançada em setembro". A
// ferramenta pedia `payees(name)` de `payables`, que tem duas chaves para payees (payee_id e
// beneficiario_id); o banco recusava a consulta e a ferramenta tratava o erro como "nada". Além
// disso, mesmo funcionando, ela só via o que já estava lançado: em setembro havia R$ 100 lançados
// como combustível e R$ 356,51 em 11 compras no Posto Paulinho ainda pendentes no cartão.
//
// Aqui fica a regra pura (testada em gastos_test.ts):
//   - o que a pessoa disse vira categorias do plano de contas: pelo nome ("combustível" acha
//     "Combustível e deslocamento" e "Veículo e Combustível") ou pela palavra do dia a dia
//     ("gasolina", "posto", "almoço" — a mesma lista do Extrato);
//   - uma linha do banco ainda sem lançamento conta para a categoria pela sugestão do Extrato,
//     pelo ramo do cartão (MCC 5541 = posto) ou pelo texto do estabelecimento;
//   - um lançamento em OUTRA categoria, mas de estabelecimento do mesmo ramo, é mostrado à parte
//     (ex.: compra no posto lançada como alimentação), sem entrar no total.
import { categoriaPeloTexto, type RegraFinanceira } from "../banking/proposals.ts";
import { categoriaPorMcc } from "../banking/mcc.ts";

/** Sem acento, minúsculo, sem pontuação. */
export function normal(s: unknown): string {
  return String(s ?? "").normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase()
    .replace(/[^a-z0-9 ]/g, " ").replace(/\s+/g, " ").trim();
}

const PALAVRAS_VAZIAS = new Set(["gasto", "gastos", "gastei", "com", "de", "do", "da", "dos", "das", "em", "no", "na", "e", "o", "a", "os", "as", "mes", "despesa", "despesas"]);

/**
 * As categorias do plano que o pedido aponta. `nomes` é o plano de contas do lado pedido
 * (despesa ou receita). Devolve as parecidas quando nada casa, para o assistente perguntar.
 */
export function resolverCategorias(
  pedido: string,
  nomes: string[],
  regras: RegraFinanceira[] = [],
): { categorias: string[]; como: string } | { nenhuma: true; parecidas: string[] } {
  const p = normal(pedido);
  if (!p) return { nenhuma: true, parecidas: [] };
  // Começo de palavra, não pedaço: "posto" não pode achar "Impostos e taxas".
  const porNome = nomes.filter((n) => {
    const nn = normal(n);
    return nn === p || ` ${nn}`.includes(` ${p}`) || ` ${p} `.includes(` ${nn} `);
  });
  if (porNome.length) return { categorias: porNome, como: `nome da categoria contém "${pedido}"` };

  // Palavra a palavra ("gasto com peças" → "peças"), ignorando as vazias.
  const palavras = p.split(" ").filter((w) => w.length >= 4 && !PALAVRAS_VAZIAS.has(w));
  const porPalavra = nomes.filter((n) => palavras.some((w) => normal(n).split(" ").some((x) => x.startsWith(w) || w.startsWith(x) && x.length >= 4)));
  if (porPalavra.length) return { categorias: porPalavra, como: `palavra do pedido no nome da categoria` };

  // Palavra do dia a dia: "gasolina", "posto", "almoço" (a mesma leitura do Extrato).
  const doTexto = categoriaPeloTexto(pedido, regras);
  if (doTexto) {
    const existe = nomes.find((n) => normal(n) === normal(doTexto.categoria));
    if (existe) return { categorias: [existe], como: doTexto.motivo };
  }

  const parecidas = nomes.filter((n) => palavras.some((w) => normal(n).includes(w.slice(0, 4)))).slice(0, 8);
  return { nenhuma: true, parecidas };
}

/** Uma linha do banco (saída) que ainda não virou lançamento. */
export interface LinhaSemLancamento {
  id: string;
  data: string;
  valor: number;
  quem: string;
  mcc: string | null;
  /** Compra no cartão que o banco ainda não fechou. */
  pendente: boolean;
  /** Categoria que o Extrato sugeriu, se a linha já está na fila. */
  categoriaSugerida: string | null;
}

/** A categoria que a linha indica: a sugestão do Extrato, o ramo do cartão ou o texto. */
export function categoriaDaLinha(l: Pick<LinhaSemLancamento, "categoriaSugerida" | "mcc" | "quem">, regras: RegraFinanceira[] = []): { categoria: string; por: string } | null {
  if (l.categoriaSugerida) return { categoria: l.categoriaSugerida, por: "sugestão do Extrato" };
  const pelaMcc = categoriaPorMcc(l.mcc);
  if (pelaMcc) return { categoria: pelaMcc.categoria, por: `ramo do cartão: ${pelaMcc.rotulo}` };
  const peloTexto = categoriaPeloTexto(l.quem, regras);
  if (peloTexto) return { categoria: peloTexto.categoria, por: peloTexto.motivo };
  return null;
}

/** A linha bate com o pedido: pela categoria indicada ou, com busca, pelo nome. */
export function linhaCasa(
  l: LinhaSemLancamento,
  categorias: string[] | null,
  busca: string | null,
  regras: RegraFinanceira[] = [],
): boolean {
  if (busca && !normal(l.quem).includes(normal(busca))) return false;
  if (!categorias) return true;
  const c = categoriaDaLinha(l, regras);
  return !!c && categorias.some((x) => normal(x) === normal(c.categoria));
}

/** Um lançamento lido do banco. */
export interface LancamentoLido {
  data: string;
  valor: number;
  categoria: string | null;
  descricao: string;
  quem: string | null;
  /** Ramo do cartão da linha do banco de onde veio, se houver. */
  mcc: string | null;
}

/** Lançamento de outra categoria cujo estabelecimento é do ramo pedido (ex.: posto lançado como alimentação). */
export function doMesmoRamoEmOutraCategoria(l: LancamentoLido, categorias: string[]): boolean {
  if (!l.mcc) return false;
  const pelaMcc = categoriaPorMcc(l.mcc);
  if (!pelaMcc) return false;
  const pedida = categorias.some((x) => normal(x) === normal(pelaMcc.categoria));
  const lancadaFora = !categorias.some((x) => normal(x) === normal(l.categoria));
  return pedida && lancadaFora;
}

export const centavos = (v: number) => Math.round((Number(v) || 0) * 100) / 100;

export function somar<T>(itens: T[], valor: (t: T) => number): number {
  return centavos(itens.reduce((s, t) => s + (Number(valor(t)) || 0), 0));
}

/** Primeiro e último dia de um mês, em ISO. */
export function intervaloDoMes(ano: number, mes: number): [string, string] {
  const ult = new Date(Date.UTC(ano, mes, 0)).getUTCDate();
  const mm = String(mes).padStart(2, "0");
  return [`${ano}-${mm}-01`, `${ano}-${mm}-${ult}`];
}
