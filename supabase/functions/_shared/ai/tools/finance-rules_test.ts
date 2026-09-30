import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { financeRulesTools, resolverClienteDito, resolverFornecedorDito } from "./finance-rules.ts";

/* Aprovar pelo assistente com a escolha "casar com o já lançado" — a linha que pode já estar
   lançada é recusada pelo servidor sem essa escolha, então ela tem de chegar inteira. */

const tool = (nome: string) => financeRulesTools.find((t) => t.name === nome)!;

Deno.test("aprovar leva a escolha de vínculo por proposta ao servidor", async () => {
  Deno.env.set("SUPABASE_URL", "https://exemplo.supabase.co");
  const original = globalThis.fetch;
  let corpo: any = null;
  globalThis.fetch = ((_url: string, init?: RequestInit) => {
    corpo = JSON.parse(String(init?.body ?? "{}"));
    return Promise.resolve(new Response(JSON.stringify({ ok: true, aprovadas: 2 }), { status: 200 }));
  }) as typeof fetch;
  try {
    const ctx = { sb: {}, admin: {}, userId: "u", userRole: "admin" as const, jwt: "jwt", appOrigin: "", settings: {} };
    await tool("aprovar_propostas_de_lancamento").execute(
      { ids: ["p84", "p75"], vinculos: { p84: "pg84", p75: "nenhum" } }, ctx as never);
  } finally {
    globalThis.fetch = original;
  }
  assertEquals(corpo, {
    action: "approve", ids: ["p84", "p75"],
    overrides: { p84: { vinculo: { id: "pg84" } }, p75: { vinculo: "nenhum" } },
  });
});

Deno.test("cadastrar a partir do extrato pede confirmação e só para o financeiro", () => {
  const t = tool("cadastrar_contraparte_do_extrato");
  assertEquals(t.risk, "medium");
  assertEquals(t.roles, ["admin", "financial"]);
});

/* Fornecedor dito pelo usuário (decisão do dono de 26/09/2026: nome diferente só por escolha
   dele). Um banco falso com a tabela de fornecedores, lida em páginas. */
function sbComFornecedores(lista: Array<{ id: string; name: string; trade_name?: string | null; cnpj_cpf?: string | null }>) {
  const linhas = lista.map((f) => ({ trade_name: null, cnpj_cpf: null, ...f }));
  const b: any = {
    select: () => b, order: () => b, eq: () => b,
    range: (de: number, ate: number) => Promise.resolve({ data: linhas.slice(de, ate + 1), error: null }),
    maybeSingle: () => Promise.resolve({ data: null, error: null }),
  };
  return { from: () => b };
}

Deno.test("fornecedor dito com acento acha o cadastro sem acento", async () => {
  const ctx = { sb: sbComFornecedores([{ id: "k1", name: "KAMELL COMERCIO GLOBAL LTDA", cnpj_cpf: "11.111.111/0001-11" }]) };
  assertEquals(await resolverFornecedorDito(ctx as never, "Kamell Comércio Global"), { id: "k1", nome: "KAMELL COMERCIO GLOBAL LTDA" });
});

Deno.test("matriz e filial com o mesmo nome são um cadastro só (a matriz)", async () => {
  const ctx = { sb: sbComFornecedores([
    { id: "filial", name: "Coremma Ltda", cnpj_cpf: "83.109.504/0006-86" },
    { id: "matriz", name: "COREMMA LTDA", cnpj_cpf: "83.109.504/0001-71" },
  ]) };
  assertEquals(await resolverFornecedorDito(ctx as never, "Coremma"), { id: "matriz", nome: "COREMMA LTDA" });
});

Deno.test("duas empresas com o mesmo nome viram pergunta, com id e CNPJ", async () => {
  const ctx = { sb: sbComFornecedores([
    { id: "a", name: "TIM S.A.", cnpj_cpf: "02.421.421/0001-11" },
    { id: "b", name: "TIM SA", cnpj_cpf: "99.999.999/0001-99" },
  ]) };
  const r = await resolverFornecedorDito(ctx as never, "Tim") as any;
  assertEquals(typeof r.error, "string");
  assertEquals(r.opcoes.map((o: any) => o.id).sort(), ["a", "b"]);
});

Deno.test("nome parcial nunca é escolhido calado: vira pergunta", async () => {
  const ctx = { sb: sbComFornecedores([{ id: "f", name: "FERNANDO NUNES FACHINI EPP" }]) };
  const r = await resolverFornecedorDito(ctx as never, "Fernando") as any;
  assertEquals(typeof r.error, "string");
  assertEquals(r.opcoes[0].id, "f");
});

Deno.test("aprovar leva as respostas de OS e OC, e recusa número no lugar do id", async () => {
  Deno.env.set("SUPABASE_URL", "https://exemplo.supabase.co");
  const original = globalThis.fetch;
  let corpo: any = null;
  globalThis.fetch = ((_url: string, init?: RequestInit) => {
    corpo = JSON.parse(String(init?.body ?? "{}"));
    return Promise.resolve(new Response(JSON.stringify({ ok: true }), { status: 200 }));
  }) as typeof fetch;
  const os = "11111111-1111-1111-1111-111111111111";
  const oc = "22222222-2222-2222-2222-222222222222";
  try {
    const ctx = { sb: {}, admin: {}, userId: "u", userRole: "admin" as const, jwt: "jwt", appOrigin: "", settings: {} };
    await tool("aprovar_propostas_de_lancamento").execute({ ids: ["p1", "p2"], os: { p1: os, p2: "nenhuma" }, oc: { p1: oc } }, ctx as never);
    const errado = await tool("aprovar_propostas_de_lancamento").execute({ ids: ["p1"], oc: { p1: "OC-0003" } }, ctx as never) as any;
    assertEquals(typeof errado.error, "string");
  } finally {
    globalThis.fetch = original;
  }
  assertEquals(corpo.overrides, { p1: { serviceOrderId: os, purchaseOrderId: oc }, p2: { serviceOrderId: null } });
});

/* "Para onde foi?" pelo assistente (decisão do dono, 26/09/2026): destino, centro de custo pelo
   NOME (só entre os ativos) e o que foi feito chegam ao servidor como a tela manda. */
function sbComCentros(lista: Array<{ id: string; name: string }>) {
  const b: any = {
    select: () => b, eq: () => b,
    order: () => Promise.resolve({ data: lista.map((c) => ({ ...c, active: true })), error: null }),
  };
  return { from: () => b };
}

Deno.test("aprovar leva destino, centro de custo (pelo nome) e o que foi feito", async () => {
  Deno.env.set("SUPABASE_URL", "https://exemplo.supabase.co");
  const original = globalThis.fetch;
  let corpo: any = null;
  globalThis.fetch = ((_url: string, init?: RequestInit) => {
    corpo = JSON.parse(String(init?.body ?? "{}"));
    return Promise.resolve(new Response(JSON.stringify({ ok: true }), { status: 200 }));
  }) as typeof fetch;
  try {
    const ctx = {
      sb: sbComCentros([{ id: "cc-obra", name: "Obras e reformas da sede" }, { id: "cc-veic", name: "Veículos da empresa" }]),
      admin: {}, userId: "u", userRole: "admin" as const, jwt: "jwt", appOrigin: "", settings: {},
    };
    await tool("aprovar_propostas_de_lancamento").execute({
      ids: ["p7"], destino: { p7: "empresa" }, centro_de_custo: { p7: "obras e reformas da SEDE" },
      observacao: { p7: "  pintura da fachada  " },
    }, ctx as never);
    // Centro que não existe (ou desativado) vira pergunta com as opções — nunca escolha.
    const r = await tool("aprovar_propostas_de_lancamento").execute({
      ids: ["p7"], destino: { p7: "empresa" }, centro_de_custo: { p7: "Despesas Administrativas" },
    }, ctx as never) as any;
    assertEquals(typeof r.error, "string");
    assertEquals(r.opcoes, ["Obras e reformas da sede", "Veículos da empresa"]);
    // Destino fora dos dois valores é recusado.
    const ruim = await tool("aprovar_propostas_de_lancamento").execute({ ids: ["p7"], destino: { p7: "sede" } }, ctx as never) as any;
    assertEquals(typeof ruim.error, "string");
  } finally {
    globalThis.fetch = original;
  }
  assertEquals(corpo.overrides, { p7: { destino: "empresa", costCenterId: "cc-obra", notes: "pintura da fachada" } });
});

/* Regra de ENTRADA (resposta 18 do dono): só por documento, com o cliente, e só sugere. Banco
   falso: clientes em páginas, categorias de receita, regras existentes e a contagem do extrato. */
function sbParaRegraDeEntrada(
  clientes: Array<{ id: string; name: string; cpf_cnpj?: string | null }>, existentes: any[] = [],
  categorias: Array<{ name: string; dre_group: string }> = [{ name: "Serviços prestados", dre_group: "receita" }],
) {
  const inseridas: any[] = [];
  const atualizadas: any[] = [];
  const tabela = (nome: string) => {
    const resposta = () => nome === "financial_categories"
      ? { data: categorias, error: null }
      : nome === "finance_rules" ? { data: existentes, error: null }
      : nome === "bank_transactions" ? { count: 3, data: null, error: null }
      : { data: [], error: null };
    const b: any = {
      select: () => b, eq: () => b, in: () => b, order: () => b,
      range: (de: number, ate: number) => Promise.resolve({
        data: nome === "clients" ? clientes.slice(de, ate + 1).map((c) => ({ cpf_cnpj: null, ...c })) : [], error: null,
      }),
      maybeSingle: () => Promise.resolve({ data: null, error: null }),
      insert: (linha: any) => {
        inseridas.push(linha);
        return { select: () => ({ single: () => Promise.resolve({ data: { id: "nova" }, error: null }) }) };
      },
      update: (linha: any) => { atualizadas.push(linha); return { eq: () => Promise.resolve({ error: null }) }; },
      then: (ok: (v: unknown) => unknown, falha?: (e: unknown) => unknown) => Promise.resolve(resposta()).then(ok, falha),
    };
    return b;
  };
  return { sb: { from: tabela }, inseridas, atualizadas };
}

const ctxDe = (sb: unknown) => ({ sb, admin: {}, userId: "u", userRole: "admin" as const, jwt: "jwt", appOrigin: "", settings: {} });

Deno.test("regra de entrada: documento + cliente pelo nome exato + categoria de receita, e só sugere", async () => {
  Deno.env.set("SUPABASE_URL", "https://exemplo.supabase.co");
  const original = globalThis.fetch;
  globalThis.fetch = (() => Promise.resolve(new Response(JSON.stringify({ ok: true, atualizadas: 1 }), { status: 200 }))) as typeof fetch;
  const banco = sbParaRegraDeEntrada([{ id: "c-joao", name: "João da Silva" }]);
  try {
    const t = tool("criar_regra_financeira");
    const ok = await t.execute({
      sentido: "entrada", reconhecer_por: "documento", valor_de_busca: "123.456.789-01",
      cliente: "joao da silva", categoria: "Serviços prestados",
    }, ctxDe(banco.sb) as never) as any;
    assertEquals(ok.ok, true);
    assertEquals(ok.cliente, "João da Silva");
    assertEquals(ok.entradas_deste_documento_no_extrato, 3);
    assertEquals(banco.inseridas[0], {
      match_type: "document", match_value: "12345678901", direction: "credit", origin: "user",
      reasoning: "Criada pelo assistente a pedido do usuário.",
      set_category: "Serviços prestados", set_dre_group: "receita", set_client_id: "c-joao", set_supplier_id: null,
      autonomy: "suggest", min_amount: null, max_amount: null, status: "active",
    });

    // Por nome não existe regra de entrada; lançar sozinha também não; documento curto, também não.
    const base = { sentido: "entrada", cliente: "João da Silva", categoria: "Serviços prestados" };
    const porNome = await t.execute({ ...base, reconhecer_por: "texto", valor_de_busca: "MARIA" }, ctxDe(banco.sb) as never) as any;
    assertEquals(typeof porNome.error, "string");
    const sozinha = await t.execute({ ...base, reconhecer_por: "documento", valor_de_busca: "12345678901", lancar_sozinha: true }, ctxDe(banco.sb) as never) as any;
    assertEquals(typeof sozinha.error, "string");
    const docCurto = await t.execute({ ...base, reconhecer_por: "documento", valor_de_busca: "1234567890" }, ctxDe(banco.sb) as never) as any;
    assertEquals(typeof docCurto.error, "string");
    assertEquals(banco.inseridas.length, 1);
  } finally {
    globalThis.fetch = original;
  }
});

Deno.test("regra de entrada que já existe com outro cliente só troca com o usuário dizendo", async () => {
  Deno.env.set("SUPABASE_URL", "https://exemplo.supabase.co");
  const original = globalThis.fetch;
  globalThis.fetch = (() => Promise.resolve(new Response(JSON.stringify({ ok: true }), { status: 200 }))) as typeof fetch;
  const banco = sbParaRegraDeEntrada([{ id: "c-joao", name: "João da Silva" }],
    [{ id: "r-velha", set_client_id: "c-outro", set_category: "Serviços prestados", status: "active" }]);
  try {
    const args = { sentido: "entrada", reconhecer_por: "documento", valor_de_busca: "12345678901", cliente: "João da Silva", categoria: "Serviços prestados" };
    const pergunta = await tool("criar_regra_financeira").execute(args, ctxDe(banco.sb) as never) as any;
    assertEquals(typeof pergunta.error, "string");
    assertEquals(banco.atualizadas.length, 0);
    const trocada = await tool("criar_regra_financeira").execute({ ...args, substituir_regra_existente: true }, ctxDe(banco.sb) as never) as any;
    assertEquals(trocada.ok, true);
    assertEquals(banco.atualizadas[0].set_client_id, "c-joao");
    assertEquals(banco.inseridas.length, 0);
  } finally {
    globalThis.fetch = original;
  }
});

Deno.test("cliente dito parecido vira pergunta, nunca escolha", async () => {
  const banco = sbParaRegraDeEntrada([{ id: "c1", name: "JOAO DA SILVA NETO" }, { id: "c2", name: "Ana Souza" }]);
  const r = await resolverClienteDito({ sb: banco.sb } as never, "João da Silva") as any;
  assertEquals(typeof r.error, "string");
  assertEquals(r.opcoes.map((o: any) => o.id), ["c1"]);
});

Deno.test("regra de entrada de aporte do sócio: sem cliente, sem perguntar cliente, e só sugere", async () => {
  Deno.env.set("SUPABASE_URL", "https://exemplo.supabase.co");
  const original = globalThis.fetch;
  globalThis.fetch = (() => Promise.resolve(new Response(JSON.stringify({ ok: true, atualizadas: 2 }), { status: 200 }))) as typeof fetch;
  // Nenhum cliente cadastrado: se a ferramenta procurasse o cliente, daria erro.
  const banco = sbParaRegraDeEntrada([], [], [
    { name: "Serviços prestados", dre_group: "receita" }, { name: "Aporte de sócio", dre_group: "nao_operacional" },
  ]);
  try {
    const ok = await tool("criar_regra_financeira").execute({
      sentido: "entrada", reconhecer_por: "documento", valor_de_busca: "123.456.789-01", categoria: "aporte de sócio",
    }, ctxDe(banco.sb) as never) as any;
    assertEquals(ok.ok, true);
    assertEquals(ok.cliente, null);
    assertEquals(banco.inseridas[0].set_client_id, null);
    assertEquals(banco.inseridas[0].set_category, "Aporte de sócio");
    assertEquals(banco.inseridas[0].autonomy, "suggest");
    // Receita comum continua exigindo o cliente.
    const semCliente = await tool("criar_regra_financeira").execute({
      sentido: "entrada", reconhecer_por: "documento", valor_de_busca: "98765432100", categoria: "Serviços prestados",
    }, ctxDe(banco.sb) as never) as any;
    assertEquals(typeof semCliente.error, "string");
    assertEquals(banco.inseridas.length, 1);
  } finally {
    globalThis.fetch = original;
  }
});

/* Trocar a categoria ao aprovar pelo WhatsApp (29/09/2026, "sim" do dono): o nome dito vira o
   nome exato do plano de contas, do tipo da proposta; categoria restrita só para o administrador. */
function sbComPropostasECategorias(
  propostas: Array<{ id: string; kind: string }>,
  categorias: Array<{ name: string; type: string; sensitive?: boolean }>,
) {
  return {
    from: (tabela: string) => {
      const filtros: Record<string, unknown> = {};
      const b: any = {
        select: () => b,
        eq: (c: string, v: unknown) => { filtros[c] = v; return b; },
        in: (_c: string, ids: string[]) => Promise.resolve({ data: propostas.filter((p) => ids.includes(p.id)), error: null }),
        order: () => Promise.resolve({
          data: tabela === "financial_categories"
            ? categorias.filter((c) => c.type === filtros.type).map((c) => ({ name: c.name, sensitive: !!c.sensitive }))
            : [],
          error: null,
        }),
      };
      return b;
    },
  };
}

Deno.test("aprovar troca a categoria pelo nome dito, conferido no plano de contas", async () => {
  Deno.env.set("SUPABASE_URL", "https://exemplo.supabase.co");
  const original = globalThis.fetch;
  let corpo: any = null;
  globalThis.fetch = ((_url: string, init?: RequestInit) => {
    corpo = JSON.parse(String(init?.body ?? "{}"));
    return Promise.resolve(new Response(JSON.stringify({ ok: true }), { status: 200 }));
  }) as typeof fetch;
  const sb = sbComPropostasECategorias(
    [{ id: "p1", kind: "create_payable" }, { id: "p2", kind: "create_receivable" }, { id: "p3", kind: "internal_transfer" }],
    [
      { name: "Alimentação de campo", type: "payable" },
      { name: "Pró-labore", type: "payable", sensitive: true },
      { name: "Receita de serviços", type: "receivable" },
    ],
  );
  try {
    const admin = { sb, admin: {}, userId: "u", userRole: "admin" as const, jwt: "jwt", appOrigin: "", settings: {} };
    await tool("aprovar_propostas_de_lancamento").execute(
      { ids: ["p1", "p2"], categoria: { p1: "alimentacao de CAMPO", p2: "Receita de serviços" } }, admin as never);
    assertEquals(corpo.overrides, { p1: { category: "Alimentação de campo" }, p2: { category: "Receita de serviços" } });

    // Nome fora do plano volta como pergunta, com as opções do tipo certo.
    const fora = await tool("aprovar_propostas_de_lancamento").execute(
      { ids: ["p1"], categoria: { p1: "Lanche" } }, admin as never) as any;
    assertEquals(typeof fora.error, "string");
    assertEquals(fora.opcoes, ["Alimentação de campo", "Pró-labore"]);

    // Categoria de saída numa entrada não existe para ela.
    const tipoErrado = await tool("aprovar_propostas_de_lancamento").execute(
      { ids: ["p2"], categoria: { p2: "Alimentação de campo" } }, admin as never) as any;
    assertEquals(typeof tipoErrado.error, "string");

    // Transferência não tem categoria para trocar.
    const transf = await tool("aprovar_propostas_de_lancamento").execute(
      { ids: ["p3"], categoria: { p3: "Alimentação de campo" } }, admin as never) as any;
    assertEquals(typeof transf.error, "string");

    // Restrita: o financeiro não escolhe, nem a vê nas opções.
    corpo = null;
    const financeiro = { ...admin, userRole: "financial" as const };
    const restrita = await tool("aprovar_propostas_de_lancamento").execute(
      { ids: ["p1"], categoria: { p1: "Pró-labore" } }, financeiro as never) as any;
    assertEquals(typeof restrita.error, "string");
    assertEquals(corpo, null);
    const opcoesDoFinanceiro = await tool("aprovar_propostas_de_lancamento").execute(
      { ids: ["p1"], categoria: { p1: "Lanche" } }, financeiro as never) as any;
    assertEquals(opcoesDoFinanceiro.opcoes, ["Alimentação de campo"]);
  } finally {
    globalThis.fetch = original;
  }
});
