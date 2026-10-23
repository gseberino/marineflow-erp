// Identificação da linha do Extrato com a regra de ENTRADA — "o Pix do CPF/CNPJ X é do cliente Y"
// (resposta 18 do dono, 26/09/2026): o cliente da regra vence o dono do documento, com a prova
// "regra sua", e continua sugestão.
import { assert, assertEquals, assertNotEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  carregarContexto, clienteQueAprovacaoUsa, FRASE_DA_REGRA_SEM_CONTEXTO, identificarLinha, MOTOR_DA_FILA,
  PEDIDO_DE_ESCOLHA_DO_CLIENTE, pedidoDeConfirmacaoDoCliente, type ContextoDeIdentificacao, ultimaEscolhaPorFavorecido,
} from "./identificacao.ts";
import {
  indexarContrapartes, pagadoresDoDocumento, perguntaDeQuemEValida, RELACAO_DO_NOME_IDENTICO, situacaoDoClienteSugerido,
  vetoDoPagador, type CadastroParaIdentificar,
} from "../_shared/banking/contraparte.ts";

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

// Revisão de 23/10/2026, 4ª rodada (C6): sem o contexto não dá para conferir pagadores nem vetos — o "não" do dono vence
// a regra antiga, então a regra de cliente não preenche a entrada: fica sem cliente, com a pergunta, e sem a marca do
// motor (a varredura diária a refaz quando o contexto voltar).
Deno.test("sem o contexto (leitura falhou), a regra de cliente NÃO preenche a entrada — pergunta, e a aprovação não usa ninguém", () => {
  const l = identificarLinha(pixDaMaria, { ...proposta, suggestedClientId: "c-joao" }, null);
  assertEquals(l.clientId, null);
  assert(l.evidencia === null, "sem a marca do motor: a varredura refaz");
  assertEquals(l.frases, [FRASE_DA_REGRA_SEM_CONTEXTO]);
  assertStringIncludes(l.frases[0], "não deu para conferir os pagadores que você guardou nem os que recusou — escolha o cliente");
  assertEquals(clienteQueAprovacaoUsa({ suggested_client_id: l.clientId, evidencia: l.evidencia as any }), null);
  // sem regra de cliente: nada a perguntar (como antes)
  assertEquals(identificarLinha(pixDaMaria, { ...proposta, appliedRuleId: null }, null).frases, []);
  // a saída continua com o fornecedor do motor de propostas (a regra de fornecedor não muda)
  const saida = identificarLinha({ ...pixDaMaria, transaction_type: "debit" },
    { ...proposta, kind: "create_payable", suggestedSupplierId: "f-1", suggestedClientId: "c-joao" }, null);
  assertEquals([saida.supplierId, saida.clientId, saida.frases], ["f-1", null, []]);
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

// ─── Pagadores conhecidos (leva 8, 22/10/2026) ───────────────────────────────────────────────────
// Um cliente de banco de mentira: toda tabela volta vazia, menos as que o teste diz. Encadeia qualquer método do
// PostgREST e responde quando é aguardado (como o supabase-js).
function bancoDeMentira(tabelas: Record<string, { data: unknown; error: unknown }>, lidas: string[] = []) {
  return {
    from(t: string) {
      lidas.push(t);
      const r = tabelas[t] ?? { data: [], error: null };
      const cadeia: Record<string | symbol, unknown> = new Proxy({}, {
        get(_o, k) {
          if (k === "then") return (ok: (v: unknown) => unknown, nok: (e: unknown) => unknown) => Promise.resolve(r).then(ok, nok);
          if (k === "maybeSingle" || k === "single") {
            return () => Promise.resolve({ data: Array.isArray(r.data) ? (r.data[0] ?? null) : r.data, error: r.error });
          }
          return () => cadeia;
        },
      });
      return cadeia;
    },
    rpc: () => Promise.resolve({ data: null, error: null }),
  } as never;
}

const CLIENTES = {
  data: [
    { id: "c-maria", name: "MARIA SILVA", cpf_cnpj: "123.456.789-01", active: true },
    { id: "c-joao", name: "João da Silva", cpf_cnpj: "999.888.777-66", active: true },
    { id: "c-antigo", name: "Cliente Desativado", cpf_cnpj: null, active: false },
  ],
  error: null,
};
// O cônjuge da Maria paga por ela; um parente pagava pelo cliente que foi desativado. O dono recusou um CPF para o
// João e pausou outro para o cliente desativado; um proposto (sem o SIM) não vale nada para o motor.
const PAGADORES = {
  data: [
    { documento: "55566677788", client_id: "c-maria", relacao: "conjuge", situacao: "confirmado", confirmado_em: "2026-10-22T15:00:00Z" },
    { documento: "44433322211", client_id: "c-antigo", relacao: "parente", situacao: "confirmado", confirmado_em: "2026-10-01T15:00:00Z" },
    { documento: "77788899900", client_id: "c-joao", relacao: "outro", situacao: "recusado", confirmado_em: null },
    { documento: "66655544433", client_id: "c-antigo", relacao: "parente", situacao: "pausado", confirmado_em: "2026-10-01T15:00:00Z" },
    { documento: "11199988877", client_id: "c-maria", relacao: "parente", situacao: "proposto", confirmado_em: null },
  ],
  error: null,
};
const pixDoConjuge = { ...pixDaMaria, id: "t-conj", counterparty_name: "JOSE CONJUGE", counterparty_document: "55566677788" };
const semRegra = { ...proposta, appliedRuleId: null, confidence: 60 };

Deno.test("leva 8: MOTOR_DA_FILA = 3 (a varredura refaz as entradas com o 'cadastrar' antigo) e vai na evidência", () => {
  assertEquals(MOTOR_DA_FILA, 3);
  assertEquals((identificarLinha(pixDaMaria, { ...proposta, appliedRuleId: null }, ctx).evidencia as any).motor, 3);
});

Deno.test("leva 8: pagador conhecido de um cliente ativo vira SUGESTÃO com motivo (o cliente sugerido pede o SIM)", async () => {
  const lidas: string[] = [];
  const c = await carregarContexto(bancoDeMentira({ clients: CLIENTES, pagadores_do_cliente: PAGADORES }, lidas));
  assert(lidas.includes("pagadores_do_cliente"));
  const l = identificarLinha(pixDoConjuge, semRegra, c);
  assertEquals(l.clientId, "c-maria");
  const cliente = (l.evidencia as any).cliente;
  assertEquals([cliente.por, cliente.relacao], ["pagador_conhecido", "conjuge"]);
  assertStringIncludes(l.frases.join(" · "), "Pago pelo cônjuge de MARIA SILVA, guardado por você em 22/10 — confira");
  assertEquals((l.evidencia as any).cadastrar, undefined);
  assertEquals((l.evidencia as any).deQuemE, undefined);
  // a aprovação não usa este cliente sem o SIM, e diz o que fazer
  const naFila = { suggested_client_id: l.clientId, evidencia: l.evidencia as any };
  assertEquals(clienteQueAprovacaoUsa(naFila), null);
  assertEquals(pedidoDeConfirmacaoDoCliente(naFila),
    'Confirme o cliente: este pagador já pagou por MARIA SILVA — responda "Sim, é do MARIA SILVA" ou escolha outro');
});

Deno.test("leva 8: pagador de cliente DESATIVADO é ignorado — a entrada pergunta de quem é", async () => {
  const c = await carregarContexto(bancoDeMentira({ clients: CLIENTES, pagadores_do_cliente: PAGADORES }));
  const l = identificarLinha({ ...pixDoConjuge, counterparty_name: "PARENTE", counterparty_document: "44433322211" }, semRegra, c);
  assertEquals(l.clientId, null);
  assertEquals((l.evidencia as any).deQuemE, { documento: "44433322211", nome: "PARENTE", candidatos: [] });
  assertEquals((l.evidencia as any).cadastrar, undefined);
});

Deno.test("revisão 23/10: o motor lê confirmados (cliente ativo) e os VETOS (recusado, pausado); o proposto não entra", async () => {
  const c = await carregarContexto(bancoDeMentira({ clients: CLIENTES, pagadores_do_cliente: PAGADORES }));
  assertEquals(c.pagadoresIndisponiveis, false);
  assertEquals(pagadoresDoDocumento(c.indice, "55566677788").map((p) => p.cliente.id), ["c-maria"]);
  assertEquals(vetoDoPagador(c.indice, "77788899900", "c-joao"), "recusado");
  // o veto vale para qualquer cliente (só tira sugestão), também o desativado
  assertEquals(vetoDoPagador(c.indice, "66655544433", "c-antigo"), "pausado");
  // proposto: nem sugere, nem veta
  assertEquals(pagadoresDoDocumento(c.indice, "11199988877"), []);
  assertEquals(vetoDoPagador(c.indice, "11199988877", "c-maria"), null);
});

Deno.test("leva 8: leitura dos pagadores FALHA — o contexto marca a falha, e a entrada cai na pergunta (nunca em cliente presumido nem em cadastrar)", async () => {
  const c = await carregarContexto(bancoDeMentira({
    clients: CLIENTES,
    pagadores_do_cliente: { data: null, error: { message: 'relation "public.pagadores_do_cliente" does not exist' } },
  }));
  assertEquals(c.indice.pagadorPorDoc.size, 0);
  assertEquals(c.pagadoresIndisponiveis, true);
  assertEquals(c.indice.pagadoresIndisponiveis, true);
  const l = identificarLinha(pixDoConjuge, semRegra, c);
  assertEquals(l.clientId, null);
  assertEquals((l.evidencia as any).deQuemE, { documento: "55566677788", nome: "JOSE CONJUGE", candidatos: [] });
  assertEquals((l.evidencia as any).cadastrar, undefined);
  // a entrada sai SEM a marca do motor: a varredura diária a refaz quando a leitura voltar
  assertEquals((l.evidencia as any).motor, undefined);
  // e o resto do contexto continua valendo: o CPF da Maria ainda identifica a Maria
  assertEquals(identificarLinha(pixDaMaria, semRegra, c).clientId, "c-maria");
  // a saída não depende dos pagadores: continua com a marca
  const saida = identificarLinha({ ...pixDoConjuge, transaction_type: "debit" }, { ...semRegra, kind: "create_payable" }, c);
  assertEquals((saida.evidencia as any).motor, 3);
});

Deno.test("revisão 23/10: leitura dos pagadores FALHA e há regra de cliente — a regra não decide sozinha: pergunta, com o cliente da regra como candidato", async () => {
  const c = await carregarContexto(bancoDeMentira({
    clients: CLIENTES,
    pagadores_do_cliente: { data: null, error: { message: "erro passageiro do PostgREST" } },
  }));
  const l = identificarLinha(pixDoConjuge, { ...proposta, suggestedClientId: "c-joao" }, c);
  assertEquals(l.clientId, null);
  const ev = l.evidencia as any;
  assertEquals(ev.cliente, undefined);
  assertEquals(ev.deQuemE, {
    documento: "55566677788", nome: "JOSE CONJUGE",
    candidatos: [{ id: "c-joao", nome: "João da Silva", relacao: "regra antiga" }],
  });
  assertEquals(ev.motor, undefined);
  // a categoria da regra continua valendo
  assertEquals([l.categoria, l.dreGroup], ["Serviços prestados", "receita"]);
  const frases = l.frases.join(" · ");
  assertStringIncludes(frases,
    "De quem é este pagamento? Uma regra antiga diz que este CPF/CNPJ é do cliente João da Silva, mas não deu para conferir os pagadores que você guardou agora — escolha o cliente");
  assert(!frases.includes("Regra sua: este CPF/CNPJ é do cliente"));
  // a aprovação não tem cliente para usar sem o SIM
  assertEquals(clienteQueAprovacaoUsa({ suggested_client_id: l.clientId, evidencia: ev }), null);
  // o documento é de um cliente (a Maria): ela também é candidata
  const daMaria = identificarLinha(pixDaMaria, { ...proposta, suggestedClientId: "c-joao" }, c);
  assertEquals((daMaria.evidencia as any).deQuemE.candidatos, [
    { id: "c-joao", nome: "João da Silva", relacao: "regra antiga" },
    { id: "c-maria", nome: "MARIA SILVA", relacao: "documento do cliente" },
  ]);
});

Deno.test("revisão 23/10: leitura dos pagadores FALHA — o histórico do cliente sem documento pede o SIM (o atalho do nome idêntico fica desligado)", () => {
  const cad = (pagadoresIndisponiveis: boolean): ContextoDeIdentificacao => ({
    ...ctx,
    pagadoresIndisponiveis,
    indice: indexarContrapartes({
      fornecedores: [], favorecidos: [],
      clientes: [{ id: "c-pedro", name: "Pedro Souza", cpf_cnpj: null }],
      historico: [{ documento: "33322211100", lado: "entrada", client_id: "c-pedro" }],
      pagadoresIndisponiveis,
    }),
  });
  const pix = { ...pixDaMaria, counterparty_name: "PEDRO SOUZA", counterparty_document: "33322211100" };
  const ok = identificarLinha(pix, semRegra, cad(false));
  assertEquals([(ok.evidencia as any).cliente.por, clienteQueAprovacaoUsa({ suggested_client_id: ok.clientId, evidencia: ok.evidencia as any })],
    ["nome_identico", "c-pedro"]);
  const falhou = identificarLinha(pix, semRegra, cad(true));
  assertEquals((falhou.evidencia as any).cliente.por, "historico");
  assertEquals(clienteQueAprovacaoUsa({ suggested_client_id: falhou.clientId, evidencia: falhou.evidencia as any }), null);
});

Deno.test("leva 8: regra de entrada sua vence a pergunta (deQuemE zerado)", () => {
  const l = identificarLinha({ ...pixDaMaria, counterparty_document: "11122233344", counterparty_name: "ALGUEM" },
    { ...proposta, suggestedClientId: "c-joao" }, ctx);
  assertEquals(l.clientId, "c-joao");
  assertEquals((l.evidencia as any).cliente.por, "regra");
  assertEquals((l.evidencia as any).deQuemE, undefined);
  // com a leitura dos pagadores funcionando, a linha leva a marca do motor
  assertEquals((l.evidencia as any).motor, 3);
  assert(!l.frases.join(" · ").includes("De quem é este pagamento?"));
});

// ─── O "não" do dono: pagador RECUSADO ou PAUSADO (revisão de 23/10/2026, item 1) ─────────────────────────────────
// O dono disse que este documento não paga por aquele cliente. As mensagens prometem "não volta a ser sugerido" — o
// motor cumpre: nem o histórico unânime, nem o nome idêntico, nem o pagador conhecido, nem a regra antiga o sugerem.
const CPF_DO_TERCEIRO = "12312312399";
function ctxComVeto(
  vetados: NonNullable<CadastroParaIdentificar["vetados"]>,
  extra: Partial<CadastroParaIdentificar> = {},
): ContextoDeIdentificacao {
  return {
    ...ctx,
    indice: indexarContrapartes({
      fornecedores: [], favorecidos: [],
      clientes: [
        { id: "c-joao", name: "João da Silva", cpf_cnpj: "999.888.777-66" },
        { id: "c-maria", name: "MARIA SILVA", cpf_cnpj: "123.456.789-01" },
        { id: "c-pedro", name: "Pedro Souza", cpf_cnpj: null },
      ],
      // este CPF já pagou 2× pelo João
      historico: [
        { documento: CPF_DO_TERCEIRO, lado: "entrada", client_id: "c-joao" },
        { documento: CPF_DO_TERCEIRO, lado: "entrada", client_id: "c-joao" },
      ],
      vetados,
      ...extra,
    }),
  };
}
const pixDoTerceiro = { ...pixDaMaria, id: "t-terc", counterparty_name: "TERCEIRO QUALQUER", counterparty_document: CPF_DO_TERCEIRO };

Deno.test("veto: histórico unânime de um cliente RECUSADO não sugere — a linha pergunta, e diz por quê", () => {
  // sem o veto: o histórico sugere o João (pedindo o SIM)
  const antes = identificarLinha(pixDoTerceiro, semRegra, ctxComVeto([]));
  assertEquals([antes.clientId, (antes.evidencia as any).cliente.por], ["c-joao", "historico"]);
  const l = identificarLinha(pixDoTerceiro, semRegra, ctxComVeto([{ documento: CPF_DO_TERCEIRO, client_id: "c-joao", situacao: "recusado" }]));
  assertEquals(l.clientId, null);
  const ev = l.evidencia as any;
  assertEquals(ev.cliente, undefined);
  assertEquals(ev.deQuemE, {
    documento: CPF_DO_TERCEIRO, nome: "TERCEIRO QUALQUER", candidatos: [],
    vetados: [{ id: "c-joao", nome: "João da Silva", situacao: "recusado" }],
  });
  const frases = l.frases.join(" · ");
  assertStringIncludes(frases, "De quem é este pagamento?");
  assertStringIncludes(frases, "Você recusou este CPF como pagador de João da Silva: João da Silva não é sugerido");
  assert(!frases.includes("já pagou 2× em nome de João da Silva"));
  assertEquals(clienteQueAprovacaoUsa({ suggested_client_id: l.clientId, evidencia: ev }), null);
  assertEquals(ev.motor, 3);
});

Deno.test("veto: PAUSADO também tira a sugestão (até o administrador reativar); reativado, volta a sugerir", () => {
  const l = identificarLinha(pixDoTerceiro, semRegra, ctxComVeto([{ documento: CPF_DO_TERCEIRO, client_id: "c-joao", situacao: "pausado" }]));
  assertEquals(l.clientId, null);
  assertEquals((l.evidencia as any).deQuemE.vetados, [{ id: "c-joao", nome: "João da Silva", situacao: "pausado" }]);
  assertStringIncludes(l.frases.join(" · "), "Você pausou este CPF como pagador de João da Silva: João da Silva não é sugerido até o administrador reativar");
  // reativado = confirmado de novo: pagador conhecido, com o SIM
  const reativado = identificarLinha(pixDoTerceiro, semRegra, ctxComVeto([], {
    pagadores: [{ documento: CPF_DO_TERCEIRO, client_id: "c-joao", relacao: "parente", confirmado_em: "2026-10-23T15:00:00Z" }],
  }));
  assertEquals([reativado.clientId, (reativado.evidencia as any).cliente.por], ["c-joao", "pagador_conhecido"]);
});

Deno.test("veto: o histórico vetado não deixa o nome idêntico de OUTRO cliente decidir sem pergunta", () => {
  const l = identificarLinha({ ...pixDoTerceiro, counterparty_name: "PEDRO SOUZA" }, semRegra,
    ctxComVeto([{ documento: CPF_DO_TERCEIRO, client_id: "c-joao", situacao: "recusado" }]));
  assertEquals(l.clientId, null);
  assertEquals((l.evidencia as any).deQuemE.candidatos, []);
});

Deno.test("veto: nome idêntico de um cliente vetado para este CPF não identifica", () => {
  const pix = { ...pixDaMaria, counterparty_name: "PEDRO SOUZA", counterparty_document: "45645645600" };
  assertEquals(identificarLinha(pix, semRegra, ctxComVeto([])).clientId, "c-pedro");
  const l = identificarLinha(pix, semRegra, ctxComVeto([{ documento: "45645645600", client_id: "c-pedro", situacao: "recusado" }]));
  assertEquals(l.clientId, null);
  assertEquals((l.evidencia as any).deQuemE.vetados.map((v: any) => v.id), ["c-pedro"]);
});

Deno.test("veto: pagador de dois clientes com um vetado — sugere o que sobra (pagador conhecido, com o SIM)", () => {
  const MARINA = "33444555000166";
  const c = ctxComVeto([{ documento: "33444555000247", client_id: "c-pedro", situacao: "recusado" }], {
    pagadores: [
      { documento: MARINA, client_id: "c-maria", relacao: "marina" },
      { documento: MARINA, client_id: "c-pedro", relacao: "marina" },
    ],
  });
  const l = identificarLinha({ ...pixDaMaria, counterparty_name: "MARINA DO PORTO", counterparty_document: MARINA }, semRegra, c);
  assertEquals(l.clientId, "c-maria");
  assertEquals((l.evidencia as any).cliente.por, "pagador_conhecido");
  assertEquals(clienteQueAprovacaoUsa({ suggested_client_id: l.clientId, evidencia: l.evidencia as any }), null);
});

Deno.test("veto: regra antiga cujo cliente o dono vetou para este documento não escolhe o cliente", () => {
  const regraDoJoaoAqui = { ...proposta, suggestedClientId: "c-joao" };
  const l = identificarLinha(pixDoTerceiro, regraDoJoaoAqui,
    ctxComVeto([{ documento: CPF_DO_TERCEIRO, client_id: "c-joao", situacao: "recusado" }]));
  assertEquals(l.clientId, null);
  const ev = l.evidencia as any;
  assertEquals(ev.cliente, undefined);
  assertEquals(ev.deQuemE.candidatos, []);
  assertEquals([l.categoria, l.dreGroup], ["Serviços prestados", "receita"]);
  assertStringIncludes(l.frases.join(" · "),
    "Uma regra antiga diz que este CPF/CNPJ é do cliente João da Silva, mas você recusou quem pagou como pagador de João da Silva: a regra não escolhe o cliente");
  assertEquals(clienteQueAprovacaoUsa({ suggested_client_id: l.clientId, evidencia: ev }), null);
  // com um pagador confirmado de OUTRO cliente, ele é a sugestão (com o SIM) — o vetado nem entra como candidato
  const comOutro = identificarLinha(pixDoTerceiro, regraDoJoaoAqui, ctxComVeto(
    [{ documento: CPF_DO_TERCEIRO, client_id: "c-joao", situacao: "pausado" }],
    { pagadores: [{ documento: CPF_DO_TERCEIRO, client_id: "c-maria", relacao: "conjuge" }] },
  ));
  assertEquals([comOutro.clientId, (comOutro.evidencia as any).cliente.por], ["c-maria", "pagador_conhecido"]);
  assertEquals((comOutro.evidencia as any).deQuemE, undefined);
});

Deno.test("leva 8: sem nada, a entrada pergunta de quem é — com a frase no motivo", () => {
  const l = identificarLinha({ ...pixDaMaria, counterparty_document: "11122233344", counterparty_name: "ALGUEM" },
    { ...proposta, appliedRuleId: null }, ctx);
  assertEquals(l.clientId, null);
  assertEquals((l.evidencia as any).deQuemE, { documento: "11122233344", nome: "ALGUEM", candidatos: [] });
  assertStringIncludes(l.frases.join(" · "), "De quem é este pagamento?");
});

// ─── Regra ANTIGA de outro cliente × pagador confirmado (revisão de 22/10/2026, item 3) ───────────────────────────
// A regra "o CPF/CNPJ X é do cliente Y" é antiga; o dono confirmou X como pagador de OUTRO cliente. A regra não
// decide mais o cliente em silêncio: a linha pergunta "de quem é?", com Y e os clientes do pagador como candidatos.
const CNPJ_DA_EQUIT = "04754513000149";
function ctxComPagadores(pagadores: Array<{ documento: string; client_id: string; relacao: string; confirmado_em?: string | null }>): ContextoDeIdentificacao {
  return {
    ...ctx,
    indice: indexarContrapartes({
      fornecedores: [], favorecidos: [], historico: [],
      clientes: [
        { id: "c-joao", name: "João da Silva", cpf_cnpj: "999.888.777-66" },
        { id: "c-maria", name: "MARIA SILVA", cpf_cnpj: "123.456.789-01" },
        { id: "c-pedro", name: "Pedro Souza", cpf_cnpj: null },
      ],
      pagadores,
    }),
  };
}
const pixDaEquit = { ...pixDaMaria, id: "t-equit", counterparty_name: "EQUIT ADMINISTRACAO DE BENS LTDA", counterparty_document: CNPJ_DA_EQUIT };
const regraDoJoao = { ...proposta, suggestedClientId: "c-joao" };

Deno.test("item 3: regra antiga de OUTRO cliente não vence o pagador confirmado — vira a pergunta, com os dois candidatos", () => {
  const c = ctxComPagadores([{ documento: CNPJ_DA_EQUIT, client_id: "c-maria", relacao: "empresa_do_cliente", confirmado_em: "2026-10-22T15:00:00Z" }]);
  const l = identificarLinha(pixDaEquit, regraDoJoao, c);
  assertEquals(l.clientId, null);
  const ev = l.evidencia as any;
  assertEquals(ev.cliente, undefined);
  assertEquals(ev.cadastrar, undefined);
  assertEquals(ev.deQuemE, {
    documento: CNPJ_DA_EQUIT, nome: "EQUIT ADMINISTRACAO DE BENS LTDA",
    candidatos: [
      { id: "c-joao", nome: "João da Silva", relacao: "regra antiga" },
      { id: "c-maria", nome: "MARIA SILVA", relacao: "empresa_do_cliente" },
    ],
  });
  // a categoria da regra continua valendo
  assertEquals([l.categoria, l.dreGroup], ["Serviços prestados", "receita"]);
  const frases = l.frases.join(" · ");
  assertStringIncludes(frases,
    "De quem é este pagamento? Uma regra antiga diz que este CPF/CNPJ é do cliente João da Silva, mas você guardou quem pagou como pagador de MARIA SILVA — escolha o cliente");
  assert(!frases.includes("Regra sua: este CPF/CNPJ é do cliente"));
  assert(!frases.includes("paga por mais de um cliente"));
  // a aprovação não tem cliente para usar sozinha
  assertEquals(clienteQueAprovacaoUsa({ suggested_client_id: l.clientId, evidencia: ev }), null);
});

Deno.test("item 3: o pagador guardado pela FILIAL (raiz do CNPJ) também tira a decisão da regra antiga", () => {
  const c = ctxComPagadores([{ documento: "04754513000230", client_id: "c-maria", relacao: "empresa_do_cliente" }]);
  const l = identificarLinha(pixDaEquit, regraDoJoao, c);
  assertEquals(l.clientId, null);
  assertEquals((l.evidencia as any).deQuemE.candidatos.map((x: any) => x.id), ["c-joao", "c-maria"]);
});

Deno.test("item 3: pagador do MESMO cliente da regra (ainda não consolidada) — a regra decide como antes", () => {
  const c = ctxComPagadores([{ documento: CNPJ_DA_EQUIT, client_id: "c-joao", relacao: "empresa_do_cliente" }]);
  const l = identificarLinha(pixDaEquit, regraDoJoao, c);
  assertEquals(l.clientId, "c-joao");
  assertEquals((l.evidencia as any).cliente.por, "regra");
  assertEquals((l.evidencia as any).deQuemE, undefined);
});

Deno.test("item 3: a marina paga pelo cliente da regra E por outro — pergunta; o da regra aparece com a relação de pagador", () => {
  const c = ctxComPagadores([
    { documento: CNPJ_DA_EQUIT, client_id: "c-joao", relacao: "marina" },
    { documento: CNPJ_DA_EQUIT, client_id: "c-pedro", relacao: "marina" },
  ]);
  const l = identificarLinha(pixDaEquit, regraDoJoao, c);
  assertEquals(l.clientId, null);
  assertEquals((l.evidencia as any).deQuemE.candidatos, [
    { id: "c-joao", nome: "João da Silva", relacao: "marina" },
    { id: "c-pedro", nome: "Pedro Souza", relacao: "marina" },
  ]);
  assertStringIncludes(l.frases.join(" · "), "como pagador de Pedro Souza — escolha o cliente");
});

Deno.test("item 3: o documento é de um cliente (cadastro feito depois) — o dono do documento também é candidato", () => {
  // O CPF da Maria guardado como pagador do Pedro (antes de a Maria ter o CPF na ficha) e uma regra antiga do João.
  const c = ctxComPagadores([{ documento: "12345678901", client_id: "c-pedro", relacao: "conjuge" }]);
  const l = identificarLinha(pixDaMaria, regraDoJoao, c);
  assertEquals(l.clientId, null);
  assertEquals((l.evidencia as any).deQuemE.candidatos, [
    { id: "c-joao", nome: "João da Silva", relacao: "regra antiga" },
    { id: "c-pedro", nome: "Pedro Souza", relacao: "conjuge" },
    { id: "c-maria", nome: "MARIA SILVA", relacao: "documento do cliente" },
  ]);
});

Deno.test("item 3: sem o nome no extrato, a pergunta usa o nome da descrição", () => {
  const c = ctxComPagadores([{ documento: CNPJ_DA_EQUIT, client_id: "c-maria", relacao: "empresa_do_cliente" }]);
  const l = identificarLinha({ ...pixDaEquit, counterparty_name: null, description: "Pix recebido de EQUIT ADM" }, regraDoJoao, c);
  assertEquals((l.evidencia as any).deQuemE.nome, "EQUIT ADM");
});

// ─── Entrada com fornecedor (simulação de 22/10/2026, P4) ────────────────────────────────────────────────────────
Deno.test("P4: entrada com fornecedor já tem dono — sem 'cadastrar' e sem a pergunta 'de quem é?'", () => {
  const c: ContextoDeIdentificacao = {
    ...ctx,
    indice: indexarContrapartes({
      fornecedores: [{ id: "f-loja", name: "LOJA NAUTICA LTDA", cnpj_cpf: "11222333000144" }],
      favorecidos: [], historico: [], clientes: [],
    }),
  };
  // devolução de um fornecedor: a regra de texto diz o fornecedor; o documento do extrato é outro
  const l = identificarLinha(
    { ...pixDaMaria, counterparty_name: "ALGUEM QUE DEVOLVEU", counterparty_document: "11122233344" },
    { ...proposta, kind: "create_receivable", suggestedSupplierId: "f-loja", fornecedorPelaRegra: true }, c);
  assertEquals(l.supplierId, "f-loja");
  assertEquals((l.evidencia as any).deQuemE, undefined);
  assertEquals((l.evidencia as any).cadastrar, undefined);
  assert(!l.frases.join(" · ").includes("De quem é este pagamento?"));
  // sem o fornecedor, a mesma linha pergunta (o zerar é por causa do fornecedor)
  const sem = identificarLinha({ ...pixDaMaria, counterparty_name: "ALGUEM QUE DEVOLVEU", counterparty_document: "11122233344" },
    { ...proposta, appliedRuleId: null }, c);
  assertEquals((sem.evidencia as any).deQuemE?.documento, "11122233344");
});

Deno.test("leva 8: o cliente que a aprovação usa sozinha — só quando a prova não pede o SIM", () => {
  const com = (por: string) => ({ suggested_client_id: "c1", evidencia: { cliente: { id: "c1", nome: "Fulano", por } } });
  assertEquals(clienteQueAprovacaoUsa(com("documento")), "c1");
  assertEquals(clienteQueAprovacaoUsa(com("nome_identico")), "c1");
  assertEquals(clienteQueAprovacaoUsa(com("regra")), "c1");
  for (const por of ["pagador_conhecido", "historico", "vinculo"]) assertEquals(clienteQueAprovacaoUsa(com(por)), null);
  assertStringIncludes(pedidoDeConfirmacaoDoCliente(com("historico"))!, "Confirme o cliente: este pagador já pagou por Fulano");
  // vínculo antigo: a recusa de sempre ("Escolha o cliente…")
  assertEquals(pedidoDeConfirmacaoDoCliente(com("vinculo")), null);
  assertEquals(pedidoDeConfirmacaoDoCliente(com("documento")), null);
  assertEquals(pedidoDeConfirmacaoDoCliente({ suggested_client_id: null, evidencia: null }), null);
});

// ─── Revisão de 23/10/2026: a ANOTAÇÃO do dono é o SIM; a prova antiga do motor não pede SIM sobre o cliente dele ──────
// _aplicar_anotacao troca suggested_client_id pelo cliente anotado (ou o da OS anotada) e MANTÉM evidencia.cliente do
// motor. Antes, a prova antiga (pagador conhecido de outro cliente) fazia a aprovação recusar o cliente que o dono disse.
Deno.test("anotação: o cliente que o dono anotou vale — a prova antiga de outro cliente não pede o SIM", async () => {
  const c = await carregarContexto(bancoDeMentira({ clients: CLIENTES, pagadores_do_cliente: PAGADORES }));
  const l = identificarLinha(pixDoConjuge, semRegra, c);
  assertEquals((l.evidencia as any).cliente.por, "pagador_conhecido");
  // O que o _aplicar_anotacao deixa na fila: "o Pix é do João" — sugerido trocado, prova do motor intacta.
  const anotada = { suggested_client_id: "c-joao", evidencia: { ...(l.evidencia as any), anotacao: { id: "a-1" } } };
  assertEquals(clienteQueAprovacaoUsa(anotada), "c-joao");
  assertEquals(clienteQueAprovacaoUsa(anotada, { cliente_id: "c-joao", os_id: null }), "c-joao");
  assertEquals(pedidoDeConfirmacaoDoCliente(anotada), null);
});

Deno.test("anotação: a que DISSE o mesmo cliente da prova é o SIM; a que só deu categoria não", () => {
  const naFila = (por: string) => ({
    suggested_client_id: "c1", evidencia: { cliente: { id: "c1", nome: "Fulano", por }, anotacao: { id: "a-1" } },
  });
  // lida da anotação: disse o cliente
  assertEquals(clienteQueAprovacaoUsa(naFila("pagador_conhecido"), { cliente_id: "c1", os_id: null }), "c1");
  assertEquals(pedidoDeConfirmacaoDoCliente(naFila("historico"), { cliente_id: "c1", os_id: null }), null);
  // OS anotada (o cliente da entrada é o da OS) — lida ou só na evidência
  assertEquals(clienteQueAprovacaoUsa(naFila("pagador_conhecido"), { cliente_id: null, os_id: "os-60" }), "c1");
  assertEquals(clienteQueAprovacaoUsa({ ...naFila("historico"), evidencia: { ...naFila("historico").evidencia, anotacao: { id: "a-1", os_id: "os-60" } } }), "c1");
  // só categoria: o cliente ainda é o palpite do motor — pede o SIM
  assertEquals(clienteQueAprovacaoUsa(naFila("pagador_conhecido"), { cliente_id: null, os_id: null }), null);
  assertStringIncludes(pedidoDeConfirmacaoDoCliente(naFila("historico"), { cliente_id: null, os_id: null })!, "Confirme o cliente");
  // sem a anotação lida (leitura que não houve), a evidência sem OS não basta
  assertEquals(clienteQueAprovacaoUsa(naFila("pagador_conhecido")), null);
  // anotação lida e não aplicada (cancelada, trocada, leitura que falhou = null): nem a OS que a evidência guarda vale
  const comOsNaEvidencia = { ...naFila("historico"), evidencia: { ...naFila("historico").evidencia, anotacao: { id: "a-1", os_id: "os-60" } } };
  assertEquals(clienteQueAprovacaoUsa(comOsNaEvidencia, null), null);
  // a anotação disse OUTRO cliente e o sugerido não é o dela: continua pedindo
  assertEquals(clienteQueAprovacaoUsa(naFila("historico"), { cliente_id: "c2", os_id: null }), null);
  // e o que não pede SIM continua sem pedir, com ou sem anotação
  assertEquals(clienteQueAprovacaoUsa(naFila("documento"), { cliente_id: null, os_id: null }), "c1");
});

// ─── Revisão de 23/10/2026, item 4: sem a leitura dos pagadores, o NOME IDÊNTICO vira pergunta ───────────────────────
Deno.test("pagadores indisponíveis: nome idêntico não identifica sozinho — pergunta, com o cliente candidato (nunca cliente sem SIM)", () => {
  const cad = (pagadoresIndisponiveis: boolean): ContextoDeIdentificacao => ({
    ...ctx,
    pagadoresIndisponiveis,
    indice: indexarContrapartes({
      fornecedores: [], favorecidos: [], historico: [],
      clientes: [{ id: "c-pedro", name: "Pedro Souza", cpf_cnpj: null }, { id: "c-joao", name: "João da Silva", cpf_cnpj: "999.888.777-66" }],
      pagadoresIndisponiveis,
    }),
  });
  const pix = { ...pixDaMaria, counterparty_name: "PEDRO SOUZA", counterparty_document: "33322211100" };
  const ok = identificarLinha(pix, semRegra, cad(false));
  assertEquals([(ok.evidencia as any).cliente.por, ok.clientId], ["nome_identico", "c-pedro"]);

  const falhou = identificarLinha(pix, semRegra, cad(true));
  assertEquals(falhou.clientId, null);
  const ev = falhou.evidencia as any;
  assertEquals(ev.cliente, undefined);
  assertEquals(ev.deQuemE, {
    documento: "33322211100", nome: "PEDRO SOUZA", candidatos: [{ id: "c-pedro", nome: "Pedro Souza", relacao: RELACAO_DO_NOME_IDENTICO }],
  });
  assertEquals(ev.motor, undefined, "sem a marca: a varredura refaz quando a leitura voltar");
  assertStringIncludes(falhou.frases.join(" · "), "O nome é idêntico ao do cliente Pedro Souza, mas não deu para conferir os pagadores");
  assertEquals(clienteQueAprovacaoUsa({ suggested_client_id: falhou.clientId, evidencia: ev }), null);

  // Com regra antiga de outro cliente: a pergunta da regra mantém o candidato do nome idêntico.
  const comRegra = identificarLinha(pix, { ...proposta, suggestedClientId: "c-joao" }, cad(true));
  assertEquals(comRegra.clientId, null);
  assertEquals((comRegra.evidencia as any).deQuemE.candidatos, [
    { id: "c-joao", nome: "João da Silva", relacao: "regra antiga" },
    { id: "c-pedro", nome: "Pedro Souza", relacao: RELACAO_DO_NOME_IDENTICO },
  ]);
});

// ─── Revisão de 23/10/2026, item 5: a pergunta que SOBRA depois da anotação ou do "É cliente novo" ─────────────────
Deno.test("pergunta que sobra: anotação ou cadastro dão o cliente, e o deQuemE gravado deixa de valer", async () => {
  const c = await carregarContexto(bancoDeMentira({ clients: CLIENTES, pagadores_do_cliente: PAGADORES }));
  const l = identificarLinha({ ...pixDoConjuge, counterparty_name: "PARENTE", counterparty_document: "44433322211" }, semRegra, c);
  const naFila = { suggested_client_id: l.clientId, evidencia: l.evidencia as any };
  assertEquals(perguntaDeQuemEValida(naFila)?.documento, "44433322211");
  // _aplicar_anotacao: sugerido = o cliente anotado; a evidência só perde o 'cadastrar' (o deQuemE fica).
  const anotada = { suggested_client_id: "c-joao", evidencia: { ...naFila.evidencia, anotacao: { id: "a-1" } } };
  assertEquals(perguntaDeQuemEValida(anotada), null);
  assertEquals(clienteQueAprovacaoUsa(anotada), "c-joao");
  // cadastrar_contraparte_do_extrato ("É cliente novo"): sugerido e prova por documento; o deQuemE fica.
  const cadastrada = {
    suggested_client_id: "c-novo",
    evidencia: { ...naFila.evidencia, cliente: { id: "c-novo", nome: "PARENTE", por: "documento", detalhe: "CPF confere com o cliente PARENTE" } },
  };
  assertEquals(perguntaDeQuemEValida(cadastrada), null);
  assertEquals(clienteQueAprovacaoUsa(cadastrada), "c-novo");
});

// ─── Revisão de 23/10/2026, 4ª rodada (A): o sugerido que NÃO é o da prova só vale com a ANOTAÇÃO que o disse ─────────
// O _aplicar_anotacao põe o cliente anotado no sugerido e mantém a prova antiga do motor. Desligar o comprovante desfaz
// a anotação (migrations 20261011302000 / 20261011303000): tiram 'anotacao' da evidência e MANTÊM o sugerido. Sem a
// anotação em vigor (desfeita, ou leitura que falhou), ninguém resolveu de quem é: a aprovação não usa NENHUM cliente
// — nem o sugerido, nem o da prova antiga — e o pedido é "Escolha o cliente…", nunca "Sim, é do <prova>".
const PROVA_ACRISIO = { id: "c-acrisio", nome: "ACRISIO", por: "pagador_conhecido" };
const anotadaTsd = { suggested_client_id: "c-tsd", evidencia: { cliente: PROVA_ACRISIO, anotacao: { id: "a-1" } } };
const desfeitaTsd = { suggested_client_id: "c-tsd", evidencia: { cliente: PROVA_ACRISIO } };

Deno.test("(A) anotação COM o cliente (lida): o sugerido anotado vale, sem o SIM — a prova antiga de outro não pede nada", () => {
  const lida = { cliente_id: "c-tsd", os_id: null };
  assertEquals(situacaoDoClienteSugerido("c-tsd", PROVA_ACRISIO, lida), "vale");
  assertEquals(clienteQueAprovacaoUsa(anotadaTsd, lida), "c-tsd");
  assertEquals(pedidoDeConfirmacaoDoCliente(anotadaTsd, lida), null);
  // a anotação disse OUTRO cliente (não o sugerido): ninguém disse o sugerido — escolher
  assertEquals(clienteQueAprovacaoUsa(anotadaTsd, { cliente_id: "c-outro", os_id: null }), null);
  assertEquals(pedidoDeConfirmacaoDoCliente(anotadaTsd, { cliente_id: "c-outro", os_id: null }), PEDIDO_DE_ESCOLHA_DO_CLIENTE);
});

Deno.test("(A) anotação com a OS (lida ou só na marca): o cliente da OS vale", () => {
  assertEquals(clienteQueAprovacaoUsa(anotadaTsd, { cliente_id: null, os_id: "os-60" }), "c-tsd");
  const marcaComOs = { ...anotadaTsd, evidencia: { ...anotadaTsd.evidencia, anotacao: { id: "a-1", os_id: "os-60" } } };
  assertEquals(clienteQueAprovacaoUsa(marcaComOs), "c-tsd");
  assertEquals(pedidoDeConfirmacaoDoCliente(marcaComOs), null);
});

Deno.test("(A) anotação DESFEITA (comprovante desligado): sugerido ≠ prova sem anotação — nenhum cliente, 'Escolha o cliente…'", () => {
  assertEquals(situacaoDoClienteSugerido("c-tsd", PROVA_ACRISIO, null), "escolher");
  assertEquals(clienteQueAprovacaoUsa(desfeitaTsd), null, "nem o sugerido da anotação cancelada");
  assertEquals(clienteQueAprovacaoUsa(desfeitaTsd, null), null);
  const pedido = pedidoDeConfirmacaoDoCliente(desfeitaTsd, null)!;
  assertEquals(pedido, PEDIDO_DE_ESCOLHA_DO_CLIENTE);
  assert(pedido.startsWith("Escolha o cliente"), pedido);
  assertEquals(pedido.includes("ACRISIO") || pedido.includes("Sim, é do"), false, "nunca 'Sim, é do <prova>'");
  // a anotação desfeita que tinha resolvido a pergunta "de quem é?" (sem prova nenhuma): também escolher
  const semProva = {
    suggested_client_id: "c-tsd", evidencia: { deQuemE: { documento: "12345678901", nome: "MARIA", candidatos: [] } } as any,
  };
  assertEquals(clienteQueAprovacaoUsa(semProva), null);
  assertEquals(pedidoDeConfirmacaoDoCliente(semProva), PEDIDO_DE_ESCOLHA_DO_CLIENTE);
  // qualquer prova de outro cliente vale o mesmo — inclusive a que não pede o SIM (documento)
  const provaPorDocumento = { suggested_client_id: "c-tsd", evidencia: { cliente: { ...PROVA_ACRISIO, por: "documento" } } };
  assertEquals(clienteQueAprovacaoUsa(provaPorDocumento), null);
});

Deno.test("(A) leitura da anotação que FALHOU (anotacaoDaLinha = null): a marca na evidência não basta — escolher", () => {
  // o servidor sempre lê: null (erro, cancelada, trocada) vence a marca {id} que a evidência guarda
  assertEquals(clienteQueAprovacaoUsa(anotadaTsd, null), null);
  assertEquals(pedidoDeConfirmacaoDoCliente(anotadaTsd, null), PEDIDO_DE_ESCOLHA_DO_CLIENTE);
  // lida e aplicada, mas sem cliente nem OS (só categoria): não disse quem é — escolher
  assertEquals(clienteQueAprovacaoUsa(anotadaTsd, { cliente_id: null, os_id: null }), null);
  // sem leitura (a tela, que só tem a marca): a marca em vigor sobre um sugerido que não é o da prova é a anotação
  assertEquals(clienteQueAprovacaoUsa(anotadaTsd), "c-tsd");
  assertEquals(situacaoDoClienteSugerido("c-tsd", PROVA_ACRISIO, { id: "a-1" }), "vale");
});

Deno.test("(A) ids IGUAIS (sugerido = prova): a anotação não muda a regra de sempre — pede o SIM ou vale pela prova", () => {
  const naFila = (por: string) => ({ suggested_client_id: "c1", evidencia: { cliente: { id: "c1", nome: "Fulano", por } } });
  // prova que pede o SIM, sem anotação (ou desfeita, ou ilegível): "Sim, é do Fulano" sobre o cliente DA PROVA, que é o sugerido
  assertEquals(situacaoDoClienteSugerido("c1", { id: "c1", por: "historico" }, null), "pede_sim");
  assertEquals(clienteQueAprovacaoUsa(naFila("historico"), null), null);
  assertStringIncludes(pedidoDeConfirmacaoDoCliente(naFila("historico"), null)!, 'responda "Sim, é do Fulano"');
  // a marca da anotação sobre o MESMO cliente (sem a leitura) continua pedindo — só a lida com o cliente é o SIM
  assertEquals(situacaoDoClienteSugerido("c1", { id: "c1", por: "historico" }, { id: "a-1" }), "pede_sim");
  assertEquals(clienteQueAprovacaoUsa(naFila("historico"), { cliente_id: "c1", os_id: null }), "c1");
  // prova que não pede o SIM: vale, com ou sem anotação
  for (const anot of [undefined, null, { cliente_id: null, os_id: null }]) {
    assertEquals(clienteQueAprovacaoUsa(naFila("documento"), anot), "c1");
    assertEquals(pedidoDeConfirmacaoDoCliente(naFila("documento"), anot), null);
  }
  // sem sugerido: nada a usar, nada a pedir (a recusa de sempre)
  assertEquals(situacaoDoClienteSugerido(null, { id: "c1", por: "historico" }), "sem_sugestao");
  assertEquals(pedidoDeConfirmacaoDoCliente({ suggested_client_id: null, evidencia: { cliente: { id: "c1", por: "historico" } } }), null);
});
