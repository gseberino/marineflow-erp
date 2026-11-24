// Pacote 1 do assistente, S3 (24/11/2026): três escritas que rodavam sem o dono ver passam a pedir o "sim".
//   · apply_quote_price  — muda custo e preço de venda do orçamento: "sim", com o custo e a venda de antes e de depois;
//   · alterar_favorecido — trocar chave Pix, conta ou CPF/CNPJ pede PIN (o resto segue com o "sim"), com o antes e o depois;
//   · update_client      — trocar telefone, WhatsApp ou a marca de não receber mensagens pede o "sim", com o antes e o depois.
// O que se fixa aqui: o risco calculado (e que o cálculo NUNCA lança: computeRisk é chamado fora de try em agent.ts), o
// texto do cartão, o que vira recusa em vez de pendência, e que o cartão mostra o mesmo que a execução grava.
// Banco falso em memória; dados inventados.
// Rodar com:
//   deno test --allow-all --no-check --node-modules-dir=none supabase/functions/_shared/ai/tools/riscos-de-ferramenta_test.ts
import { assert, assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { bancoFalso, ctxDe, type Linha } from "./banco-falso-fakes_test.ts";
import { FALHA_AO_CONFERIR_A_COTACAO, precoDeVendaComMargem, quoteTools, resumirAplicacaoDoPreco } from "./quotes.ts";
import { AVISO_DO_DESTINO_DO_DINHEIRO, favorecidoTools, resumirFavorecido, riscoDeAlterarFavorecido } from "./favorecidos.ts";
import { clientTools, FALHA_AO_CONFERIR_O_CLIENTE, resumirTrocaDeContato, riscoDeAtualizarCliente } from "./clients.ts";
import { buildPendingSummary, executarChamadaDeTool, resumoQueRecusa, rotuloDoCampo, tituloDaAcao } from "../agent.ts";
import type { ToolDef } from "./registry.ts";

const ferramenta = (lista: ToolDef[], nome: string) => lista.find((t) => t.name === nome)!;
/** O Intl separa "R$" do número com espaço fixo (U+00A0): o teste compara com espaço comum. */
const limpo = (t: string | null) => String(t).replace(/ /g, " ");

/** O ambiente de uma chamada com a ferramenta À VISTA (no perfil): vale o risco que ela declara ou calcula. */
function aVista(tool: ToolDef, db: unknown, extra: Record<string, unknown> = {}) {
  return { toolsByName: { [tool.name]: tool }, alcancaveisPelaRede: {}, toolCtx: ctxDe(db, extra), sessionId: "sessao-s3", channel: "whatsapp" as const };
}
const pendencias = (b: { tabelas: Record<string, Linha[]> }) => b.tabelas.ai_operator_pending_actions ?? [];

/** Uma entrada que lança ao ser lida: o pior caso para um computeRisk chamado fora de try. */
const HOSTIL = new Proxy({}, { get() { throw new Error("leitura que explode"); } });
const ESTRANHAS: unknown[] = [undefined, null, "texto", 42, true, [], ["phone"], HOSTIL];

// ─── apply_quote_price ──────────────────────────────────────────────────────────────────────────

const OS = "os-201";
function cotacao(linha: "peca" | "servico", muda: (t: Record<string, Linha[]>) => void = () => {}) {
  const tabelas: Record<string, Linha[]> = {
    quote_responses: [{ id: "resp-1", quote_request_id: "qr-1", supplier_id: "sup-1", quote_request_item_id: "qi-1", unit_price: 100, confirmed: false }],
    quote_request_items: [{ id: "qi-1", description: "Bomba de porão", service_order_part_id: linha === "peca" ? "part-1" : null,
      service_order_service_id: linha === "servico" ? "svc-1" : null }],
    quote_requests: [{ id: "qr-1", code: "COT-00007", service_order_id: OS }],
    service_orders: [{ id: OS, service_order_number: "ORÇ-00201", status: "draft", grand_total: 300 }],
    // 2 × 150 − 25 de desconto da linha
    service_order_parts: [{ id: "part-1", service_order_id: OS, quantity: 2, unit_cost_snapshot: 80, unit_sale_snapshot: 150,
      line_total_cost: 160, line_total_sale: 275, discount_amount: 25 }],
    service_order_services: [{ id: "svc-1", service_order_id: OS, quantity: 2, unit_price_snapshot: 150, line_total: 275, discount_amount: 25 }],
    suppliers: [{ id: "sup-1", name: "Fornecedor Teste" }],
    receivables: [],
  };
  muda(tabelas);
  return tabelas;
}
const aplicar = ferramenta(quoteTools, "apply_quote_price");

Deno.test("S3 preço cotado: a ferramenta declara risco medium (pede o sim) e tem título em português", () => {
  assertEquals(aplicar.risk, "medium");
  assertEquals(aplicar.computeRisk, undefined, "sem atalho por argumento: toda aplicação de preço pede o sim");
  assertEquals(tituloDaAcao("apply_quote_price"), "Aplicar preço cotado ao orçamento");
});

Deno.test("S3 preço cotado: o cartão mostra fornecedor, item, orçamento e custo e venda de antes e de depois", async () => {
  const comMargem = bancoFalso(cotacao("peca"));
  assertEquals(limpo(await resumirAplicacaoDoPreco(comMargem.db, { response_id: "resp-1", markup_percent: 40 })), [
    "Aplicar o preço de *Fornecedor Teste* em *Bomba de porão* (ORÇ-00201):",
    "- Custo: R$ 80,00 → *R$ 100,00*",
    "- Venda: R$ 150,00 → *R$ 140,00*",
  ].join("\n"));
  assertEquals(comMargem.gravacoes, [], "o resumo só lê");

  // Sem margem, a peça muda só de custo.
  const semMargem = bancoFalso(cotacao("peca"));
  assertEquals(limpo(await resumirAplicacaoDoPreco(semMargem.db, { response_id: "resp-1" })), [
    "Aplicar o preço de *Fornecedor Teste* em *Bomba de porão* (ORÇ-00201):",
    "- Custo: R$ 80,00 → *R$ 100,00*",
    "- Venda: não muda",
  ].join("\n"));

  // Material/serviço de texto livre: a linha não guarda custo; com margem, muda a venda.
  const material = bancoFalso(cotacao("servico"));
  assertEquals(limpo(await resumirAplicacaoDoPreco(material.db, { response_id: "resp-1", markup_percent: 40 })), [
    "Aplicar o preço de *Fornecedor Teste* em *Bomba de porão* (ORÇ-00201):",
    "- Custo: esta linha não guarda custo (cotado: R$ 100,00)",
    "- Venda: R$ 150,00 → *R$ 140,00*",
  ].join("\n"));
  // É pelo caminho do agente o mesmo texto, e não é recusa.
  const peloAgente = await buildPendingSummary(material.db, "apply_quote_price", { response_id: "resp-1", markup_percent: 40 });
  assertEquals(limpo(peloAgente), limpo(await resumirAplicacaoDoPreco(material.db, { response_id: "resp-1", markup_percent: 40 })));
  assertEquals(resumoQueRecusa("apply_quote_price", peloAgente), null);
});

Deno.test("S3 preço cotado: o que a execução recusaria é recusa numa linha, e a pendência não nasce", async () => {
  const casos: Array<[string, Record<string, Linha[]>, Record<string, unknown>, string]> = [
    ["resposta sem preço", cotacao("peca", (t) => { t.quote_responses[0].unit_price = null; }), { response_id: "resp-1" },
      "⚠️ Essa resposta de cotação não tem preço registrado."],
    ["resposta que não existe", cotacao("peca"), { response_id: "outra" }, "⚠️ Resposta de cotação não encontrada."],
    ["sem response_id", cotacao("peca"), {}, "⚠️ Resposta de cotação não encontrada."],
    ["item sem linha no orçamento", cotacao("peca", (t) => { t.quote_request_items[0].service_order_part_id = null; }), { response_id: "resp-1" },
      "⚠️ Esse item da cotação não está amarrado a nenhuma linha de orçamento — não há onde aplicar o preço."],
    ["cotação sem orçamento", cotacao("peca", (t) => { t.quote_requests[0].service_order_id = null; }), { response_id: "resp-1" },
      "⚠️ Essa cotação não tem orçamento de origem."],
    ["OS cancelada", cotacao("peca", (t) => { t.service_orders[0].status = "cancelled"; }), { response_id: "resp-1" },
      "⚠️ OS cancelada não pode ser alterada."],
    ["OS faturada", cotacao("peca", (t) => { t.service_orders[0].status = "invoiced"; }), { response_id: "resp-1" },
      "⚠️ OS já faturada não pode ter valores alterados."],
    ["margem negativa", cotacao("peca"), { response_id: "resp-1", markup_percent: -5 }, "⚠️ markup_percent não pode ser negativo."],
    ["margem que não é número", cotacao("peca"), { response_id: "resp-1", markup_percent: "muito" },
      "⚠️ Não entendi a margem (markup_percent): diga um número, por exemplo 40."],
    ["desconto maior que a venda nova", cotacao("peca", (t) => { t.service_order_parts[0].discount_amount = 500; }), { response_id: "resp-1", markup_percent: 40 },
      "⚠️ O desconto dessa linha é maior que o novo preço de venda. Ajuste o desconto na tela da OS antes."],
    ["a linha de peça sumiu", cotacao("peca", (t) => { t.service_order_parts = []; }), { response_id: "resp-1" },
      "⚠️ A linha de peça do orçamento não existe mais."],
    ["material sem margem (a execução não alteraria nada)", cotacao("servico"), { response_id: "resp-1" },
      '⚠️ "Bomba de porão" é material/serviço (texto livre) e o sistema não guarda custo nessa linha. Custo cotado: R$ 100,00. ' +
      "Diga a margem (markup_percent) para eu aplicar o preço de venda."],
  ];
  for (const [nome, tabelas, args, esperado] of casos) {
    const b = bancoFalso(tabelas);
    const resumo = await buildPendingSummary(b.db, "apply_quote_price", args);
    assertEquals(limpo(resumo), esperado, nome);
    assert(resumoQueRecusa("apply_quote_price", resumo), `${nome}: tem de ser recusa (uma linha só), não pendência`);
    assertEquals(b.gravacoes, [], nome);
  }
});

Deno.test("S3 preço cotado: leitura que falha é recusa com a frase combinada — nunca um cartão às cegas, nunca exceção", async () => {
  for (const tabela of ["quote_responses", "quote_request_items", "quote_requests", "service_orders", "service_order_parts", "suppliers"]) {
    const b = bancoFalso(cotacao("peca"), { [`select:${tabela}`]: "timeout" });
    const resumo = await resumirAplicacaoDoPreco(b.db, { response_id: "resp-1", markup_percent: 40 });
    assertEquals(resumo, "⚠️ Não consegui conferir a cotação agora. Nada foi alterado; tente de novo.", tabela);
    assertEquals(resumo, FALHA_AO_CONFERIR_A_COTACAO);
    assert(resumoQueRecusa("apply_quote_price", resumo), tabela);
  }
  // Banco que lança (rede caída) e argumentos que não são objeto: a mesma recusa, sem exceção.
  const quebrado = { from() { throw new Error("rede caída"); } };
  assertEquals(await resumirAplicacaoDoPreco(quebrado, { response_id: "resp-1" }), FALHA_AO_CONFERIR_A_COTACAO);
  assertEquals(await resumirAplicacaoDoPreco(bancoFalso(cotacao("peca")).db, undefined), "⚠️ Resposta de cotação não encontrada.");
});

Deno.test("S3 preço cotado: o cartão diz o que a execução grava (mesma conta da margem)", async () => {
  assertEquals(precoDeVendaComMargem(100, 40), 140);
  assertEquals(precoDeVendaComMargem(33.33, 15), 38.33);
  const b = bancoFalso(cotacao("peca"));
  const cartao = limpo(await resumirAplicacaoDoPreco(b.db, { response_id: "resp-1", markup_percent: 15 }));
  assertStringIncludes(cartao, "- Custo: R$ 80,00 → *R$ 100,00*");
  assertStringIncludes(cartao, "- Venda: R$ 150,00 → *R$ 115,00*");
  // deno-lint-ignore no-explicit-any
  const r = await aplicar.execute({ response_id: "resp-1", markup_percent: 15 }, ctxDe(b.db)) as any;
  assertEquals(r.antes, { custo_unitario: 80, preco_venda: 150 });
  assertEquals(r.depois, { custo_unitario: 100, preco_venda: 115 });
  assertEquals(b.tabelas.service_order_parts[0].unit_cost_snapshot, 100);
  assertEquals(b.tabelas.service_order_parts[0].unit_sale_snapshot, 115);
});

Deno.test("S3 preço cotado: pelo agente, à vista, vira pendência medium e NADA é gravado antes do sim", async () => {
  const b = bancoFalso(cotacao("peca"));
  const r = await executarChamadaDeTool({ name: "apply_quote_price", input: { response_id: "resp-1", markup_percent: 40 } }, aVista(aplicar, b.db));
  // deno-lint-ignore no-explicit-any
  assertEquals((r.toolResult as any).pending, true, JSON.stringify(r.toolResult));
  assertEquals(r.executou, false);
  assertEquals(r.proposal?.risk_level, "medium");
  const [p] = pendencias(b);
  assertEquals(p.action_name, "apply_quote_price");
  assertEquals(p.risk_level, "medium");
  assertEquals(p.title, "Aplicar preço cotado ao orçamento");
  assertEquals(p.payload, { response_id: "resp-1", markup_percent: 40 });
  assertStringIncludes(limpo(p.summary), "- Venda: R$ 150,00 → *R$ 140,00*");
  assertEquals(b.tabelas.service_order_parts[0].unit_cost_snapshot, 80, "o custo só muda depois do sim");
  assertEquals(b.gravacoes.filter((g) => g.tabela.startsWith("service_order") || g.tabela === "quote_responses"), []);

  // Resposta sem preço: recusa ao modelo, sem pendência e sem pedir sim.
  const semPreco = bancoFalso(cotacao("peca", (t) => { t.quote_responses[0].unit_price = null; }));
  const recusa = await executarChamadaDeTool({ name: "apply_quote_price", input: { response_id: "resp-1" } }, aVista(aplicar, semPreco.db));
  assertEquals(recusa.toolResult, { error: "Essa resposta de cotação não tem preço registrado.", nada_registrado: true });
  assertEquals(recusa.proposal, undefined);
  assertEquals(pendencias(semPreco), []);
});

// ─── alterar_favorecido ─────────────────────────────────────────────────────────────────────────

const favorecido = ferramenta(favorecidoTools, "alterar_favorecido");
function favorecidos() {
  return {
    payees: [
      { id: "p-eli", name: "Eliane Souza", kind: "prestador", document: "11144477735", phone: "(47) 99999-0000", email: null, pix_key: "eliane@x.com",
        pix_key_type: "email", bank_name: "Banco A", bank_branch: "0001", bank_account: "12345-6", account_type: "corrente",
        default_category: null, active: true, notes: null },
    ],
    finance_rules: [],
    financial_categories: [],
  } as Record<string, Linha[]>;
}

Deno.test("S3 favorecido: trocar chave Pix, conta ou CPF/CNPJ é risco alto (PIN); o resto segue medium (só o sim)", () => {
  assertEquals(favorecido.risk, "medium", "o risco DECLARADO não muda: o perfil 'operacao' e o teste do financeiro dependem dele");
  assertEquals(favorecido.computeRisk, riscoDeAlterarFavorecido);
  for (const args of [
    { chave_pix: "11987654321", tipo_chave_pix: "telefone" }, { chave_pix: "a@b.com" }, { tipo_chave_pix: "cpf" }, { banco: "Banco B" },
    { agencia: "0002" }, { conta: "99999-1" }, { tipo_conta: "poupanca" }, { documento: "529.982.247-25" },
    { telefone: "47 98888-7777", conta: "99999-1" }, { chave_pix: 12345678900 },
  ]) {
    assertEquals(riscoDeAlterarFavorecido({ favorecido: "Eliane", ...args }), "high", JSON.stringify(args));
  }
  for (const args of [
    { telefone: "47 98888-7777" }, { email: "e@x.com" }, { novo_nome: "Eliane S." }, { ativo: false }, { categoria_padrao: "Alimentação" },
    { tipo: "diarista" }, {},
    // vazio, só espaço e nulo não mudam nada (a ferramenta só muda o campo que vem com texto)
    { chave_pix: "" }, { conta: "   " }, { documento: null }, { banco: undefined },
  ]) {
    assertEquals(riscoDeAlterarFavorecido({ favorecido: "Eliane", ...args }), "medium", JSON.stringify(args));
  }
});

Deno.test("S3 favorecido: o cálculo do risco é total — entrada estranha dá o risco mais alto, nunca exceção", () => {
  for (const estranha of ESTRANHAS) assertEquals(favorecido.computeRisk!(estranha), "high", String(typeof estranha));
  // um valor que lança ao virar texto também não derruba o turno
  const valorHostil = { toString() { throw new Error("sem texto"); } };
  assertEquals(favorecido.computeRisk!({ favorecido: "Eliane", chave_pix: valorHostil }), "high");
});

Deno.test("S3 favorecido: o cartão avisa logo abaixo do título quando muda Pix ou conta, e mostra o antigo e o novo", async () => {
  const pix = String(await resumirFavorecido(ctxDe(bancoFalso(favorecidos()).db), { favorecido: "Eliane", chave_pix: "11987654321", tipo_chave_pix: "telefone" }));
  assertEquals(pix.split("\n"), [
    "Alterar o favorecido *Eliane Souza*:",
    "🔒 Muda para onde vai o dinheiro (Pix ou conta): no WhatsApp, pede PIN.",
    "- Chave Pix: eliane@x.com → *11987654321*",
    "- Tipo da chave: email → *telefone*",
  ]);
  assertEquals(pix.split("\n")[1], AVISO_DO_DESTINO_DO_DINHEIRO);

  const conta = String(await resumirFavorecido(ctxDe(bancoFalso(favorecidos()).db), { favorecido: "Eliane", banco: "Banco B", agencia: "0002", conta: "99999-1" }));
  assertEquals(conta.split("\n"), [
    "Alterar o favorecido *Eliane Souza*:",
    AVISO_DO_DESTINO_DO_DINHEIRO,
    "- Banco: Banco A → *Banco B*",
    "- Agência: 0001 → *0002*",
    "- Conta: 12345-6 → *99999-1*",
  ]);

  // Telefone não é para onde vai o dinheiro: sem o aviso (e o risco é medium).
  const telefone = String(await resumirFavorecido(ctxDe(bancoFalso(favorecidos()).db), { favorecido: "Eliane", telefone: "47 98888-7777" }));
  assertEquals(telefone.split("\n"), ["Alterar o favorecido *Eliane Souza*:", "- Telefone: (47) 99999-0000 → *47 98888-7777*"]);
  // CPF/CNPJ pede PIN (risco alto), mas a frase do aviso fala de Pix e conta: não aparece. O antes e o depois, sim.
  const documento = String(await resumirFavorecido(ctxDe(bancoFalso(favorecidos()).db), { favorecido: "Eliane", documento: "529.982.247-25" }));
  assertEquals(documento.split("\n"), ["Alterar o favorecido *Eliane Souza*:", "- CPF/CNPJ: 11144477735 → *52998224725*"]);
});

Deno.test("S3 favorecido: pelo agente, a troca de Pix nasce pendência de risco alto (PIN) e a de telefone, medium", async () => {
  const b = bancoFalso(favorecidos());
  const r = await executarChamadaDeTool(
    { name: "alterar_favorecido", input: { favorecido: "Eliane", chave_pix: "11987654321", tipo_chave_pix: "telefone" } },
    aVista(favorecido, b.db),
  );
  assertEquals(r.proposal?.risk_level, "high");
  const [p] = pendencias(b);
  assertEquals(p.risk_level, "high", "é o risk_level gravado que cobra o PIN no sim");
  assertEquals(p.title, "Alterar favorecido");
  assertStringIncludes(p.summary, AVISO_DO_DESTINO_DO_DINHEIRO);
  assertStringIncludes(p.summary, "eliane@x.com → *11987654321*");
  assertEquals(b.tabelas.payees[0].pix_key, "eliane@x.com", "a chave só muda depois do sim com PIN");

  const b2 = bancoFalso(favorecidos());
  const r2 = await executarChamadaDeTool({ name: "alterar_favorecido", input: { favorecido: "Eliane", telefone: "47 98888-7777" } }, aVista(favorecido, b2.db));
  assertEquals(r2.proposal?.risk_level, "medium");
  assertEquals(pendencias(b2)[0].risk_level, "medium");
  assertEquals(String(pendencias(b2)[0].summary).includes("🔒"), false);
});

// ─── update_client ──────────────────────────────────────────────────────────────────────────────

const atualizar = ferramenta(clientTools, "update_client");
function clientes(muda: (t: Record<string, Linha[]>) => void = () => {}) {
  const tabelas: Record<string, Linha[]> = {
    clients: [
      { id: "c1", name: "João da Silva", type: "individual", cpf_cnpj: "508.421.889-91", phone: "(47) 99165-3158", whatsapp: "(47) 99165-3158",
        email: null, opt_out_whatsapp: false, active: true, notes: null },
      { id: "c2", name: "Nelson Prates", type: "individual", cpf_cnpj: null, phone: null, whatsapp: null, email: null, opt_out_whatsapp: true,
        active: true, notes: null },
    ],
  };
  muda(tabelas);
  return tabelas;
}

Deno.test("S3 cliente: telefone, WhatsApp ou a marca de não receber mensagens pedem o sim; o resto do cadastro segue direto", () => {
  assertEquals(atualizar.risk, "low", "declarado low: o que não mexe em contato continua rodando direto");
  assertEquals(atualizar.computeRisk, riscoDeAtualizarCliente);
  for (const args of [
    { phone: "47 99145-5678" }, { whatsapp: "47 99145-5678" }, { opt_out_whatsapp: true }, { opt_out_whatsapp: false },
    { email: "a@b.com", whatsapp: "47 99145-5678" },
    // APAGAR também é troca de contato (crítica de risco): vazio, só espaço e nulo pedem o sim
    { phone: "" }, { whatsapp: "" }, { phone: null }, { whatsapp: null }, { phone: "   " }, { opt_out_whatsapp: null },
    // valor torto na marca: erra para o lado do sim
    { opt_out_whatsapp: "true" }, { opt_out_whatsapp: 1 }, { phone: 47991455678 },
  ]) {
    assertEquals(riscoDeAtualizarCliente({ client_id: "c1", ...args }), "medium", JSON.stringify(args));
  }
  for (const args of [
    { email: "a@b.com" }, { name: "João S." }, { active: false, motivo: "vendeu o barco" }, { cpf_cnpj: "50842188991", city: "Itajaí" },
    { display_name: "João" }, { phone: undefined, whatsapp: undefined, opt_out_whatsapp: undefined }, {},
  ]) {
    assertEquals(riscoDeAtualizarCliente({ client_id: "c1", ...args }), "low", JSON.stringify(args));
  }
});

Deno.test("S3 cliente: o cálculo do risco é total — argumento indefinido não lança (derrubaria o turno) e dá o risco mais alto", () => {
  // A versão da especificação usava `"phone" in args`: com args indefinido, TypeError fora de try em executarChamadaDeTool.
  for (const estranha of ESTRANHAS) assertEquals(atualizar.computeRisk!(estranha), "medium", String(typeof estranha));
});

Deno.test("S3 cliente: o cartão mostra WhatsApp, telefone e a marca com o antes e o depois, e cita o que mais muda", async () => {
  const b = bancoFalso(clientes());
  const args = { client_id: "c1", whatsapp: "5547991455678", phone: "4733448088", opt_out_whatsapp: true, email: "joao@x.com", city: "Itajaí" };
  const cartao = await buildPendingSummary(b.db, "update_client", args, { userRole: "admin" });
  assertEquals(cartao.split("\n"), [
    "Trocar o contato do cliente *João da Silva*:",
    "- WhatsApp: (47) 99165-3158 → *(47) 99145-5678*",
    "- Telefone: (47) 99165-3158 → *(47) 3344-8088*",
    "- Não receber mensagens no WhatsApp: não → *sim*",
    "- Também muda: E-mail, Cidade",
  ]);
  assertEquals(resumoQueRecusa("update_client", cartao), null);
  assertEquals(b.gravacoes, [], "o resumo só lê");

  // Cadastro sem número: o antes é "—". Marca que volta: sim → não.
  assertEquals((await resumirTrocaDeContato(b.db, { client_id: "c2", whatsapp: "47 99145-5678", opt_out_whatsapp: false }))!.split("\n"), [
    "Trocar o contato do cliente *Nelson Prates*:",
    "- WhatsApp: — → *(47) 99145-5678*",
    "- Não receber mensagens no WhatsApp: sim → *não*",
  ]);
  // Só a marca.
  assertEquals(await resumirTrocaDeContato(b.db, { client_id: "c1", opt_out_whatsapp: true }),
    "Trocar o contato do cliente *João da Silva*:\n- Não receber mensagens no WhatsApp: não → *sim*");
  // Os rótulos dos outros campos são os do cartão genérico (rotuloDoCampo), em português.
  const outros = await resumirTrocaDeContato(b.db, { client_id: "c1", phone: "4733448088", cpf_cnpj: "50842188991", display_name: "João", type: "company",
    communication_tone: "informal", state_registration: "123", ie_indicator: "isento", notes: "obs" }, { rotulo: rotuloDoCampo });
  assertEquals(outros!.split("\n")[2], "- Também muda: CPF/CNPJ, Nome usado, Tipo, Tom da comunicação, Inscrição estadual, Indicador de IE, Observações");
});

Deno.test("S3 cliente: sem mexer em contato não há cartão de contato (o resumo genérico de sempre)", async () => {
  const b = bancoFalso(clientes());
  assertEquals(await resumirTrocaDeContato(b.db, { client_id: "c1", email: "joao@x.com" }), null);
  assertEquals(await buildPendingSummary(b.db, "update_client", { client_id: "c1", email: "joao@x.com" }), "- Cliente: c1\n- E-mail: joao@x.com");
  assertEquals(b.gravacoes, []);
});

Deno.test("S3 cliente: leitura que falha, cliente que não existe e pedido de APAGAR o número são recusa — a pendência não nasce", async () => {
  const falha = bancoFalso(clientes(), { "select:clients": "timeout" });
  const semLeitura = await buildPendingSummary(falha.db, "update_client", { client_id: "c1", whatsapp: "47 99145-5678" });
  assertEquals(semLeitura, "⚠️ Não consegui conferir o cliente agora. Nada foi alterado; tente de novo.");
  assertEquals(semLeitura, FALHA_AO_CONFERIR_O_CLIENTE);
  assert(resumoQueRecusa("update_client", semLeitura));
  // banco que lança (rede caída): a mesma frase, sem exceção
  assertEquals(await buildPendingSummary({ from() { throw new Error("rede caída"); } }, "update_client", { client_id: "c1", phone: "47 99145-5678" }),
    FALHA_AO_CONFERIR_O_CLIENTE);

  const b = bancoFalso(clientes());
  const casos: Array<[unknown, string]> = [
    [{ client_id: "nao-existe", phone: "47 99145-5678" }, "⚠️ Cliente não encontrado."],
    [{ phone: "47 99145-5678" }, "⚠️ Cliente não encontrado."],
    // Apagar: a execução descarta o que vem vazio ou nulo, então o cartão "→ —" seria um sim sobre o que não acontece.
    [{ client_id: "c1", phone: "" }, "⚠️ Telefone ou WhatsApp vazio: pelo assistente dá para trocar o número do cliente, mas não apagar (isso é na tela do cliente). Nada foi alterado."],
    [{ client_id: "c1", whatsapp: null, email: "joao@x.com" }, "⚠️ Telefone ou WhatsApp vazio: pelo assistente dá para trocar o número do cliente, mas não apagar (isso é na tela do cliente). Nada foi alterado."],
    [{ client_id: "c1", phone: "   ", whatsapp: "47 99145-5678" }, "⚠️ Telefone ou WhatsApp vazio: pelo assistente dá para trocar o número do cliente, mas não apagar (isso é na tela do cliente). Nada foi alterado."],
    [{ client_id: "c1", opt_out_whatsapp: "true" }, "⚠️ Não entendi se o cliente quer ou não receber mensagens no WhatsApp: diga sim ou não. Nada foi alterado."],
    [{ client_id: "c1", opt_out_whatsapp: null }, "⚠️ Nada para atualizar — informe ao menos um campo."],
    [undefined, "⚠️ Nada para atualizar — informe ao menos um campo."],
  ];
  for (const [args, esperado] of casos) {
    const resumo = await buildPendingSummary(b.db, "update_client", args as Record<string, unknown>);
    assertEquals(resumo, esperado, JSON.stringify(args));
    assert(resumoQueRecusa("update_client", resumo), JSON.stringify(args));
  }
  assertEquals(b.gravacoes, []);
});

Deno.test("S3 cliente (técnico): o que a execução recusaria é recusa antes do cartão; nome repetido igual ao gravado não entra", async () => {
  const b = bancoFalso(clientes());
  const recusa = await buildPendingSummary(b.db, "update_client", { client_id: "c1", phone: "47 99145-5678", name: "João Silva Jr" }, { userRole: "technician" });
  assertEquals(recusa, "⚠️ Só o escritório muda o nome de um cliente — peça ao escritório.");
  assert(resumoQueRecusa("update_client", recusa));
  // a execução diz a mesma frase (uma fonte só)
  // deno-lint-ignore no-explicit-any
  const exec = await atualizar.execute({ client_id: "c1", phone: "47 99145-5678", name: "João Silva Jr" }, ctxDe(b.db, { userRole: "technician" })) as any;
  assertEquals(`⚠️ ${exec.error}`, recusa);
  assertEquals(exec.nada_gravado, true);

  // O modelo repete o nome e o CPF ao trocar o telefone: iguais ao gravado, não são troca e não aparecem no cartão.
  const cartao = await buildPendingSummary(b.db, "update_client",
    { client_id: "c1", phone: "47 99145-5678", name: "João da Silva", cpf_cnpj: "50842188991", email: "joao@x.com" }, { userRole: "technician" });
  assertEquals(cartao.split("\n"), [
    "Trocar o contato do cliente *João da Silva*:",
    "- Telefone: (47) 99165-3158 → *(47) 99145-5678*",
    "- Também muda: E-mail",
  ]);
  // Para o escritório, nome e CPF/CNPJ continuam livres e aparecem no que mais muda.
  const doEscritorio = await buildPendingSummary(b.db, "update_client", { client_id: "c1", phone: "47 99145-5678", name: "João Silva Jr" }, { userRole: "admin" });
  assertEquals(doEscritorio.split("\n")[2], "- Também muda: Nome");
});

Deno.test("S3 cliente: pelo agente, à vista, a troca de contato vira pendência medium; o sim grava o que o cartão mostrou", async () => {
  const b = bancoFalso(clientes());
  const args = { client_id: "c1", whatsapp: "5547991455678", opt_out_whatsapp: true };
  const r = await executarChamadaDeTool({ name: "update_client", input: args }, aVista(atualizar, b.db));
  // deno-lint-ignore no-explicit-any
  assertEquals((r.toolResult as any).pending, true, JSON.stringify(r.toolResult));
  assertEquals(r.executou, false);
  assertEquals(r.proposal?.risk_level, "medium");
  const [p] = pendencias(b);
  assertEquals(p.action_name, "update_client");
  assertEquals(p.risk_level, "medium", "só o sim, sem PIN");
  assertEquals(p.title, "Corrigir cliente");
  assertEquals(p.payload, args);
  assertEquals(String(p.summary).split("\n"), [
    "Trocar o contato do cliente *João da Silva*:",
    "- WhatsApp: (47) 99165-3158 → *(47) 99145-5678*",
    "- Não receber mensagens no WhatsApp: não → *sim*",
  ]);
  assertEquals(b.tabelas.clients[0].whatsapp, "(47) 99165-3158", "o número só muda depois do sim");
  assertEquals(b.tabelas.clients[0].opt_out_whatsapp, false);

  // O sim executa o payload gravado: fica no cadastro o que o cartão mostrou.
  // deno-lint-ignore no-explicit-any
  const feito = await atualizar.execute(p.payload, ctxDe(b.db)) as any;
  assertEquals(feito.ok, true);
  assertEquals(b.tabelas.clients[0].whatsapp, "(47) 99145-5678");
  assertEquals(b.tabelas.clients[0].opt_out_whatsapp, true);
});

Deno.test("S3 cliente: pelo agente, o que não mexe em contato roda direto como antes; e nada estranho derruba o turno", async () => {
  const b = bancoFalso(clientes());
  const r = await executarChamadaDeTool({ name: "update_client", input: { client_id: "c1", email: "joao@x.com" } }, aVista(atualizar, b.db));
  assertEquals(r.executou, true);
  assertEquals(r.proposal, undefined);
  assertEquals(pendencias(b), []);
  assertEquals(b.tabelas.clients[0].email, "joao@x.com");

  // Pedido de apagar: risco medium (não roda direto) e recusa dita ao modelo, sem pendência e sem gravar.
  const apagar = await executarChamadaDeTool({ name: "update_client", input: { client_id: "c1", whatsapp: "" } }, aVista(atualizar, b.db));
  assertEquals(apagar.executou, false);
  // deno-lint-ignore no-explicit-any
  assertStringIncludes((apagar.toolResult as any).error, "não apagar");
  assertEquals(pendencias(b), []);
  assertEquals(b.tabelas.clients[0].whatsapp, "(47) 99165-3158");

  // Argumentos que não são objeto: antes, `"phone" in undefined` lançava fora de try. Agora é recusa, sem exceção.
  for (const estranha of [undefined, null, "texto", 42]) {
    const x = await executarChamadaDeTool({ name: "update_client", input: estranha }, aVista(atualizar, b.db));
    assertEquals(x.executou, false, String(estranha));
    assertEquals(x.proposal, undefined, String(estranha));
    // deno-lint-ignore no-explicit-any
    assert((x.toolResult as any).error, String(estranha));
  }
  assertEquals(pendencias(b), []);
});
