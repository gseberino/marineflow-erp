// Achar o barco pelo que o dono escreve no WhatsApp ("Donna V", "dona v", "barco do Acrisio",
// "madu") — Fase 5 do Dropbox, 08/10/2026 (plans/marineflow-dropbox-fase2.md). Puro: tem teste.
//
// Regra de nome (feedback do dono, 26/09): nome PARECIDO não decide sozinho. Aqui a busca só
// escolhe quando há UM candidato claramente melhor (igual, começo, ou dono igual); senão devolve
// as opções e o assistente pergunta.

export type Candidato = { id: string; nome: string; cliente: string | null };

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

/** Nota de 0 a 100: o nome do barco vale mais que o do dono. */
export function notaDoBarco(termo: string, c: Candidato): number {
  const t = chaveDeNome(termo.replace(/^(o |a )?(barco|lancha|motorhome|embarcacao)( d[oae]s?)? /i, ""));
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

/** Escolhe o barco só quando um candidato se destaca; empate ou nota baixa = pergunta. */
export function escolherBarco(termo: string, candidatos: Candidato[]): Escolha {
  const notas = candidatos
    .map((c) => ({ c, n: notaDoBarco(termo, c) }))
    .filter((x) => x.n >= 60)
    .sort((a, b) => b.n - a.n);
  if (!notas.length) return { ok: false, erro: `Não achei barco com "${termo}".` };
  const melhores = notas.filter((x) => x.n === notas[0].n);
  if (melhores.length === 1) return { ok: true, barco: melhores[0].c };
  return {
    ok: false,
    erro: `Há ${melhores.length} barcos que batem com "${termo}". Pergunte qual.`,
    opcoes: melhores.slice(0, 8).map((x) => x.c),
  };
}
