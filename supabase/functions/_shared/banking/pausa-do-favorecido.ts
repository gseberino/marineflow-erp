// Desativar um favorecido pausa as regras do extrato que apontam para ele (07/10/2026).
//
// Regra do dono ("Desativar cadastro: pausar as regras dele", 28/09/2026): desativar o cadastro
// não desliga quem aponta para ele, e o próximo Pix voltaria a entrar classificado no favorecido
// desativado. As regras que apontam — pelo CPF/CNPJ dele, ou pelo nome COMPLETO dele no extrato —
// são pausadas com uma marca na nota; reativar o favorecido devolve as que foram pausadas por isso,
// na situação de antes.
//
// Módulo puro, sem banco: é usado pela TELA (src/hooks/use-payees.ts, botão desativar/reativar de
// Favorecidos) e pelo ASSISTENTE (_shared/ai/tools/favorecidos.ts, alterar_favorecido). A marca na
// nota é a mesma nos dois — o que a tela pausou, o assistente reativa, e vice-versa.

export interface RegraDoExtrato {
  id: string;
  match_type: string;
  match_value: string;
  set_category: string | null;
  status: string;
  note: string | null;
}

export interface FavorecidoDaPausa {
  id: string;
  name: string;
  document: string | null;
}

/** O que identifica a pausa deste favorecido na nota da regra. */
export const marcaDoFavorecido = (id: string) => `fav:${id}]`;

/** Mesma normalização de `normal` (_shared/ai/tools/caixa.ts): sem acento, minúsculas, só letras/dígitos. */
function normalDoNome(s: unknown): string {
  return String(s ?? "").normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase()
    .replace(/[^a-z0-9 ]/g, " ").replace(/\s+/g, " ").trim();
}

/** A marca que a desativação deixa na nota da regra: guarda a situação de antes para a volta. */
export function marcarPausa(nota: string | null, f: { id: string; name: string }, statusAntes: string, hoje: string): string {
  return `${nota ?? ""} [pausada ao desativar o favorecido ${f.name} em ${hoje} · era ${statusAntes} · ${marcaDoFavorecido(f.id)}`.trim();
}

/** Reativar: a situação de antes (a marca diz) e a nota sem a marca. */
export function tirarPausa(nota: string | null, idDoFavorecido: string): { status: string; note: string | null } {
  const texto = String(nota ?? "");
  const fim = texto.indexOf(marcaDoFavorecido(idDoFavorecido));
  const inicio = fim < 0 ? -1 : texto.lastIndexOf("[pausada ao desativar o favorecido", fim);
  if (inicio < 0) return { status: "active", note: nota };
  const marca = texto.slice(inicio, fim + marcaDoFavorecido(idDoFavorecido).length);
  const antes = marca.match(/· era (active|proposed) ·/)?.[1] ?? "active";
  const resto = (texto.slice(0, inicio) + texto.slice(fim + marcaDoFavorecido(idDoFavorecido).length)).replace(/\s+/g, " ").trim();
  return { status: antes, note: resto || null };
}

/** As regras do extrato que apontam para este favorecido: pelo documento dele, ou pelo nome completo. */
export function regrasQueApontam<R extends RegraDoExtrato>(f: FavorecidoDaPausa, regras: R[]): R[] {
  const doc = String(f.document ?? "").replace(/\D/g, "");
  const nome = normalDoNome(f.name);
  return regras.filter((r) =>
    (r.match_type === "document" && doc.length >= 11 && String(r.match_value ?? "").replace(/\D/g, "") === doc) ||
    (r.match_type === "counterparty" && nome.includes(" ") && ` ${normalDoNome(r.match_value)} `.includes(` ${nome} `))
  );
}

/** Situações lidas para cada lado: desativar mexe nas que valem; reativar, nas pausadas. */
export const SITUACOES_DA_MUDANCA = (ativar: boolean): string[] => (ativar ? ["paused"] : ["active", "proposed"]);

/**
 * Quais regras mudam. Desativar: as que apontam e estão valendo. Reativar: só as que foram
 * pausadas por ESTA desativação (a marca) — regra pausada à mão continua pausada.
 * Recebe as regras lidas com SITUACOES_DA_MUDANCA (filtra de novo por segurança).
 */
export function regrasDaMudanca<R extends RegraDoExtrato>(f: FavorecidoDaPausa, regras: R[], ativar: boolean): R[] {
  const situacoes = SITUACOES_DA_MUDANCA(ativar);
  const lidas = regras.filter((r) => situacoes.includes(r.status));
  if (ativar) return lidas.filter((r) => String(r.note ?? "").includes(marcaDoFavorecido(f.id)));
  return regrasQueApontam(f, lidas);
}

/** O que gravar na regra: pausar com a marca, ou voltar à situação de antes sem a marca. */
export function mudancaDaRegra(
  regra: RegraDoExtrato, f: { id: string; name: string }, ativar: boolean, hoje: string,
): { status: string; note: string | null } {
  return ativar ? tirarPausa(regra.note, f.id) : { status: "paused", note: marcarPausa(regra.note, f, regra.status, hoje) };
}
