// Achar a unidade (barco, motorhome, trailer…) pelo que o dono escreve no WhatsApp ("Donna V",
// "dona v", "barco do Acrisio", "o trailer do Ribas", "madu") — Fase 5 do Dropbox, 08/10/2026
// (plans/marineflow-dropbox-fase2.md). A pasta existe para motorhome também. Puro: tem teste.
//
// Regra de nome (feedback do dono, 26/09): nome PARECIDO não decide sozinho. Aqui a busca só
// escolhe quando há UM candidato claramente melhor (igual, começo, ou dono igual); senão devolve
// as opções e o assistente pergunta.

/** `tipo` (vessels.asset_type) é só para o texto ("a lancha Donna V"): a nota não usa. */
export type Candidato = { id: string; nome: string; cliente: string | null; tipo?: string | null };

/** Sem acento, minúsculo, letras repetidas juntadas ("Donna" e "Dona" ficam iguais). */
export function chaveDeNome(s: string | null | undefined): string {
  return (s ?? "")
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, " ")
    .replace(/([a-z])\1+/g, "$1")
    .trim()
    .replace(/\s+/g, " ");
}

/**
 * A palavra do tipo na frente do termo ("o trailer do Ribas" → "ribas"), já na chave (sem acento,
 * letras repetidas juntadas). Os tipos da lista do cadastro (22/10/2026) e o que se fala no dia a dia.
 * Só sai com algo depois: "motorhome" sozinho continua sendo o termo (há unidades chamadas assim).
 */
const TIPO_NA_FRENTE =
  /^(o |a )?(barco|bote|lancha|veleiro|catamara|moto aquatica|jet ?ski|embarcacao|motorhome|motor home|trailer|camper|van|automovel|veiculo|equipamento)( d[oae]s?)? /;

/**
 * Nota de 0 a 100: o nome da unidade vale mais que o do dono. Conta o termo inteiro E o termo sem o
 * tipo na frente, e fica com a maior: "Trailer Darlan" é o nome exato do trailer (100) e não pode
 * cair para "contém darlan" (70) e perder para um "Darlan II" (85).
 */
export function notaDoBarco(termo: string, c: Candidato): number {
  const inteira = chaveDeNome(termo);
  const semTipo = inteira.replace(TIPO_NA_FRENTE, "");
  return Math.max(notaDaChave(inteira, c), semTipo === inteira ? 0 : notaDaChave(semTipo, c));
}

function notaDaChave(t: string, c: Candidato): number {
  if (!t) return 0;
  const barco = chaveDeNome(c.nome);
  const dono = chaveDeNome(c.cliente);
  if (barco === t) return 100;
  if (barco.startsWith(t + " ") || barco.startsWith(t)) return 85;
  if (dono && dono === t) return 80;
  if (barco.includes(t)) return 70;
  if (dono && (dono.startsWith(t + " ") || dono.split(" ").includes(t))) return 60;
  return 0;
}

export type Escolha =
  | { ok: true; barco: Candidato }
  | { ok: false; erro: string; opcoes?: Candidato[] };

/** Escolhe a unidade só quando um candidato se destaca; empate ou nota baixa = pergunta. */
export function escolherBarco(termo: string, candidatos: Candidato[]): Escolha {
  const notas = candidatos
    .map((c) => ({ c, n: notaDoBarco(termo, c) }))
    .filter((x) => x.n >= 60)
    .sort((a, b) => b.n - a.n);
  if (!notas.length) return { ok: false, erro: `Não achei embarcação ou veículo com "${termo}".` };
  const melhores = notas.filter((x) => x.n === notas[0].n);
  if (melhores.length === 1) return { ok: true, barco: melhores[0].c };
  return {
    ok: false,
    erro: `Há ${melhores.length} embarcações ou veículos que batem com "${termo}". Pergunte qual.`,
    opcoes: melhores.slice(0, 8).map((x) => x.c),
  };
}
