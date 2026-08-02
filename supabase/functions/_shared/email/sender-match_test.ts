import { assertEquals, assert } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  matchSender, isFreeDomain, normalizeName, nameSimilarity, levenshtein, type MatchCandidate,
} from "./sender-match.ts";

const CANDIDATOS: MatchCandidate[] = [
  { id: "c1", name: "Marina Itajaí Ltda", email: "contato@marinaitajai.com.br", kind: "client" },
  { id: "c2", name: "Carlos Andrade", email: "carlos@gmail.com", kind: "client" },
  { id: "f1", name: "Náutica Sul Distribuidora", email: "vendas@nauticasul.com.br", kind: "supplier" },
  { id: "f2", name: "Náutica Sul Financeiro", email: "financeiro@nauticasul.com.br", kind: "supplier" },
];

Deno.test("matchSender: e-mail idêntico é certeza", () => {
  const m = matchSender("Contato@MarinaItajai.com.br", "Marina", CANDIDATOS);
  assertEquals(m?.id, "c1");
  assertEquals(m?.confidence, 1);
  assertEquals(m?.reason, "exact_email");
});

Deno.test("matchSender: domínio corporativo único casa com 0.8", () => {
  const m = matchSender("compras@marinaitajai.com.br", "Setor de Compras", CANDIDATOS);
  assertEquals(m?.id, "c1");
  assertEquals(m?.reason, "domain");
  assertEquals(m?.confidence, 0.8);
});

Deno.test("matchSender: domínio GRATUITO nunca casa por domínio", () => {
  // outro@gmail.com não pode virar "Carlos Andrade" só porque os dois usam Gmail
  const m = matchSender("pessoa.desconhecida@gmail.com", "Pessoa Desconhecida", CANDIDATOS);
  assertEquals(m, null);
});

Deno.test("matchSender: dois cadastros no mesmo domínio, sem nome, não escolhe", () => {
  const m = matchSender("outro@nauticasul.com.br", "", CANDIDATOS);
  assertEquals(m, null, "ambiguidade não autoriza adivinhação");
});

Deno.test("matchSender: dois cadastros no mesmo domínio desempatam pelo nome", () => {
  const m = matchSender("outro@nauticasul.com.br", "Náutica Sul Financeiro", CANDIDATOS);
  assertEquals(m?.id, "f2");
  assertEquals(m?.reason, "domain");
});

Deno.test("matchSender: nome muito parecido vira sugestão fraca (0.5)", () => {
  const m = matchSender("novo.contato@outrodominio.com.br", "Marina Itajai Ltda", CANDIDATOS);
  assertEquals(m?.id, "c1");
  assertEquals(m?.confidence, 0.5);
  assertEquals(m?.reason, "name_similarity");
});

Deno.test("matchSender: nome vagamente parecido NÃO casa", () => {
  const m = matchSender("x@dominio.com.br", "Marina", CANDIDATOS);
  assertEquals(m, null);
});

Deno.test("matchSender: entrada vazia devolve null sem quebrar", () => {
  assertEquals(matchSender("", "algum nome", CANDIDATOS), null);
  assertEquals(matchSender("a@b.com", "x", []), null);
  assertEquals(matchSender(null, null, CANDIDATOS), null);
});

Deno.test("matchSender: preserva o tipo da entidade (cliente vs fornecedor)", () => {
  assertEquals(matchSender("vendas@nauticasul.com.br", "", CANDIDATOS)?.kind, "supplier");
  assertEquals(matchSender("contato@marinaitajai.com.br", "", CANDIDATOS)?.kind, "client");
});

Deno.test("isFreeDomain: cobre os provedores comuns no Brasil", () => {
  assert(isFreeDomain("gmail.com"));
  assert(isFreeDomain("hotmail.com.br"));
  assert(isFreeDomain("uol.com.br"));
  assertEquals(isFreeDomain("marinaitajai.com.br"), false);
  assertEquals(isFreeDomain(null), false);
});

Deno.test("normalizeName: tira acento e sufixo societário", () => {
  assertEquals(normalizeName("Náutica Sul Comércio LTDA"), "nautica sul");
  assertEquals(normalizeName("MARINA ITAJAÍ S/A"), "marina itajai");
});

Deno.test("levenshtein e nameSimilarity: comportamento básico", () => {
  assertEquals(levenshtein("abc", "abc"), 0);
  assertEquals(levenshtein("", "abc"), 3);
  assertEquals(levenshtein("gato", "rato"), 1);
  assertEquals(nameSimilarity("Marina Itajaí", "marina itajai"), 1);
  assert(nameSimilarity("Marina Itajaí", "Posto Naval") < 0.5);
});
