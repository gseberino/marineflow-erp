// Quem paga por um cliente, pelo assistente (leva 8, 22/10/2026, "siga pelo recomendado").
//
// O que se prova aqui:
//   - a lista de propostas: a ENTRADA traz a pergunta de_quem_e (CPF mascarado), nunca "cadastrar cliente"; o cliente
//     sugerido por pagador conhecido / histórico pede o SIM (cliente_pede_sim);
//   - aprovar: cliente_confirmado vira overrides[id].clientId = o sugerido LIDO DA FILA (nunca um nome), e recusa quando
//     não há sugestão, quando ela mudou depois do "sim" ou quando o retrato não pôde ser tirado (revisão de 23/10/2026);
//     o cartão do "sim" mostra o cliente resolvido (nunca uuid) e a trava de autonomia por argumento;
//   - cadastrar_contraparte_do_extrato recusa a entrada sem o "é cliente novo" dito (e o resumo recusa antes do "sim");
//   - guardar_pagador_do_cliente chama a RPC só com cliente, linha e relação (o documento e o nome a função tira do
//     banco), com p_autor, e o resumo do "sim" mostra o pedido resolvido com o CPF mascarado;
//   - listar_pagadores_do_cliente mascara o CPF e diz quando a leitura falha;
//   - as duas tools ficam só pela rede, a lista roda direto, guardar nunca roda sozinha.
// Rodar com:
//   deno test --allow-all supabase/functions/_shared/ai/tools/pagadores-do-cliente_test.ts
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  financeRulesTools, lerPedidoDoPagador, QUEM_FALTA_ESCOLHER, recusaDeCadastroNaEntrada, RETRATO_QUE_FALHOU,
  resumirCadastroDoExtrato, resumirClienteConfirmado, resumirGuardarPagador,
} from "./finance-rules.ts";
import { buildPendingSummary, prepararFerramentasDoTurno, resumoQueRecusa, tituloDaAcao, zerarCacheDoPerfilDeTools } from "../agent.ts";
import { PERFIL_ADMIN, PERFIL_OPERACAO, rodaDiretoPelaRede, SO_PELA_REDE } from "../perfil-operacao.ts";
import { autonomyKey, EXPLICACAO_DA_TRAVA_POR_ARGUMENTO, isAutonomyGranted, NEVER_AUTONOMOUS } from "../autonomy-policy.ts";
import { FORA_DO_WHATSAPP } from "../channel-scope.ts";
import { allTools, type Role, type ToolDef } from "./index.ts";

// deno-lint-ignore no-explicit-any
type Qualquer = any;

const ferramenta = (nome: string) => financeRulesTools.find((t) => t.name === nome) as ToolDef;

const CLIENTE = "11111111-1111-4111-8111-111111111111";
const OUTRO_CLIENTE = "22222222-2222-4222-8222-222222222222";
const PROPOSTA = "33333333-3333-4333-8333-333333333333";
const LINHA = "44444444-4444-4444-8444-444444444444";
const SAIDA = "55555555-5555-4555-8555-555555555555";

/**
 * Banco de mentira: filtra por eq/in nas linhas da tabela, devolve maybeSingle e then; guarda as chamadas de rpc.
 * `falham`: tabelas cuja leitura devolve erro.
 */
function bancoFalso(
  tabelas: Record<string, Qualquer[]> = {},
  opcoes: { falham?: string[]; rpc?: (nome: string, args: Qualquer) => { data?: unknown; error?: { message: string } | null } } = {},
) {
  const rpcs: Array<{ nome: string; args: Qualquer }> = [];
  const lidas: string[] = [];
  return {
    rpcs,
    lidas,
    rpc: (nome: string, args: Qualquer) => {
      rpcs.push({ nome, args });
      const r = opcoes.rpc?.(nome, args) ?? {};
      return Promise.resolve({ data: r.data ?? null, error: r.error ?? null });
    },
    from(tabela: string) {
      lidas.push(tabela);
      let linhas = [...(tabelas[tabela] ?? [])];
      const falha = (opcoes.falham ?? []).includes(tabela);
      const erro = { message: `falha em ${tabela}` };
      const q: Qualquer = {};
      for (const m of ["select", "order", "limit", "range", "neq", "is", "not", "gte", "lte"]) q[m] = () => q;
      q.eq = (c: string, v: unknown) => { linhas = linhas.filter((l) => l[c] === v); return q; };
      q.in = (c: string, vs: unknown[]) => { linhas = linhas.filter((l) => vs.includes(l[c])); return q; };
      q.maybeSingle = () => Promise.resolve(falha ? { data: null, error: erro } : { data: linhas[0] ?? null, error: null });
      q.then = (ok: Qualquer, ko: Qualquer) =>
        Promise.resolve(falha ? { data: null, error: erro } : { data: linhas, error: null }).then(ok, ko);
      return q;
    },
  };
}

const ctxDe = (sb: unknown, extra: Record<string, unknown> = {}) =>
  ({ sb, admin: sb, userId: "u-dono", userRole: "admin", jwt: "jwt", appOrigin: "", settings: {}, ...extra }) as never;

/** fetch de mentira para a finance-review: guarda os corpos e responde `resposta`. */
function comFetch<T>(resposta: unknown, corpo: (body: Qualquer) => void, f: () => Promise<T>): Promise<T> {
  Deno.env.set("SUPABASE_URL", "https://exemplo.supabase.co");
  const original = globalThis.fetch;
  globalThis.fetch = ((_u: unknown, init?: RequestInit) => {
    corpo(JSON.parse(String(init?.body ?? "{}")));
    return Promise.resolve(new Response(JSON.stringify(resposta), { status: 200 }));
  }) as typeof fetch;
  return f().finally(() => { globalThis.fetch = original; });
}

// ─── listar_propostas_de_lancamento ─────────────────────────────────────────────────────────────────────
const base = {
  status: "pending", suggested_category: "Serviços prestados", confidence: 70, vinculo_sugerido: null,
  suggested_service_order_id: null, suggested_purchase_order_id: null, suggested_date: "2026-10-12", suggested_amount: 1500,
};
const FILA = [
  {
    ...base, id: "e-pergunta", kind: "create_receivable", title: "Receita: MARIA SOUZA", bank_transaction_id: "t1", suggested_client_id: null,
    evidencia: { deQuemE: { documento: "12345678901", nome: "MARIA SOUZA", candidatos: [] }, motor: 3 },
  },
  {
    ...base, id: "e-pagador", kind: "create_receivable", title: "Receita: MARIA SOUZA", bank_transaction_id: "t2", suggested_client_id: CLIENTE,
    evidencia: {
      cliente: {
        id: CLIENTE, nome: "ACRISIO", por: "pagador_conhecido", relacao: "conjuge",
        detalhe: "Pago pelo cônjuge de ACRISIO, guardado por você em 12/10 — confira",
      },
      motor: 3,
    },
  },
  {
    ...base, id: "e-antiga", kind: "create_receivable", title: "Receita: MARINA X", bank_transaction_id: "t3", suggested_client_id: null,
    evidencia: { cadastrar: { tipo: "cliente", documento: "12345678000199", nome: "MARINA X LTDA" }, motor: 2 },
  },
  {
    ...base, id: "e-marina", kind: "create_receivable", title: "Receita: MARINA Y", bank_transaction_id: "t4", suggested_client_id: null,
    evidencia: {
      deQuemE: {
        documento: "98765432000155", nome: "MARINA Y",
        candidatos: [{ id: CLIENTE, nome: "ACRISIO", relacao: "marina" }, { id: OUTRO_CLIENTE, nome: "BEATRIZ", relacao: "marina" }],
      },
    },
  },
  {
    ...base, id: "e-proprio", kind: "create_receivable", title: "Receita: ACRISIO", bank_transaction_id: "t5", suggested_client_id: CLIENTE,
    evidencia: { cliente: { id: CLIENTE, nome: "ACRISIO", por: "documento", detalhe: "CPF confere com o cliente ACRISIO" } },
  },
  {
    ...base, id: "s-fornecedor", kind: "create_payable", title: "Despesa: X LTDA", bank_transaction_id: "t6", suggested_client_id: null,
    suggested_category: "Outras despesas",
    evidencia: { cadastrar: { tipo: "fornecedor", documento: "12345678000199", nome: "X LTDA" } },
  },
];

Deno.test("listar_propostas: a entrada traz de_quem_e com o CPF mascarado, nunca 'cadastrar' cliente", async () => {
  const r = await ferramenta("listar_propostas_de_lancamento").execute({}, ctxDe(bancoFalso({ finance_review_queue: FILA }))) as Qualquer;
  const por = (id: string) => r.propostas.find((p: Qualquer) => p.id === id);
  assertEquals(por("e-pergunta").de_quem_e, { nome: "MARIA SOUZA", documento: "***.456.789-**", candidatos: [] });
  assertEquals("cadastrar" in por("e-pergunta"), false);
  // Linha antiga (motor 2) com "cadastrar cliente": vira a mesma pergunta — e o CNPJ sai inteiro.
  assertEquals(por("e-antiga").de_quem_e, { nome: "MARINA X LTDA", documento: "12.345.678/0001-99", candidatos: [] });
  assertEquals("cadastrar" in por("e-antiga"), false);
  // Pagou para dois clientes: os candidatos, com a relação legível.
  assertEquals(por("e-marina").de_quem_e.candidatos, [
    { client_id: CLIENTE, nome: "ACRISIO", relacao: "Marina" }, { client_id: OUTRO_CLIENTE, nome: "BEATRIZ", relacao: "Marina" },
  ]);
  // A saída continua com o que cadastrar.
  assertEquals(por("s-fornecedor").cadastrar, { tipo: "fornecedor", documento: "12345678000199", nome: "X LTDA" });
  assertEquals("de_quem_e" in por("s-fornecedor"), false);
  // O CPF de terceiro não sai inteiro em lugar nenhum da resposta.
  assertEquals(JSON.stringify(r).includes("12345678901"), false);
});

Deno.test("listar_propostas: cliente de pagador conhecido pede o SIM, com o motivo; o do documento do próprio cliente não", async () => {
  const r = await ferramenta("listar_propostas_de_lancamento").execute({}, ctxDe(bancoFalso({ finance_review_queue: FILA }))) as Qualquer;
  const por = (id: string) => r.propostas.find((p: Qualquer) => p.id === id);
  assertEquals(por("e-pagador").cliente_pede_sim, true);
  assertEquals(por("e-pagador").motivo_do_cliente, "Pago pelo cônjuge de ACRISIO, guardado por você em 12/10 — confira");
  assertEquals(por("e-pagador").de_quem_e, null);
  assertEquals("cliente_pede_sim" in por("e-proprio"), false);
  assertEquals("cliente_pede_sim" in por("e-pergunta"), false);
  const t = ferramenta("listar_propostas_de_lancamento");
  assert(/PERGUNTE ao usuário de quem é o pagamento; nunca cadastre cliente com os dados de quem pagou/.test(t.description));
  assert(t.description.includes("cliente_confirmado") && t.description.includes("guardar_pagador_do_cliente"));
});

// ─── aprovar_propostas_de_lancamento: cliente_confirmado ────────────────────────────────────────────────
const FILA_APROVAR = [
  { id: "e-pagador", kind: "create_receivable", title: "Receita: MARIA SOUZA", bank_transaction_id: "t2", suggested_client_id: CLIENTE, suggested_amount: 1500, suggested_date: "2026-10-12" },
  { id: "e-pergunta", kind: "create_receivable", title: "Receita: JOANA", bank_transaction_id: "t1", suggested_client_id: null, suggested_amount: 300, suggested_date: "2026-10-12" },
];

Deno.test("aprovar: cliente_confirmado vira o clientId sugerido pela fila (nunca um nome)", async () => {
  const corpos: Qualquer[] = [];
  await comFetch({ ok: true }, (b) => corpos.push(b), async () => {
    const sb = bancoFalso({ finance_review_queue: FILA_APROVAR });
    await ferramenta("aprovar_propostas_de_lancamento").execute({ ids: ["e-pagador"], cliente_confirmado: ["e-pagador"] }, ctxDe(sb));
    // Confirmado de proposta que não está sendo aprovada não entra.
    await ferramenta("aprovar_propostas_de_lancamento").execute(
      { ids: ["e-pagador"], vinculos: { "e-pagador": "nenhum" }, cliente_confirmado: ["e-pergunta"] }, ctxDe(sb));
  });
  assertEquals(corpos[0], { action: "approve", ids: ["e-pagador"], overrides: { "e-pagador": { clientId: CLIENTE } } });
  assertEquals(corpos[1].overrides, { "e-pagador": { vinculo: "nenhum" } });
});

Deno.test("aprovar: confirmar cliente de entrada SEM sugestão é recusado (pergunte de quem é), nada vai ao servidor", async () => {
  let chamou = false;
  const r = await comFetch({ ok: true }, () => { chamou = true; }, () =>
    ferramenta("aprovar_propostas_de_lancamento").execute(
      { ids: ["e-pergunta"], vinculos: { "e-pergunta": "nenhum" }, cliente_confirmado: ["e-pergunta"] },
      ctxDe(bancoFalso({ finance_review_queue: FILA_APROVAR })),
    )) as Qualquer;
  assert(r.error.includes("guardar_pagador_do_cliente"), r.error);
  assertEquals(r.propostas, [{ id: "e-pergunta", titulo: "Receita: JOANA" }]);
  assertEquals(chamou, false);
});

Deno.test("aprovar: o retrato do 'sim' — sugestão que mudou depois da pendência é recusada", async () => {
  const t = ferramenta("aprovar_propostas_de_lancamento");
  const sb = bancoFalso({ finance_review_queue: FILA_APROVAR });
  assertEquals(await t.retratoDaPendencia!({ ids: ["e-pagador"], cliente_confirmado: ["e-pagador"] }, ctxDe(sb)), {
    cliente_confirmado: { "e-pagador": CLIENTE },
  });
  assertEquals(await t.retratoDaPendencia!({ ids: ["e-pagador"] }, ctxDe(sb)), null);
  let chamou = false;
  const r = await comFetch({ ok: true }, () => { chamou = true; }, () =>
    t.execute({
      ids: ["e-pagador"], vinculos: { "e-pagador": "nenhum" }, cliente_confirmado: ["e-pagador"],
      _retrato: { cliente_confirmado: { "e-pagador": OUTRO_CLIENTE } },
    }, ctxDe(sb))) as Qualquer;
  assert(/mudou/.test(r.error), r.error);
  assertEquals(chamou, false);
  // O mesmo cliente do retrato segue.
  const corpos: Qualquer[] = [];
  await comFetch({ ok: true }, (b) => corpos.push(b), () =>
    t.execute({
      ids: ["e-pagador"], vinculos: { "e-pagador": "nenhum" }, cliente_confirmado: ["e-pagador"],
      _retrato: { cliente_confirmado: { "e-pagador": CLIENTE } },
    }, ctxDe(sb)));
  assertEquals(corpos[0].overrides, { "e-pagador": { vinculo: "nenhum", clientId: CLIENTE } });
});

// Revisão de 23/10/2026: o retrato que não deu para tirar NÃO vira "sem retrato" (a execução aplicaria o cliente do
// momento, a quem o dono pode nunca ter dito sim) — vira o marcador, e a execução recusa.
Deno.test("aprovar: retrato cuja leitura falha (erro ou exceção) vira o marcador, e a execução com ele recusa", async () => {
  const t = ferramenta("aprovar_propostas_de_lancamento");
  const pedido = { ids: ["e-pagador"], cliente_confirmado: ["e-pagador"] };
  assertEquals(await t.retratoDaPendencia!(pedido, ctxDe(bancoFalso({}, { falham: ["finance_review_queue"] }))), { leitura_falhou: true });
  const explode = { from() { throw new Error("rede caiu"); } };
  assertEquals(await t.retratoDaPendencia!(pedido, ctxDe(explode)), { leitura_falhou: true });
  assertEquals({ ...RETRATO_QUE_FALHOU }, { leitura_falhou: true });
  let chamou = false;
  const r = await comFetch({ ok: true }, () => { chamou = true; }, () =>
    t.execute({ ...pedido, vinculos: { "e-pagador": "nenhum" }, _retrato: { leitura_falhou: true } },
      ctxDe(bancoFalso({ finance_review_queue: FILA_APROVAR })))) as Qualquer;
  assert(/Não consegui conferir, quando o pedido foi feito, o cliente/.test(r.error), r.error);
  assertEquals(r.propostas, [{ id: "e-pagador", titulo: "Receita: MARIA SOUZA" }]);
  assertEquals(chamou, false);
});

Deno.test("aprovar: id confirmado que o retrato não tem (não estava na fila no 'sim') também é 'mudou' — recusa", async () => {
  let chamou = false;
  const r = await comFetch({ ok: true }, () => { chamou = true; }, () =>
    ferramenta("aprovar_propostas_de_lancamento").execute({
      ids: ["e-pagador"], vinculos: { "e-pagador": "nenhum" }, cliente_confirmado: ["e-pagador"], _retrato: { cliente_confirmado: {} },
    }, ctxDe(bancoFalso({ finance_review_queue: FILA_APROVAR })))) as Qualquer;
  assert(/mudou/.test(r.error), r.error);
  assertEquals(chamou, false);
});

// ─── o cartão do "Sim, é do X" (revisão de 23/10/2026) ──────────────────────────────────────────────────
const SEM_CADASTRO = "77777777-7777-4777-8777-777777777777";
const FILA_DO_CARTAO = [
  {
    id: "e-pagador", kind: "create_receivable", title: "Receita: MARIA SOUZA", suggested_amount: 1500, suggested_date: "2026-10-12",
    suggested_client_id: CLIENTE,
    evidencia: {
      cliente: { id: CLIENTE, nome: "ACRISIO", por: "pagador_conhecido", detalhe: "Pago pelo cônjuge de ACRISIO, guardado por você em 12/10 — confira" },
    },
  },
  { id: "s-posto", kind: "create_payable", title: "Despesa: POSTO", suggested_amount: 200, suggested_date: "2026-10-13", suggested_client_id: null, evidencia: null },
  {
    id: "e-pergunta", kind: "create_receivable", title: "Receita: JOANA", suggested_amount: 300, suggested_date: "2026-10-12", suggested_client_id: null,
    evidencia: { deQuemE: { documento: "12345678901", nome: "JOANA", candidatos: [] } },
  },
  {
    // a evidência fala de OUTRO cliente: não serve de motivo para o sugerido
    id: "e-outro", kind: "create_receivable", title: "Receita: PEDRO", suggested_amount: 800, suggested_date: "2026-10-14",
    suggested_client_id: OUTRO_CLIENTE, evidencia: { cliente: { id: CLIENTE, nome: "ACRISIO", por: "historico", detalhe: "Este CPF já pagou 2× em nome de ACRISIO — confira" } },
  },
  {
    id: "e-historico", kind: "create_receivable", title: "Receita: PEDRO", suggested_amount: 800, suggested_date: "2026-10-14",
    suggested_client_id: OUTRO_CLIENTE, evidencia: { cliente: { id: OUTRO_CLIENTE, nome: "BEATRIZ", por: "historico" } },
  },
  {
    id: "e-sem-cadastro", kind: "create_receivable", title: "Receita: RITA", suggested_amount: 100, suggested_date: "2026-10-15",
    suggested_client_id: SEM_CADASTRO, evidencia: { cliente: { id: SEM_CADASTRO, nome: "RITA", por: "historico", detalhe: "x" } },
  },
];
const CLIENTES_DO_CARTAO = [{ id: CLIENTE, name: "ACRISIO" }, { id: OUTRO_CLIENTE, name: "BEATRIZ" }];
/** O R$ do toLocaleString vem com espaço inseparável: troca por espaço comum para comparar. */
const espaco = (s: string | null) => String(s ?? "").replace(/ /g, " ");

Deno.test("cartão do aprovar com cliente_confirmado: título, data, valor e 'cliente: <nome> (<motivo>)' — nunca uuid", async () => {
  const admin = bancoFalso({ finance_review_queue: FILA_DO_CARTAO, clients: CLIENTES_DO_CARTAO });
  const args = { ids: ["e-pagador", "s-posto"], cliente_confirmado: ["e-pagador"], vinculos: { "e-pagador": "nenhum" } };
  const cartao = espaco(await buildPendingSummary(admin, "aprovar_propostas_de_lancamento", args, { userRole: "admin" }));
  assertEquals(cartao.split("\n"), [
    "Aprovar 2 propostas de lançamento:",
    "- Receita: MARIA SOUZA · 12/10/2026 · R$ 1.500,00 — cliente: *ACRISIO* (Pago pelo cônjuge de ACRISIO, guardado por você em 12/10 — confira)",
    "- Despesa: POSTO · 13/10/2026 · R$ 200,00",
    // os outros argumentos seguem no formato de sempre
    "- Casar com: {\"e-pagador\":\"nenhum\"}",
  ]);
  assertEquals(cartao.includes(CLIENTE), false);
  assertEquals(/Ids:|Cliente Confirmado/.test(cartao), false);
  assertEquals(resumoQueRecusa("aprovar_propostas_de_lancamento", cartao), null, "é pendência, não recusa");
  assertEquals(tituloDaAcao("aprovar_propostas_de_lancamento"), "Aprovar propostas de lançamento");
  // Motivo: o da evidência DESTE cliente; sem detalhe, o rótulo da evidência; evidência de outro cliente não serve.
  const outro = espaco(await resumirClienteConfirmado(admin, { ids: ["e-outro", "e-historico"], cliente_confirmado: ["e-outro", "e-historico"] }));
  assertEquals(outro.split("\n").slice(1), [
    // a prova fala de outro e não há anotação: ninguém disse que é do BEATRIZ (4ª rodada) — o "sim" é a escolha do dono
    "- Receita: PEDRO · 14/10/2026 · R$ 800,00 — cliente: *BEATRIZ* (ninguém disse que é dele: confirme só se for)",
    "- Receita: PEDRO · 14/10/2026 · R$ 800,00 — cliente: *BEATRIZ* (lançamentos anteriores)",
  ]);
  // Sem cliente_confirmado: o resumo genérico de sempre (nada muda para quem não confirma cliente).
  assertEquals(await resumirClienteConfirmado(admin, { ids: ["s-posto"] }), null);
  assertEquals(await resumirClienteConfirmado(admin, { ids: ["s-posto"], cliente_confirmado: [] }), null);
  assert((await buildPendingSummary(admin, "aprovar_propostas_de_lancamento", { ids: ["s-posto"] })).startsWith("- Ids:"));
});

Deno.test("cartão do aprovar: confirmado sem sugestão, fora da fila, sem cadastro ou leitura que falha → UMA linha ⚠️ (recusa)", async () => {
  const admin = bancoFalso({ finance_review_queue: FILA_DO_CARTAO, clients: CLIENTES_DO_CARTAO });
  const casos: Array<[string, Record<string, unknown>, unknown]> = [
    ["Não há cliente sugerido para confirmar em: Receita: JOANA", { ids: ["e-pagador", "e-pergunta"], cliente_confirmado: ["e-pagador", "e-pergunta"] }, admin],
    ["Não há cliente sugerido para confirmar em: Despesa: POSTO", { ids: ["s-posto"], cliente_confirmado: ["s-posto"] }, admin],
    ["proposta que não está na fila", { ids: ["sumiu"], cliente_confirmado: ["sumiu"] }, admin],
    ["não está mais no cadastro", { ids: ["e-sem-cadastro"], cliente_confirmado: ["e-sem-cadastro"] }, admin],
    ["Diga quais propostas aprovar", { cliente_confirmado: ["e-pagador"] }, admin],
    ["Não consegui conferir o cliente das entradas agora (falha em finance_review_queue)", { ids: ["e-pagador"], cliente_confirmado: ["e-pagador"] },
      bancoFalso({ clients: CLIENTES_DO_CARTAO }, { falham: ["finance_review_queue"] })],
    ["Não consegui conferir o cliente das entradas agora (falha em clients)", { ids: ["e-pagador"], cliente_confirmado: ["e-pagador"] },
      bancoFalso({ finance_review_queue: FILA_DO_CARTAO }, { falham: ["clients"] })],
    ["Não consegui conferir o cliente das entradas agora (rede caiu)", { ids: ["e-pagador"], cliente_confirmado: ["e-pagador"] },
      { from() { throw new Error("rede\ncaiu"); } }],
  ];
  for (const [esperado, args, banco] of casos) {
    // Pelo caminho do agente: a linha ⚠️ é o resumo inteiro, e vira recusa (nunca o cartão genérico com uuid).
    const r = await buildPendingSummary(banco, "aprovar_propostas_de_lancamento", args, { userRole: "admin" });
    assert(r.startsWith("⚠️") && r.includes(esperado) && !r.includes("\n"), `${esperado}: ${r}`);
    assertEquals(typeof resumoQueRecusa("aprovar_propostas_de_lancamento", r)?.error, "string", esperado);
  }
  // Confirmado de proposta que não está sendo aprovada é ignorado, como na execução.
  const ignorado = espaco(await resumirClienteConfirmado(admin, { ids: ["s-posto"], cliente_confirmado: ["e-pergunta"] }));
  assertEquals(ignorado, "Aprovar 1 proposta de lançamento:\n- Despesa: POSTO · 13/10/2026 · R$ 200,00");
});

Deno.test("autonomia: aprovar propostas NUNCA roda sozinho, mesmo com 'auto' e sem cliente confirmado (dono, 23/10/2026)", () => {
  const nome = "aprovar_propostas_de_lancamento";
  const s = { [autonomyKey(nome)]: "auto" };
  assert(NEVER_AUTONOMOUS.has(nome));
  assertEquals(isAutonomyGranted(nome, "high", s, { ids: ["a"], cliente_confirmado: ["a"] }), false);
  assertEquals(isAutonomyGranted(nome, "high", s, { ids: ["a"] }), false);
  assertEquals(isAutonomyGranted(nome, "high", s, { ids: ["a"], cliente_confirmado: [] }), false);
  assertEquals(isAutonomyGranted(nome, "high", s), false);
  // Está na lista fixa: a trava "só em parte" (por argumento) não se aplica mais a ela.
  assertEquals(EXPLICACAO_DA_TRAVA_POR_ARGUMENTO[nome], undefined);
});

Deno.test("aprovar: leitura da fila que falha ao confirmar o cliente lança — não aprova sem o cliente", async () => {
  let erro = "";
  try {
    await ferramenta("aprovar_propostas_de_lancamento").execute(
      { ids: ["e-pagador"], vinculos: { "e-pagador": "nenhum" }, cliente_confirmado: ["e-pagador"] },
      ctxDe(bancoFalso({}, { falham: ["finance_review_queue"] })),
    );
  } catch (e) { erro = (e as Error).message; }
  assert(/Não consegui ler as propostas/.test(erro), erro);
});

// ─── cadastrar_contraparte_do_extrato na ENTRADA ────────────────────────────────────────────────────────
const PROPOSTA_DE_ENTRADA = {
  id: PROPOSTA, kind: "create_receivable", suggested_category: "Serviços prestados",
  // a sugestão antiga não vale na entrada: o documento e o nome são os da linha do banco
  evidencia: { cadastrar: { tipo: "cliente", documento: "99999999999", nome: "NOME DA SUGESTÃO" } },
  bank_transactions: { counterparty_name: "MARIA SOUZA", counterparty_document: "123.456.789-01", description: "PIX RECEBIDO" },
};

Deno.test("cadastrar_contraparte: na entrada, sem o 'é cliente novo' dito, recusa e manda perguntar", async () => {
  const sb = bancoFalso({ finance_review_queue: [PROPOSTA_DE_ENTRADA] });
  const t = ferramenta("cadastrar_contraparte_do_extrato");
  for (const args of [{ proposta_id: PROPOSTA }, { proposta_id: PROPOSTA, tipo: "fornecedor" }, { proposta_id: PROPOSTA, tipo: "favorecido" }]) {
    const r = await t.execute(args, ctxDe(sb)) as Qualquer;
    assert(/Pergunte ao usuário de quem é este pagamento/.test(r.error), r.error);
  }
  assertEquals(sb.rpcs, []);
});

Deno.test("cadastrar_contraparte: na entrada, com tipo='cliente' dito, cadastra pelos dados da LINHA do banco", async () => {
  const sb = bancoFalso({ finance_review_queue: [PROPOSTA_DE_ENTRADA] }, { rpc: () => ({ data: { ok: true, id: "novo" } }) });
  const r = await ferramenta("cadastrar_contraparte_do_extrato").execute({ proposta_id: PROPOSTA, tipo: "cliente" }, ctxDe(sb)) as Qualquer;
  assertEquals(r.ok, true);
  assertEquals(sb.rpcs.length, 1);
  assertEquals(sb.rpcs[0].nome, "cadastrar_contraparte");
  assertEquals(sb.rpcs[0].args.p_tipo, "cliente");
  assertEquals(sb.rpcs[0].args.p_dados.documento, "12345678901");
  assertEquals(sb.rpcs[0].args.p_dados.nome, "MARIA SOUZA");
});

Deno.test("cadastrar_contraparte: a saída segue como antes (o tipo e o documento da sugestão)", async () => {
  const sb = bancoFalso({
    finance_review_queue: [{
      id: SAIDA, kind: "create_payable", suggested_category: "Outras despesas",
      evidencia: { cadastrar: { tipo: "favorecido", documento: "12345678901", nome: "JOÃO PRESTADOR" } },
      bank_transactions: { counterparty_name: "JOAO P", counterparty_document: "12345678901", description: "PIX ENVIADO" },
    }],
  }, { rpc: () => ({ data: { ok: true } }) });
  await ferramenta("cadastrar_contraparte_do_extrato").execute({ proposta_id: SAIDA }, ctxDe(sb));
  assertEquals(sb.rpcs[0].args.p_tipo, "favorecido");
  assertEquals(sb.rpcs[0].args.p_dados.nome, "JOÃO PRESTADOR");
});

Deno.test("cadastrar_contraparte: o resumo recusa a entrada ANTES do 'sim' (uma linha ⚠️); na saída, segue o resumo de sempre", async () => {
  const sb = bancoFalso({ finance_review_queue: [PROPOSTA_DE_ENTRADA, { id: SAIDA, kind: "create_payable" }] });
  const r = await resumirCadastroDoExtrato(sb, { proposta_id: PROPOSTA });
  assert(r?.startsWith("⚠️") && !r.includes("\n"), String(r));
  assertEquals(typeof resumoQueRecusa("cadastrar_contraparte_do_extrato", r!)?.error, "string");
  assertEquals(await resumirCadastroDoExtrato(sb, { proposta_id: PROPOSTA, tipo: "cliente" }), null);
  assertEquals(await resumirCadastroDoExtrato(sb, { proposta_id: SAIDA }), null);
  assertEquals(await resumirCadastroDoExtrato(bancoFalso({}, { falham: ["finance_review_queue"] }), { proposta_id: PROPOSTA }), null);
  assertEquals(recusaDeCadastroNaEntrada("create_payable", undefined), null);
  // Pelo caminho do agente: o resumo da pendência é a recusa.
  const resumo = await buildPendingSummary(sb, "cadastrar_contraparte_do_extrato", { proposta_id: PROPOSTA }, { userRole: "admin" });
  assertEquals(resumo, r);
});

// ─── guardar_pagador_do_cliente ─────────────────────────────────────────────────────────────────────────
const LINHA_DO_BANCO = {
  id: LINHA, transaction_date: "2026-10-12", amount: 1500, transaction_type: "credit",
  counterparty_name: "MARIA SOUZA", counterparty_document: "123.456.789-01", description: "PIX RECEBIDO MARIA SOUZA",
};
const FILA_DO_PAGADOR = [{ id: PROPOSTA, kind: "create_receivable", bank_transaction_id: LINHA }, { id: SAIDA, kind: "create_payable", bank_transaction_id: LINHA }];
const CLIENTES = [{ id: CLIENTE, name: "ACRISIO", cpf_cnpj: "987.654.321-00", active: true }];
const GRAVOU = (situacao: string) => ({
  data: {
    ok: true, message: situacao === "confirmado" ? "1 pagador guardado e confirmado." : "1 pagador proposto: falta o SIM do administrador.",
    gravados: [{ id: "pg1", client_id: CLIENTE, cliente: "ACRISIO", nome: "MARIA SOUZA", relacao: "conjuge", situacao }],
    recusados: [], regras_consolidadas: [],
  },
});

Deno.test("guardar_pagador: medium, só admin/financeiro, e o preValidar recusa sem banco o pedido incompleto", () => {
  const t = ferramenta("guardar_pagador_do_cliente");
  assertEquals(t.risk, "medium");
  assertEquals(t.roles, ["admin", "financial"]);
  const pv = (args: Record<string, unknown>) => t.preValidar!(args, ctxDe({}));
  assert(pv({ relacao: "conjuge", proposta_id: PROPOSTA })?.error.includes("client_id"));
  assert(pv({ client_id: "ACRISIO", relacao: "conjuge", proposta_id: PROPOSTA })?.error.includes("client_id"));
  assert(pv({ client_id: CLIENTE, relacao: "esposa", proposta_id: PROPOSTA })?.error.includes("cônjuge"));
  assert(pv({ client_id: CLIENTE, relacao: "conjuge" })?.error.includes("proposta_id"));
  assert(pv({ client_id: CLIENTE, relacao: "conjuge", proposta_id: "OS-00012" })?.error.includes("uuid"));
  assertEquals(pv({ client_id: CLIENTE, relacao: "conjuge", proposta_id: PROPOSTA }), null);
  assertEquals((t.input_schema as Qualquer).properties.relacao.enum, ["empresa_do_cliente", "conjuge", "parente", "marina", "seguradora", "outro"]);
  // O esquema não pede documento nem nome: quem preenche é o banco.
  assertEquals(Object.keys((t.input_schema as Qualquer).properties).sort(), ["bank_transaction_id", "client_id", "observacao", "proposta_id", "relacao"]);
});

Deno.test("guardar_pagador: chama a RPC só com cliente, linha (da proposta) e relação, com p_autor; confirmado refaz a fila", async () => {
  const sb = bancoFalso({ finance_review_queue: FILA_DO_PAGADOR }, { rpc: () => GRAVOU("confirmado") });
  const corpos: Qualquer[] = [];
  const r = await comFetch({ ok: true, atualizadas: 2 }, (b) => corpos.push(b), () =>
    ferramenta("guardar_pagador_do_cliente").execute({
      client_id: CLIENTE, proposta_id: PROPOSTA, relacao: "conjuge", observacao: "  esposa   do Acrisio ",
      // o que o modelo inventar de documento e nome não chega à função
      documento: "00000000000", nome: "OUTRA PESSOA",
    }, ctxDe(sb))) as Qualquer;
  assertEquals(sb.rpcs, [{
    nome: "guardar_pagadores_do_cliente",
    args: {
      p_itens: [{ client_id: CLIENTE, bank_transaction_id: LINHA, relacao: "conjuge", observacao: "esposa do Acrisio", origem: "assistente" }],
      p_autor: "u-dono",
    },
  }]);
  assertEquals(corpos, [{ action: "reclassify" }]);
  assertEquals(r.ok, true);
  assertEquals(r.situacao, "confirmado");
  assertEquals(r.relacao, "Cônjuge");
  assertEquals(r.propostas_reclassificadas, 2);
});

Deno.test("guardar_pagador: pelo bank_transaction_id direto; o financeiro grava proposto e a fila não é refeita", async () => {
  const sb = bancoFalso({}, { rpc: () => GRAVOU("proposto") });
  let chamou = false;
  const r = await comFetch({ ok: true }, () => { chamou = true; }, () =>
    ferramenta("guardar_pagador_do_cliente").execute(
      { client_id: CLIENTE, bank_transaction_id: LINHA, relacao: "conjuge" }, ctxDe(sb, { userRole: "financial", userId: "u-fin" }))) as Qualquer;
  assertEquals(sb.rpcs[0].args.p_itens[0].bank_transaction_id, LINHA);
  assertEquals(sb.rpcs[0].args.p_autor, "u-fin");
  assertEquals(r.situacao, "proposto");
  assertEquals(chamou, false);
});

Deno.test("guardar_pagador: recusas — da função (com o motivo), do banco, de saída, de técnico e de leitura que falha", async () => {
  const t = ferramenta("guardar_pagador_do_cliente");
  const pedido = { client_id: CLIENTE, proposta_id: PROPOSTA, relacao: "conjuge" };
  const recusou = bancoFalso({ finance_review_queue: FILA_DO_PAGADOR }, {
    rpc: () => ({ data: { ok: false, gravados: [], recusados: [{ indice: 1, motivo: "Este CPF/CNPJ é do cliente BEATRIZ: possível cadastro duplicado." }], message: "Nenhum pagador guardado." } }),
  });
  assertEquals((await t.execute(pedido, ctxDe(recusou)) as Qualquer).error, "Este CPF/CNPJ é do cliente BEATRIZ: possível cadastro duplicado.");
  const erroDoBanco = bancoFalso({ finance_review_queue: FILA_DO_PAGADOR }, {
    rpc: () => ({ error: { message: "42501: Diga quem está guardando: entre no sistema (ou o assistente informa o autor)." } }),
  });
  assertEquals((await t.execute(pedido, ctxDe(erroDoBanco)) as Qualquer).error, "Diga quem está guardando: entre no sistema (ou o assistente informa o autor).");
  const deSaida = bancoFalso({ finance_review_queue: FILA_DO_PAGADOR });
  assert(/ENTRADA/.test((await t.execute({ ...pedido, proposta_id: SAIDA }, ctxDe(deSaida)) as Qualquer).error));
  assertEquals(deSaida.rpcs, []);
  const tecnico = bancoFalso({ finance_review_queue: FILA_DO_PAGADOR });
  assertEquals(typeof (await t.execute(pedido, ctxDe(tecnico, { userRole: "technician" })) as Qualquer).error, "string");
  assertEquals(tecnico.rpcs, []);
  const falhou = bancoFalso({}, { falham: ["finance_review_queue"] });
  assert(/Não consegui ler a proposta/.test((await t.execute(pedido, ctxDe(falhou)) as Qualquer).error));
  assertEquals(falhou.rpcs, []);
  // Proposta e linha que não batem: pergunta, não escolhe.
  const outra = "66666666-6666-4666-8666-666666666666";
  const divergente = bancoFalso({ finance_review_queue: FILA_DO_PAGADOR });
  assert(/não são a mesma/.test((await t.execute({ ...pedido, bank_transaction_id: outra }, ctxDe(divergente)) as Qualquer).error));
});

Deno.test("guardar_pagador: o resumo do 'sim' é o pedido resolvido, com o CPF mascarado; quem pede muda o depois", async () => {
  const admin = bancoFalso({ finance_review_queue: FILA_DO_PAGADOR, bank_transactions: [LINHA_DO_BANCO], clients: CLIENTES });
  const args = { client_id: CLIENTE, proposta_id: PROPOSTA, relacao: "conjuge", observacao: "esposa do Acrisio" };
  const doDono = await resumirGuardarPagador(admin, args, { userRole: "admin" });
  assertEquals(doDono.split("\n"), [
    "Guardar quem paga por um cliente",
    "Quem pagou: *MARIA SOUZA* (CPF ***.456.789-**)",
    "Pagamento: 12/10/2026 · R$ 1.500,00",
    "Cliente: *ACRISIO*",
    "Relação: Cônjuge",
    "Observação: esposa do Acrisio",
    "Depois do sim: fica *confirmado*. Os próximos Pix deste CPF vão SUGERIR ACRISIO, sempre pedindo a sua confirmação; nunca dão baixa sozinhos.",
  ].map((l) => l.replace(/R\$ /, "R$ ")));
  assertEquals(doDono.includes("123.456.789-01") || doDono.includes("12345678901"), false);
  const doFinanceiro = await resumirGuardarPagador(admin, args, { userRole: "financial" });
  assert(doFinanceiro.includes("fica *proposto*"), doFinanceiro);
  // Pelo caminho do agente (buildPendingSummary) é o mesmo texto — e não é recusa.
  assertEquals(await buildPendingSummary(admin, "guardar_pagador_do_cliente", args, { userRole: "admin" }), doDono);
  assertEquals(resumoQueRecusa("guardar_pagador_do_cliente", doDono), null);
  assertEquals(tituloDaAcao("guardar_pagador_do_cliente"), "Guardar quem paga pelo cliente");
});

Deno.test("guardar_pagador: o que não serve vira UMA linha ⚠️ (recusa, não pendência)", async () => {
  const args = { client_id: CLIENTE, bank_transaction_id: LINHA, relacao: "conjuge" };
  const casos: Array<[string, ReturnType<typeof bancoFalso>]> = [
    ["próprio cliente", bancoFalso({ bank_transactions: [LINHA_DO_BANCO], clients: [{ ...CLIENTES[0], cpf_cnpj: "12345678901" }] })],
    ["Só uma entrada", bancoFalso({ bank_transactions: [{ ...LINHA_DO_BANCO, transaction_type: "debit" }], clients: CLIENTES })],
    ["não informou o CPF/CNPJ", bancoFalso({ bank_transactions: [{ ...LINHA_DO_BANCO, counterparty_document: null }], clients: CLIENTES })],
    ["inativo", bancoFalso({ bank_transactions: [LINHA_DO_BANCO], clients: [{ ...CLIENTES[0], active: false }] })],
    ["Cliente não encontrado", bancoFalso({ bank_transactions: [LINHA_DO_BANCO], clients: [] })],
    ["Linha do extrato não encontrada", bancoFalso({ bank_transactions: [], clients: CLIENTES })],
    ["Não consegui conferir", bancoFalso({ clients: CLIENTES }, { falham: ["bank_transactions"] })],
  ];
  for (const [esperado, admin] of casos) {
    const r = await resumirGuardarPagador(admin, args, { userRole: "admin" });
    assert(r.startsWith("⚠️") && r.includes(esperado) && !r.includes("\n"), `${esperado}: ${r}`);
    assertEquals(typeof resumoQueRecusa("guardar_pagador_do_cliente", r)?.error, "string", esperado);
  }
  assert((await resumirGuardarPagador(bancoFalso(), { client_id: CLIENTE, relacao: "conjuge" })).startsWith("⚠️"));
  assertEquals("error" in lerPedidoDoPagador({ client_id: CLIENTE, relacao: "conjuge", bank_transaction_id: LINHA }), false);
});

// ─── listar_pagadores_do_cliente ────────────────────────────────────────────────────────────────────────
const PAGADORES = [
  {
    client_id: CLIENTE, nome: "MARIA SOUZA", documento: "12345678901", relacao: "conjuge", situacao: "confirmado", observacao: null,
    origem: "historico", proposto_em: "2026-10-12T15:00:00Z", confirmado_em: "2026-10-12T15:00:00Z", confirmado_por: "u-dono", decidido_motivo: null,
  },
  {
    client_id: CLIENTE, nome: "ACRISIO NAUTICA LTDA", documento: "12345678000199", relacao: "empresa_do_cliente", situacao: "proposto",
    observacao: "a empresa dele", origem: "fila", proposto_em: "2026-10-20T12:00:00Z", confirmado_em: null, confirmado_por: null, decidido_motivo: null,
  },
  { client_id: OUTRO_CLIENTE, nome: "OUTRO", documento: "11122233344", relacao: "outro", situacao: "confirmado", proposto_em: "2026-10-01T12:00:00Z" },
];

Deno.test("listar_pagadores: CPF mascarado, CNPJ inteiro, relação legível e quem confirmou", async () => {
  const sb = bancoFalso({ clients: CLIENTES, pagadores_do_cliente: PAGADORES, app_users: [{ id: "u-dono", full_name: "Gustavo" }] });
  const r = await ferramenta("listar_pagadores_do_cliente").execute({ client_id: CLIENTE }, ctxDe(sb)) as Qualquer;
  assertEquals(r.cliente, "ACRISIO");
  assertEquals(r.total, 2);
  assertEquals(r.pagadores[0], {
    nome: "MARIA SOUZA", documento: "***.456.789-**", relacao: "Cônjuge", situacao: "confirmado", desde: "12/10/2026",
    confirmado_em: "12/10/2026", confirmado_por: "Gustavo",
  });
  assertEquals(r.pagadores[1], {
    nome: "ACRISIO NAUTICA LTDA", documento: "12.345.678/0001-99", relacao: "Empresa do cliente", situacao: "proposto",
    desde: "20/10/2026", observacao: "a empresa dele",
  });
  assertEquals(JSON.stringify(r).includes("12345678901"), false);
});

Deno.test("listar_pagadores: leitura que falha diz que falhou (nunca 'ninguém paga'); técnico e id torto recusam", async () => {
  const t = ferramenta("listar_pagadores_do_cliente");
  const falha = await t.execute({ client_id: CLIENTE }, ctxDe(bancoFalso({ clients: CLIENTES }, { falham: ["pagadores_do_cliente"] }))) as Qualquer;
  assert(/Não consegui ler quem paga/.test(falha.error), JSON.stringify(falha));
  assertEquals(typeof (await t.execute({ client_id: CLIENTE }, ctxDe(bancoFalso(), { userRole: "technician" })) as Qualquer).error, "string");
  assertEquals(typeof (await t.execute({ client_id: "ACRISIO" }, ctxDe(bancoFalso())) as Qualquer).error, "string");
  assertEquals(t.risk, "low");
  assertEquals(t.roles, ["admin", "financial"]);
});

// ─── perfil, rede e autonomia ───────────────────────────────────────────────────────────────────────────
Deno.test("perfil: as duas só pela rede (fora do perfil enxuto e do de operação); a lista roda direto, guardar nunca sozinha", () => {
  for (const n of ["listar_pagadores_do_cliente", "guardar_pagador_do_cliente"]) {
    assert(allTools.some((t) => t.name === n), n);
    assert(SO_PELA_REDE.has(n), n);
    assertEquals(PERFIL_OPERACAO.has(n), false, n);
    assertEquals(PERFIL_ADMIN.has(n), false, n);
    assertEquals(FORA_DO_WHATSAPP.has(n), false, `${n}: o WhatsApp também alcança`);
  }
  const porNome = new Map(allTools.map((t) => [t.name, t]));
  assertEquals(rodaDiretoPelaRede(porNome.get("listar_pagadores_do_cliente")!), true);
  assertEquals(rodaDiretoPelaRede(porNome.get("guardar_pagador_do_cliente")!), false);
  assert(NEVER_AUTONOMOUS.has("guardar_pagador_do_cliente"));
  assertEquals(isAutonomyGranted("guardar_pagador_do_cliente", "medium", { ai_autonomy_guardar_pagador_do_cliente: "auto" }), false);
});

function fakeAdmin(perfil: string) {
  return {
    from(table: string) {
      return {
        select() {
          return { in: () => Promise.resolve({ data: table === "app_settings" ? [{ key: "ai_tool_profile", value: perfil }] : [], error: null }) };
        },
      };
    },
  };
}

Deno.test("perfil: a rede alcança as duas para o admin (perfil enxuto) e para o financeiro (operação); técnico não", async () => {
  const porCargo = (role: Role) => allTools.filter((t) => !t.roles || t.roles.includes(role));
  const turno = async (perfil: string, role: Role) => {
    zerarCacheDoPerfilDeTools();
    return await prepararFerramentasDoTurno({
      system: [{ type: "text", text: "teste" }], sessionId: "s1", channel: "panel", tools: porCargo(role),
      messages: [{ role: "user", content: [{ type: "text", text: "oi" }] }],
      toolCtx: { sb: {}, admin: fakeAdmin(perfil), userId: "u1", userRole: role, jwt: "jwt", appOrigin: "", settings: {} },
    } as never);
  };
  for (const [perfil, role] of [["admin_enxuto", "admin"], ["operacao", "financial"]] as const) {
    const r = await turno(perfil, role);
    for (const n of ["listar_pagadores_do_cliente", "guardar_pagador_do_cliente"]) {
      assert(r.alcancaveisPelaRede[n], `${role}: ${n} fora do alcance`);
      assertEquals(!!r.toolsByName[n], false, `${role}: ${n} à vista (custaria tokens em todo turno)`);
    }
  }
  const tecnico = await turno("operacao", "technician");
  assertEquals(!!tecnico.alcancaveisPelaRede["guardar_pagador_do_cliente"], false);
  zerarCacheDoPerfilDeTools();
});

// ─── Revisão de 23/10/2026: a ANOTAÇÃO do dono vale como o SIM; a pergunta que SOBRA não vai ao modelo ─────────────
// _aplicar_anotacao troca o cliente sugerido e mantém a prova antiga do motor; ela e o "É cliente novo" só tiram o
// 'cadastrar' da evidência — o deQuemE fica. clienteDaPropostaExigeSim e perguntaDeQuemEValida são a fonte única.
const PROVA_DO_PAGADOR = {
  id: CLIENTE, nome: "ACRISIO", por: "pagador_conhecido", detalhe: "Pago pelo cônjuge de ACRISIO, guardado por você em 12/10 — confira",
};
const PERGUNTA = { documento: "12345678901", nome: "MARIA SOUZA", candidatos: [] };
const FILA_ANOTADA = [
  // "o Pix é da BEATRIZ": o sugerido virou BEATRIZ; a prova continua sendo do pagador do ACRISIO
  {
    ...base, id: "e-anotou-outro", kind: "create_receivable", title: "Receita: MARIA SOUZA", bank_transaction_id: "t1",
    suggested_client_id: OUTRO_CLIENTE, evidencia: { cliente: PROVA_DO_PAGADOR, anotacao: { id: "a-outro" } },
  },
  // "o Pix é do ACRISIO": a anotação disse o MESMO cliente da prova — é o SIM
  {
    ...base, id: "e-anotou-mesmo", kind: "create_receivable", title: "Receita: MARIA SOUZA", bank_transaction_id: "t2",
    suggested_client_id: CLIENTE, evidencia: { cliente: { ...PROVA_DO_PAGADOR, por: "historico" }, anotacao: { id: "a-mesmo" } },
  },
  // anotação só com a categoria: não disse de quem é — o cliente do motor ainda pede o SIM
  {
    ...base, id: "e-anotou-categoria", kind: "create_receivable", title: "Receita: MARIA SOUZA", bank_transaction_id: "t3",
    suggested_client_id: CLIENTE, evidencia: { cliente: PROVA_DO_PAGADOR, anotacao: { id: "a-categoria" } },
  },
  // "é da OS-60": numa entrada, o cliente é o da OS
  {
    ...base, id: "e-anotou-os", kind: "create_receivable", title: "Receita: MARIA SOUZA", bank_transaction_id: "t4",
    suggested_client_id: CLIENTE, evidencia: { cliente: PROVA_DO_PAGADOR, anotacao: { id: "a-os", os_id: "os-60" } },
  },
  // a pergunta que sobrou depois da anotação ("o Pix é da BEATRIZ")
  {
    ...base, id: "e-sobra-anotacao", kind: "create_receivable", title: "Receita: 12345678901-MARIA SOUZA", bank_transaction_id: "t5",
    suggested_client_id: OUTRO_CLIENTE, evidencia: { deQuemE: PERGUNTA, anotacao: { id: "a-sobra" } },
  },
  // a pergunta que sobrou depois do "É cliente novo"
  {
    ...base, id: "e-sobra-cadastro", kind: "create_receivable", title: "Receita: MARIA SOUZA", bank_transaction_id: "t6",
    suggested_client_id: CLIENTE, evidencia: { deQuemE: PERGUNTA, cliente: { id: CLIENTE, nome: "ACRISIO", por: "documento" } },
  },
  // a pergunta que vale — com o nome do banco que traz o CPF
  {
    ...base, id: "e-pergunta-cpf", kind: "create_receivable", title: "Receita: 12345678901-MARIA SOUZA", bank_transaction_id: "t7",
    suggested_client_id: null, evidencia: { deQuemE: { ...PERGUNTA, nome: "12345678901-MARIA SOUZA" } },
  },
];
const ANOTACOES = [
  { id: "a-outro", cliente_id: OUTRO_CLIENTE, os_id: null, status: "aplicada" },
  { id: "a-mesmo", cliente_id: CLIENTE, os_id: null, status: "aplicada" },
  { id: "a-categoria", cliente_id: null, os_id: null, status: "aplicada" },
  { id: "a-sobra", cliente_id: OUTRO_CLIENTE, os_id: null, status: "aplicada" },
];

Deno.test("listar_propostas: anotação que disse (ou trocou) o cliente não pede o SIM; a que só deu categoria pede", async () => {
  const sb = bancoFalso({ finance_review_queue: FILA_ANOTADA, anotacoes_do_extrato: ANOTACOES, clients: CLIENTES_DO_CARTAO });
  const r = await ferramenta("listar_propostas_de_lancamento").execute({}, ctxDe(sb)) as Qualquer;
  const por = (id: string) => r.propostas.find((p: Qualquer) => p.id === id);
  assertEquals("cliente_pede_sim" in por("e-anotou-outro"), false, "o cliente que o dono anotou não pede SIM");
  assertEquals("falta_escolher_o_cliente" in por("e-anotou-outro"), false, "a anotação lida disse o sugerido");
  assertEquals("cliente_pede_sim" in por("e-anotou-mesmo"), false, "a anotação disse o cliente: é o SIM");
  assertEquals("cliente_pede_sim" in por("e-anotou-os"), false, "OS anotada: o cliente é o da OS");
  assertEquals(por("e-anotou-categoria").cliente_pede_sim, true);
  // a anotação é lida uma vez, só para as linhas que precisam (a da OS se resolve pela fila)
  assertEquals(sb.lidas.filter((t) => t === "anotacoes_do_extrato").length, 1);
  // a fila sem anotação não lê anotações
  const semAnotacao = bancoFalso({ finance_review_queue: FILA });
  await ferramenta("listar_propostas_de_lancamento").execute({}, ctxDe(semAnotacao));
  assertEquals(semAnotacao.lidas.includes("anotacoes_do_extrato"), false);
});

// 4ª rodada (A): a leitura que falha não deixa a marca da evidência decidir — o cliente da prova continua pedindo o SIM, e
// o sugerido que não é o da prova fica por escolher (como no servidor, anotacaoDaLinha = null).
Deno.test("listar_propostas: leitura das anotações que falha — o da prova pede o SIM; o anotado que não é o da prova fica por escolher", async () => {
  const sb = bancoFalso({ finance_review_queue: FILA_ANOTADA, clients: CLIENTES_DO_CARTAO }, { falham: ["anotacoes_do_extrato"] });
  const r = await ferramenta("listar_propostas_de_lancamento").execute({}, ctxDe(sb)) as Qualquer;
  const por = (id: string) => r.propostas.find((p: Qualquer) => p.id === id);
  assertEquals(por("e-anotou-mesmo").cliente_pede_sim, true);
  assertEquals(por("e-anotou-categoria").cliente_pede_sim, true);
  // o sugerido que só a anotação explicava: nenhum cliente — nem o anotado, nem a prova antiga (ACRISIO)
  for (const id of ["e-anotou-outro", "e-sobra-anotacao"]) {
    assertEquals(por(id).falta_escolher_o_cliente, true, id);
    assertEquals("cliente_pede_sim" in por(id), false, id);
    assertEquals(por(id).quem, QUEM_FALTA_ESCOLHER, id);
  }
  assertEquals(JSON.stringify(por("e-anotou-outro")).includes("ACRISIO"), false, "a prova antiga não vira sugestão");
  // a OS na marca da evidência basta (como antes)
  assertEquals("cliente_pede_sim" in por("e-anotou-os"), false);
  assertEquals("falta_escolher_o_cliente" in por("e-anotou-os"), false);
});

// 4ª rodada (A, C2): a anotação DESFEITA (comprovante desligado) tira a marca da evidência e deixa o sugerido. A anotação
// que não volta como aplicada (cancelada, trocada) também não vale.
Deno.test("listar_propostas: anotação desfeita ou não aplicada — falta escolher o cliente; a pergunta 'de quem é?' volta", async () => {
  const fila = [
    // "o Pix é da BEATRIZ" desfeito: a prova antiga (pagador do ACRISIO) fica, o sugerido BEATRIZ fica
    { ...base, id: "e-desfeita", kind: "create_receivable", title: "Receita: MARIA SOUZA", bank_transaction_id: "t1",
      suggested_client_id: OUTRO_CLIENTE, evidencia: { cliente: PROVA_DO_PAGADOR } },
    // a anotação desfeita tinha resolvido a pergunta: ela volta, com o CPF mascarado
    { ...base, id: "e-desfeita-pergunta", kind: "create_receivable", title: "Receita: 12345678901-MARIA SOUZA", bank_transaction_id: "t2",
      suggested_client_id: OUTRO_CLIENTE, evidencia: { deQuemE: { ...PERGUNTA, nome: "12345678901-MARIA SOUZA" } } },
    // a marca ainda está, mas a anotação não volta como aplicada (cancelada/trocada)
    { ...base, id: "e-cancelada", kind: "create_receivable", title: "Receita: MARIA SOUZA", bank_transaction_id: "t3",
      suggested_client_id: OUTRO_CLIENTE, evidencia: { cliente: PROVA_DO_PAGADOR, anotacao: { id: "a-cancelada" } } },
  ];
  const sb = bancoFalso({
    finance_review_queue: fila, clients: CLIENTES_DO_CARTAO,
    anotacoes_do_extrato: [{ id: "a-cancelada", cliente_id: OUTRO_CLIENTE, os_id: null, status: "cancelada" }],
  });
  const r = await ferramenta("listar_propostas_de_lancamento").execute({}, ctxDe(sb)) as Qualquer;
  const por = (id: string) => r.propostas.find((p: Qualquer) => p.id === id);
  for (const id of ["e-desfeita", "e-desfeita-pergunta", "e-cancelada"]) {
    assertEquals(por(id).falta_escolher_o_cliente, true, id);
    assertEquals(por(id).quem, QUEM_FALTA_ESCOLHER, id);
    assertEquals("cliente_pede_sim" in por(id), false, id);
    assertEquals(/ACRISIO|BEATRIZ/.test(JSON.stringify(por(id))), false, `${id}: nem a prova antiga, nem o sugerido`);
  }
  assertEquals(por("e-desfeita").de_quem_e, null);
  assertEquals(por("e-desfeita-pergunta").de_quem_e, { nome: "***.456.789-**-MARIA SOUZA", documento: "***.456.789-**", candidatos: [] });
  assertEquals(JSON.stringify(r).includes("12345678901"), false);
  const t = ferramenta("listar_propostas_de_lancamento");
  assert(t.description.includes("falta_escolher_o_cliente") && /sem sugerir cliente nenhum/.test(t.description));
});

// 4ª rodada (C2): o "quem" de uma entrada cujo sugerido não é o da prova é o cliente ANOTADO, pelo nome do cadastro —
// nunca a prova antiga de outro cliente.
Deno.test("listar_propostas: 'quem' mostra o cliente anotado — '<nome> (você anotou)', nunca a prova antiga", async () => {
  const sb = bancoFalso({ finance_review_queue: FILA_ANOTADA, anotacoes_do_extrato: ANOTACOES, clients: CLIENTES_DO_CARTAO });
  const r = await ferramenta("listar_propostas_de_lancamento").execute({}, ctxDe(sb)) as Qualquer;
  const por = (id: string) => r.propostas.find((p: Qualquer) => p.id === id);
  assertEquals(por("e-anotou-outro").quem, "BEATRIZ (você anotou)");
  assertEquals(JSON.stringify(por("e-anotou-outro")).includes("ACRISIO"), false);
  assertEquals(por("e-sobra-anotacao").quem, "BEATRIZ (você anotou)", "a pergunta que sobrou não deixa a linha sem dono");
  // sugerido = prova: o quem de sempre
  assertEquals(por("e-anotou-mesmo").quem, "ACRISIO (por historico)");
  // os nomes vêm numa leitura só
  assertEquals(sb.lidas.filter((t) => t === "clients").length, 1);

  // leitura de clients que falha: diz que não leu — nunca cai na prova antiga
  const falha = bancoFalso({ finance_review_queue: FILA_ANOTADA, anotacoes_do_extrato: ANOTACOES }, { falham: ["clients"] });
  const f = await ferramenta("listar_propostas_de_lancamento").execute({}, ctxDe(falha)) as Qualquer;
  const pf = f.propostas.find((p: Qualquer) => p.id === "e-anotou-outro");
  assertEquals(pf.quem, "o cliente que você anotou (não consegui ler o nome dele agora)");
  assertEquals(JSON.stringify(pf).includes("ACRISIO"), false);
  // cliente anotado que saiu do cadastro
  const sumiu = bancoFalso({ finance_review_queue: FILA_ANOTADA, anotacoes_do_extrato: ANOTACOES, clients: [] });
  const s = await ferramenta("listar_propostas_de_lancamento").execute({}, ctxDe(sumiu)) as Qualquer;
  assertEquals(s.propostas.find((p: Qualquer) => p.id === "e-anotou-outro").quem, "o cliente que você anotou (não está mais no cadastro)");
  // fila sem sugerido de fora da prova não lê clients
  const semFora = bancoFalso({ finance_review_queue: FILA });
  await ferramenta("listar_propostas_de_lancamento").execute({}, ctxDe(semFora));
  assertEquals(semFora.lidas.includes("clients"), false);
});

Deno.test("listar_propostas: a pergunta que sobrou depois da anotação ou do 'É cliente novo' não vai; a que vale, com o CPF do nome mascarado", async () => {
  const sb = bancoFalso({ finance_review_queue: FILA_ANOTADA, anotacoes_do_extrato: ANOTACOES });
  const r = await ferramenta("listar_propostas_de_lancamento").execute({}, ctxDe(sb)) as Qualquer;
  const por = (id: string) => r.propostas.find((p: Qualquer) => p.id === id);
  assertEquals(por("e-sobra-anotacao").de_quem_e, null);
  assertEquals(por("e-sobra-cadastro").de_quem_e, null);
  assertEquals(por("e-pergunta-cpf").de_quem_e, { nome: "***.456.789-**-MARIA SOUZA", documento: "***.456.789-**", candidatos: [] });
  assertEquals(JSON.stringify(r).includes("12345678901"), false);
});

Deno.test("cartão do aprovar: cliente que o dono anotou (a prova fala de outro) aparece como 'você anotou'", async () => {
  const admin = bancoFalso({
    finance_review_queue: [{
      id: "e-anotou-outro", kind: "create_receivable", title: "Receita: MARIA SOUZA", suggested_amount: 1500, suggested_date: "2026-10-12",
      suggested_client_id: OUTRO_CLIENTE, evidencia: { cliente: PROVA_DO_PAGADOR, anotacao: { id: "a-outro" } },
    }],
    clients: CLIENTES_DO_CARTAO,
  });
  const cartao = espaco(await resumirClienteConfirmado(admin, { ids: ["e-anotou-outro"], cliente_confirmado: ["e-anotou-outro"] }));
  assertEquals(cartao.split("\n").slice(1), ["- Receita: MARIA SOUZA · 12/10/2026 · R$ 1.500,00 — cliente: *BEATRIZ* (você anotou)"]);
});

// ─── Revisão de 23/10/2026, item 3: CPF dentro do NOME do pagador (LGPD) ─────────────────────────────────────────
Deno.test("listar_pagadores: o CPF que o banco escreve no nome sai mascarado (e na observação e no motivo)", async () => {
  const comCpf = [{
    ...PAGADORES[0], nome: "12345678901-MARIA SOUZA", observacao: "CPF 123.456.789-01 é da esposa",
    decidido_motivo: "pausado: 12345678901 parou de pagar",
  }];
  const sb = bancoFalso({ clients: CLIENTES, pagadores_do_cliente: comCpf, app_users: [] });
  const r = await ferramenta("listar_pagadores_do_cliente").execute({ client_id: CLIENTE }, ctxDe(sb)) as Qualquer;
  assertEquals(r.pagadores[0].nome, "***.456.789-**-MARIA SOUZA");
  assertEquals(r.pagadores[0].observacao, "CPF ***.456.789-** é da esposa");
  assertEquals(r.pagadores[0].motivo, "pausado: ***.456.789-** parou de pagar");
  assertEquals(/12345678901|123\.456\.789-01/.test(JSON.stringify(r)), false);
});

Deno.test("guardar_pagador: quem_pagou, a mensagem e o aviso de regra antiga saem com o CPF do nome mascarado", async () => {
  const NOME = "12345678901-MARIA SOUZA";
  const sb = bancoFalso({ finance_review_queue: FILA_DO_PAGADOR }, {
    rpc: () => ({
      data: {
        ok: true,
        message: "1 pagador guardado e confirmado. Atenção: uma regra antiga diz que este CPF/CNPJ é do cliente BEATRIZ; "
          + `as entradas de ${NOME} passam a perguntar de quem é (escolha o cliente em cada uma).`,
        gravados: [{ id: "pg1", client_id: CLIENTE, cliente: "ACRISIO", nome: NOME, relacao: "conjuge", situacao: "confirmado" }],
        recusados: [], regras_consolidadas: [],
      },
    }),
  });
  const r = await comFetch({ ok: true, atualizadas: 1 }, () => {}, () =>
    ferramenta("guardar_pagador_do_cliente").execute({ client_id: CLIENTE, proposta_id: PROPOSTA, relacao: "conjuge" }, ctxDe(sb))) as Qualquer;
  assertEquals(r.quem_pagou, "***.456.789-**-MARIA SOUZA");
  assert(r.message.includes("as entradas de ***.456.789-**-MARIA SOUZA passam a perguntar"), r.message);
  assertEquals(/12345678901/.test(JSON.stringify(r)), false);
  // a recusa da função também
  const recusou = bancoFalso({ finance_review_queue: FILA_DO_PAGADOR }, {
    rpc: () => ({ data: { ok: false, gravados: [], recusados: [{ indice: 1, motivo: `${NOME} é o próprio cliente.` }], message: "Nenhum pagador guardado." } }),
  });
  const e = await ferramenta("guardar_pagador_do_cliente").execute(
    { client_id: CLIENTE, proposta_id: PROPOSTA, relacao: "conjuge" }, ctxDe(recusou)) as Qualquer;
  assertEquals(e.error, "***.456.789-**-MARIA SOUZA é o próprio cliente.");
});

Deno.test("guardar_pagador: o resumo do 'sim' mascara o CPF que o banco escreve no nome de quem pagou", async () => {
  const admin = bancoFalso({
    finance_review_queue: FILA_DO_PAGADOR, clients: CLIENTES,
    bank_transactions: [{ ...LINHA_DO_BANCO, counterparty_name: "12345678901-MARIA SOUZA" }],
  });
  const r = await resumirGuardarPagador(admin, { client_id: CLIENTE, proposta_id: PROPOSTA, relacao: "conjuge" }, { userRole: "admin" });
  assert(r.includes("Quem pagou: ****.456.789-**-MARIA SOUZA* (CPF ***.456.789-**)"), r);
  assertEquals(/12345678901|123\.456\.789-01/.test(r), false);
});
