// Identificação da linha do Extrato com a regra de ENTRADA — "o Pix do CPF/CNPJ X é do cliente Y"
// (resposta 18 do dono, 26/09/2026): o cliente da regra vence o dono do documento, com a prova
// "regra sua", e continua sugestão.
import { assert, assertEquals, assertNotEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { identificarLinha, type ContextoDeIdentificacao, ultimaEscolhaPorFavorecido } from "./identificacao.ts";
import { indexarContrapartes } from "../_shared/banking/contraparte.ts";

const ctx: ContextoDeIdentificacao = {
  indice: indexarContrapartes({
    fornecedores: [], favorecidos: [], historico: [],
    clientes: [
      { id: "c-joao", name: "João da Silva", cpf_cnpj: "999.888.777-66" },
      { id: "c-maria", name: "MARIA SILVA", cpf_cnpj: "123.456.789-01" },
    ],
  }),
  candidatos: [],
  categoriaDoFavorecido: new Map(),
  drePorCategoria: new Map(),
};

// A Maria paga pelo barco do marido, o João.
const pixDaMaria = {
  id: "t1", transaction_date: "2026-09-24", description: "PIX RECEBIDO", amount: 800,
  transaction_type: "credit" as const, counterparty_name: "MARIA SILVA", counterparty_document: "12345678901",
};
const proposta = {
  kind: "create_receivable", suggestedCategory: "Serviços prestados", dreGroup: "receita",
  confidence: 95, appliedRuleId: "r-in", suggestedSupplierId: null,
};

Deno.test("regra de entrada: o cliente da regra vence o dono do CPF, com a prova 'regra sua'", () => {
  const l = identificarLinha(pixDaMaria, { ...proposta, suggestedClientId: "c-joao" }, ctx);
  assertEquals(l.clientId, "c-joao");
  const cliente = (l.evidencia as any).cliente;
  assertEquals([cliente.id, cliente.nome, cliente.por], ["c-joao", "João da Silva", "regra"]);
  assertStringIncludes(l.frases.join(" · "), "Regra sua: este CPF/CNPJ é do cliente João da Silva");
});

Deno.test("sem regra, o CPF identifica quem pagou", () => {
  const l = identificarLinha(pixDaMaria, { ...proposta, appliedRuleId: null }, ctx);
  assertEquals(l.clientId, "c-maria");
  assertEquals((l.evidencia as any).cliente.por, "documento");
});

Deno.test("cliente da regra que não existe mais não entra — vale o que o documento diz", () => {
  const l = identificarLinha(pixDaMaria, { ...proposta, suggestedClientId: "c-apagado" }, ctx);
  assertEquals(l.clientId, "c-maria");
});

Deno.test("na saída, a regra de entrada não dá cliente a ninguém", () => {
  const l = identificarLinha({ ...pixDaMaria, transaction_type: "debit" },
    { ...proposta, kind: "create_payable", suggestedClientId: "c-joao" }, ctx);
  assertNotEquals(l.clientId, "c-joao");
});

Deno.test("sem o contexto (leitura falhou), o cliente da regra ainda chega à entrada", () => {
  const l = identificarLinha(pixDaMaria, { ...proposta, suggestedClientId: "c-joao" }, null);
  assertEquals(l.clientId, "c-joao");
  assert(l.evidencia === null);
});

// ─── Pix para o SÓCIO segue a última escolha do dono (20/10/2026, spec-papelada-fix.md B2) ───
// As 13 aprovações reais de Pix para o sócio (reconciliation_log 'aprovou_proposta', produção, 20/10/2026), da
// mais nova para a mais velha: a última foi "Retirada de sócio" (28/09 14:58), depois de uma "Outras despesas"
// e de várias "Pró-labore e retirada" (categoria que não existe mais no plano).
const DECISOES_DO_SOCIO: Array<[string, string]> = [
  ["2026-09-28 14:58:26.508889+00", "Retirada de sócio"],
  ["2026-09-28 14:56:25.270496+00", "Retirada de sócio"],
  ["2026-09-28 14:56:25.117851+00", "Pró-labore"],
  ["2026-09-28 14:56:24.935332+00", "Pró-labore"],
  ["2026-09-28 14:56:11.115978+00", "Retirada de sócio"],
  ["2026-09-28 14:56:03.250447+00", "Outras despesas"],
  ["2026-09-28 14:55:47.53884+00", "Pró-labore"],
  ["2026-09-25 15:01:15.414553+00", "Pró-labore e retirada"],
  ["2026-09-25 15:01:15.222576+00", "Pró-labore e retirada"],
  ["2026-09-25 15:01:15.090854+00", "Pró-labore e retirada"],
  ["2026-09-25 15:01:14.950581+00", "Pró-labore e retirada"],
  ["2026-09-25 15:01:14.815488+00", "Pró-labore e retirada"],
  ["2026-08-09 13:16:40.792535+00", "Pró-labore e retirada"],
];
const ATIVAS = new Set(["Pró-labore", "Retirada de sócio", "Outras despesas", "Diárias de freelancers"]);

Deno.test("B2: a última escolha do dono para o sócio, da trilha real — 'Outras despesas' e categoria extinta não contam", () => {
  const logs = DECISOES_DO_SOCIO.map(([em, categoria], i) => ({ payable_id: `pg${i}`, ocorrido_em: em, depois: { categoria } }));
  const dono = new Map(logs.map((l) => [String(l.payable_id), "fav-socio"]));
  // embaralhado: a ordem de leitura não muda a resposta
  const m = ultimaEscolhaPorFavorecido([...logs].reverse(), dono, ATIVAS);
  assertEquals(m.get("fav-socio"), { categoria: "Retirada de sócio", em: "2026-09-28 14:58:26.508889+00" });
  // se a última tivesse sido "Outras despesas", vale a anterior de verdade
  const comOutras = [{ payable_id: "pgX", ocorrido_em: "2026-10-01 10:00:00+00", depois: { categoria: "Outras despesas" } }, ...logs];
  assertEquals(ultimaEscolhaPorFavorecido(comOutras, new Map([...dono, ["pgX", "fav-socio"]]), ATIVAS).get("fav-socio")?.categoria, "Retirada de sócio");
  // despesa de outro favorecido não entra
  assertEquals(ultimaEscolhaPorFavorecido(logs, new Map(), ATIVAS).size, 0);
});

const CPF_DO_SOCIO = "11122233344";
const ctxDoSocio: ContextoDeIdentificacao = {
  indice: indexarContrapartes({
    fornecedores: [], clientes: [], historico: [],
    favorecidos: [
      { id: "fav-socio", name: "Sócio da Empresa", document: CPF_DO_SOCIO },
      { id: "fav-diarista", name: "Diarista Fulano", document: "55566677788" },
    ],
  }),
  candidatos: [],
  categoriaDoFavorecido: new Map([["fav-socio", "Pró-labore"]]),
  drePorCategoria: new Map([["Pró-labore", "despesa_operacional"], ["Retirada de sócio", "nao_operacional"]]),
  ultimaEscolhaDoSocio: new Map([["fav-socio", { categoria: "Retirada de sócio", em: "2026-09-28 14:58:26.508889+00" }]]),
};
// Um dos Pix reais de outubro (05/10, R$ 500): o motor sugeria Pró-labore pela maioria dividida (5 de 9, conf. 75).
const pixParaOSocio = {
  id: "t-socio", transaction_date: "2026-10-05", description: "Pix enviado para Socio da Empresa", amount: 500,
  transaction_type: "debit" as const, counterparty_name: null, counterparty_document: CPF_DO_SOCIO,
};
const peloHistorico = {
  kind: "create_payable", suggestedCategory: "Pró-labore", dreGroup: "despesa_operacional",
  confidence: 75, appliedRuleId: null, suggestedSupplierId: null,
};

Deno.test("B2: Pix para o sócio sugere a última escolha (Retirada de sócio), com o porquê", () => {
  const l = identificarLinha(pixParaOSocio, peloHistorico, ctxDoSocio);
  assertEquals([l.payeeId, l.categoria, l.dreGroup], ["fav-socio", "Retirada de sócio", "nao_operacional"]);
  assertStringIncludes(l.frases.join(" · "),
    "Da última vez (28/09) você lançou Pix para Sócio da Empresa como Retirada de sócio: a sugestão segue a sua última escolha (a separação pelo salário mínimo acerta o pró-labore do mês)");
});

Deno.test("B2: sem nada melhor (Outras despesas), a última escolha vence também a categoria padrão do cadastro", () => {
  const l = identificarLinha(pixParaOSocio, { ...peloHistorico, suggestedCategory: "Outras despesas", confidence: 30 }, ctxDoSocio);
  assertEquals(l.categoria, "Retirada de sócio");
});

Deno.test("B2: regra sua continua vencendo; última escolha igual à sugestão não muda nada nem fala", () => {
  const comRegra = identificarLinha(pixParaOSocio, { ...peloHistorico, appliedRuleId: "r1" }, ctxDoSocio);
  assertEquals(comRegra.categoria, "Pró-labore");
  const igual = identificarLinha(pixParaOSocio, { ...peloHistorico, suggestedCategory: "Retirada de sócio", dreGroup: "nao_operacional" }, ctxDoSocio);
  assertEquals(igual.categoria, "Retirada de sócio");
  assert(!igual.frases.join(" · ").includes("Da última vez"));
});

Deno.test("B2: só o sócio — outro favorecido, entrada e contexto sem a leitura ficam como antes", () => {
  const diarista = identificarLinha({ ...pixParaOSocio, counterparty_document: "55566677788" }, { ...peloHistorico, suggestedCategory: "Diárias de freelancers" }, ctxDoSocio);
  assertEquals(diarista.categoria, "Diárias de freelancers");
  const entrada = identificarLinha({ ...pixParaOSocio, transaction_type: "credit" }, { ...peloHistorico, kind: "create_receivable", suggestedCategory: "Aporte de sócio" }, ctxDoSocio);
  assertEquals(entrada.categoria, "Aporte de sócio");
  const semLeitura = identificarLinha(pixParaOSocio, peloHistorico, { ...ctxDoSocio, ultimaEscolhaDoSocio: undefined });
  assertEquals(semLeitura.categoria, "Pró-labore");
});
