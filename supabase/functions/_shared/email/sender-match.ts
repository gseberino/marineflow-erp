// Casamento remetente → cliente/fornecedor. Determinístico, sem LLM.
//
// DOUTRINA (herdada de DECISOES-TECNICAS.md): o modelo NUNCA escolhe a entidade e nunca
// recebe ou devolve id. Quem resolve é este código, no backend, a partir de dados do banco.
// O modelo só vê o rótulo humano depois de resolvido.

import { domainOf, normalizeAddress } from "./normalize.ts";

export type EntityKind = "client" | "supplier";

export interface MatchCandidate {
  id: string;
  name: string | null;
  email: string | null;
  kind: EntityKind;
}

export interface SenderMatch {
  id: string;
  kind: EntityKind;
  name: string | null;
  /** 1.0 = e-mail idêntico · 0.8 = mesmo domínio corporativo · 0.5 = nome parecido */
  confidence: number;
  reason: "exact_email" | "domain" | "name_similarity";
}

/**
 * Domínios de e-mail gratuitos: casar por domínio aqui ligaria TODO cliente do Gmail
 * a um só cadastro. É a diferença entre "mesma empresa" e "mesmo provedor".
 */
export const FREE_EMAIL_DOMAINS = new Set([
  "gmail.com", "hotmail.com", "hotmail.com.br", "outlook.com", "outlook.com.br",
  "live.com", "msn.com", "yahoo.com", "yahoo.com.br", "icloud.com", "me.com",
  "bol.com.br", "uol.com.br", "terra.com.br", "ig.com.br", "globo.com",
  "protonmail.com", "proton.me", "aol.com", "zipmail.com.br", "r7.com",
]);

export function isFreeDomain(domain: string | null): boolean {
  return !!domain && FREE_EMAIL_DOMAINS.has(domain.toLowerCase());
}

/** Normaliza nome para comparação: sem acento, sem pontuação, sem sufixo societário. */
export function normalizeName(raw: string | null | undefined): string {
  return String(raw ?? "")
    .normalize("NFD").replace(/[̀-ͯ]/g, "")
    .toLowerCase()
    .replace(/\b(ltda|me|epp|eireli|s\/?a|sa|cia|comercio|comercial|industria|servicos)\b/g, " ")
    .replace(/[^a-z0-9\s]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

/** Distância de Levenshtein, iterativa e com uma linha só de memória. */
export function levenshtein(a: string, b: string): number {
  if (a === b) return 0;
  if (a.length === 0) return b.length;
  if (b.length === 0) return a.length;

  let prev = new Array<number>(b.length + 1);
  let cur = new Array<number>(b.length + 1);
  for (let j = 0; j <= b.length; j++) prev[j] = j;

  for (let i = 1; i <= a.length; i++) {
    cur[0] = i;
    for (let j = 1; j <= b.length; j++) {
      const custo = a[i - 1] === b[j - 1] ? 0 : 1;
      cur[j] = Math.min(cur[j - 1] + 1, prev[j] + 1, prev[j - 1] + custo);
    }
    [prev, cur] = [cur, prev];
  }
  return prev[b.length];
}

/** Similaridade 0..1 entre dois nomes já normalizados. */
export function nameSimilarity(a: string, b: string): number {
  const x = normalizeName(a), y = normalizeName(b);
  if (!x || !y) return 0;
  if (x === y) return 1;
  const maxLen = Math.max(x.length, y.length);
  return 1 - levenshtein(x, y) / maxLen;
}

/** Acima disto, dois nomes são "parecidos o bastante" para virar sugestão (nunca certeza). */
export const NAME_SIMILARITY_FLOOR = 0.86;

/**
 * Cascata de casamento. Para na primeira camada que resolve, e nunca devolve empate:
 * ambiguidade não autoriza adivinhação — se duas entidades empatam, devolve null e o
 * e-mail fica como "contato desconhecido", que é um estado honesto.
 */
export function matchSender(
  fromAddress: string | null | undefined,
  fromName: string | null | undefined,
  candidates: MatchCandidate[],
): SenderMatch | null {
  const addr = normalizeAddress(fromAddress);
  if (!addr || candidates.length === 0) return null;

  // 1) E-mail idêntico — certeza.
  const exatos = candidates.filter((c) => normalizeAddress(c.email) === addr);
  if (exatos.length === 1) return toMatch(exatos[0], 1, "exact_email");
  if (exatos.length > 1) return null; // mesmo e-mail em dois cadastros: humano resolve

  // 2) Mesmo domínio corporativo — forte, mas não é certeza de pessoa.
  const dom = domainOf(addr);
  if (dom && !isFreeDomain(dom)) {
    const mesmoDominio = candidates.filter((c) => domainOf(c.email) === dom);
    if (mesmoDominio.length === 1) return toMatch(mesmoDominio[0], 0.8, "domain");
    if (mesmoDominio.length > 1) {
      // Vários contatos da mesma empresa: desempata pelo nome, se houver um claramente melhor.
      const porNome = melhorPorNome(fromName, mesmoDominio);
      if (porNome) return { ...porNome, confidence: 0.8, reason: "domain" };
      return null;
    }
  }

  // 3) Nome parecido — só sugestão.
  const porNome = melhorPorNome(fromName, candidates);
  return porNome ?? null;
}

function melhorPorNome(fromName: string | null | undefined, candidates: MatchCandidate[]): SenderMatch | null {
  const nome = String(fromName ?? "").trim();
  if (!nome) return null;

  let melhor: { c: MatchCandidate; s: number } | null = null;
  let segundo = 0;
  for (const c of candidates) {
    const s = nameSimilarity(nome, c.name ?? "");
    if (!melhor || s > melhor.s) { segundo = melhor?.s ?? 0; melhor = { c, s }; }
    else if (s > segundo) segundo = s;
  }
  if (!melhor || melhor.s < NAME_SIMILARITY_FLOOR) return null;
  // Empate técnico entre dois cadastros: não escolhe.
  if (melhor.s - segundo < 0.05) return null;
  return toMatch(melhor.c, 0.5, "name_similarity");
}

function toMatch(c: MatchCandidate, confidence: number, reason: SenderMatch["reason"]): SenderMatch {
  return { id: c.id, kind: c.kind, name: c.name, confidence, reason };
}
