// "Serviço N" nas tools (F0 do porte da via v2): o número é o da via (created_at, id), número sozinho em remover/editar
// item PERGUNTA, e leitura que falha lança. Banco falso que filtra, ordena e grava em memória. Dado sintético.
import { assert, assertEquals, assertRejects, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { serviceOrderTools } from "./service-orders.ts";
import { fieldOpsTools } from "./field-ops.ts";

// deno-lint-ignore no-explicit-any
type Linha = Record<string, any>;

function bancoFalso(tabelas: Record<string, Linha[]>, falhas: Record<string, string> = {}) {
  const gravacoes: Array<{ op: string; tabela: string; valor?: unknown }> = [];
  function consulta(tabela: string) {
    const filtros: Array<(l: Linha) => boolean> = [];
    const ordem: Array<[string, boolean]> = [];
    let op: "select" | "update" | "insert" | "delete" = "select";
    // deno-lint-ignore no-explicit-any
    let valor: any = null;
    let unico = false;
    const executar = () => {
      const erro = falhas[`${op}:${tabela}`];
      if (erro) return { data: null, error: { message: erro } };
      const todas = (tabelas[tabela] ??= []);
      if (op === "insert") {
        gravacoes.push({ op, tabela, valor });
        return { data: null, error: null };
      }
      const alvo = todas.filter((l) => filtros.every((f) => f(l)));
      if (op === "update") { alvo.forEach((l) => Object.assign(l, valor)); gravacoes.push({ op, tabela, valor }); }
      if (op === "delete") { tabelas[tabela] = todas.filter((l) => !alvo.includes(l)); gravacoes.push({ op, tabela, valor: alvo.map((l) => l.id) }); }
      const res = alvo.map((l) => ({ ...l }));
      res.sort((a, b) => {
        for (const [c, asc] of ordem) {
          const x = String(a[c] ?? ""), y = String(b[c] ?? "");
          if (x !== y) return (x < y ? -1 : 1) * (asc ? 1 : -1);
        }
        return 0;
      });
      if (unico) return { data: res[0] ?? null, error: null };
      return { data: res, error: null };
    };
    // deno-lint-ignore no-explicit-any
    const q: any = {
      select: () => q,
      eq: (c: string, v: unknown) => { filtros.push((l) => l[c] === v); return q; },
      neq: (c: string, v: unknown) => { filtros.push((l) => l[c] !== v); return q; },
      in: (c: string, vs: unknown[]) => { filtros.push((l) => vs.includes(l[c])); return q; },
      order: (c: string, o?: { ascending?: boolean }) => { ordem.push([c, o?.ascending !== false]); return q; },
      limit: () => q,
      update: (v: unknown) => { op = "update"; valor = v; return q; },
      insert: (v: unknown) => { op = "insert"; valor = v; return q; },
      delete: () => { op = "delete"; return q; },
      single: () => { unico = true; return Promise.resolve(executar()); },
      maybeSingle: () => { unico = true; return Promise.resolve(executar()); },
      // deno-lint-ignore no-explicit-any
      then: (ok: any, ko: any) => Promise.resolve(executar()).then(ok, ko),
    };
    return q;
  }
  return { from: consulta, rpc: () => Promise.resolve({ data: null, error: null }), gravacoes, tabelas };
}

const ctxCom = (db: unknown) => ({ sb: db, admin: db, userId: "dono-1", userRole: "admin", jwt: "", appOrigin: "", settings: {} }) as never;
const tool = (lista: { name: string }[], nome: string) => lista.find((t) => t.name === nome)! as (typeof serviceOrderTools)[number];

const OS = "11111111-1111-4111-8111-111111111136";
const T = (ms: number) => `2026-11-16T18:00:00.${String(ms).padStart(3, "0")}000+00:00`;

/** O cartão da proposta do assistente: 4 peças (1–4) e 2 de mão de obra (5–6). Na via, a mão de obra é 1 e 2. */
function orcamento() {
  return {
    service_orders: [{ id: OS, service_order_number: "ORÇ-00136", status: "draft", grand_total: 1000 }],
    service_order_parts: [
      { id: "p1", service_order_id: OS, created_at: T(1), product_id: "pr1", quantity: 1, unit_sale_snapshot: 2000, unit_cost_snapshot: 1500, line_total_sale: 2000, products: { name: "Bateria LiFePO4 100Ah" } },
      { id: "p2", service_order_id: OS, created_at: T(2), product_id: "pr2", quantity: 2, unit_sale_snapshot: 50, unit_cost_snapshot: 20, line_total_sale: 100, products: { name: "Terminal 50mm" } },
      { id: "p3", service_order_id: OS, created_at: T(3), product_id: "pr3", quantity: 1, unit_sale_snapshot: 300, unit_cost_snapshot: 200, line_total_sale: 300, products: { name: "Disjuntor 125A" } },
      { id: "p4", service_order_id: OS, created_at: T(4), product_id: "pr4", quantity: 4, unit_sale_snapshot: 10, unit_cost_snapshot: 5, line_total_sale: 40, products: { name: "Abraçadeira" } },
    ],
    service_order_services: [
      // ordem física invertida: o banco ordena por created_at, id
      { id: "s2", service_order_id: OS, created_at: T(6), name_snapshot: "Deslocamento", quantity: 1, unit_price_snapshot: 200, line_total: 200, field_status: null, field_status_note: null },
      { id: "s1", service_order_id: OS, created_at: T(5), name_snapshot: "Instalação do banco de baterias", quantity: 1, unit_price_snapshot: 800, line_total: 800, field_status: null, field_status_note: null },
    ],
  };
}

for (const dito of ["4", "o 4", "tira o 4", "item 4"]) {
  Deno.test(`remover: 4 peças + 2 serviços, depois "${dito}" → needs_choice, nada apagado`, async () => {
    const db = bancoFalso(orcamento());
    const r = await tool(serviceOrderTools, "remove_service_order_item").execute(
      { service_order_id: OS, description: dito === "tira o 4" ? "4" : dito },
      ctxCom(db),
    ) as Linha;
    assertEquals(r.needs_choice, true, JSON.stringify(r));
    assertEquals(r.nada_alterado, true);
    assertStringIncludes(r.message, "não existe o serviço 4");
    // os 2 serviços com o número da via, e as peças à parte, sem número
    assertEquals(r.options.map((o: Linha) => o.descricao), ["1 · Instalação do banco de baterias", "2 · Deslocamento"]);
    assertEquals(r.pecas.map((p: Linha) => p.descricao), ["Bateria LiFePO4 100Ah", "Terminal 50mm", "Disjuntor 125A", "Abraçadeira"]);
    assertEquals(db.gravacoes.length, 0);
    assertEquals(db.tabelas.service_order_parts.length, 4);
    assertEquals(db.tabelas.service_order_services.length, 2);
  });
}

Deno.test("remover: 'serviço 2' existe — mesmo assim pergunta (é o 2 · Deslocamento?) e não apaga", async () => {
  const db = bancoFalso(orcamento());
  const r = await tool(serviceOrderTools, "remove_service_order_item").execute({ service_order_id: OS, description: "serviço 2" }, ctxCom(db)) as Linha;
  assertEquals(r.needs_choice, true);
  assertStringIncludes(r.message, 'O serviço 2 da via é "Deslocamento"');
  assertStringIncludes(r.message, "item_id");
  assertEquals(r.options, [{ item_id: "s2", numero: 2, descricao: "2 · Deslocamento", quantidade: 1, total: 200 }]);
  assertEquals(db.gravacoes.length, 0);
});

Deno.test("editar: '4' com preço novo → needs_choice, nada alterado", async () => {
  const db = bancoFalso(orcamento());
  const r = await tool(serviceOrderTools, "edit_service_order_item").execute(
    { service_order_id: OS, description: "4", unit_price: 1 },
    ctxCom(db),
  ) as Linha;
  assertEquals(r.needs_choice, true);
  assertStringIncludes(r.message, "editar");
  assertEquals(db.gravacoes.length, 0);
  assertEquals(db.tabelas.service_order_parts.find((p) => p.id === "p4")!.unit_sale_snapshot, 10);
});

Deno.test("remover pelo NOME: palavra inteira — 'LiFePO4' é a bateria; 'bater' (pedaço) não apaga nada", async () => {
  const pedaco = bancoFalso(orcamento());
  const r = await tool(serviceOrderTools, "remove_service_order_item").execute({ service_order_id: OS, description: "bater" }, ctxCom(pedaco)) as Linha;
  // pedaço de palavra não executa: pergunta, com a bateria e o banco de baterias como parecidos (revisão da F0, achador-3)
  assertEquals(r.needs_choice, true, JSON.stringify(r));
  assertEquals(r.options.map((o: Linha) => o.descricao), ["Bateria LiFePO4 100Ah", "1 · Instalação do banco de baterias"]);
  assertEquals(pedaco.gravacoes.length, 0);
  // com o item_id o número não importa: é o caminho preferencial
  const peloId = bancoFalso(orcamento());
  const r2 = await tool(serviceOrderTools, "edit_service_order_item").execute({ service_order_id: OS, item_id: "s2", description: "2", quantity: 2 }, ctxCom(peloId)) as Linha;
  assert(r2.ok, JSON.stringify(r2));
  assertEquals(peloId.tabelas.service_order_services.find((s) => s.id === "s2")!.quantity, 2);
});

/** Revisão da F0 (achador-1): a peça tem a palavra "4" solta e há 4 serviços na via. */
function orcamentoComCabo4() {
  return {
    service_orders: [{ id: OS, service_order_number: "ORÇ-00900", status: "draft", grand_total: 1000 }],
    service_order_parts: [
      { id: "p1", service_order_id: OS, created_at: T(1), product_id: "pr1", quantity: 1, unit_sale_snapshot: 10, unit_cost_snapshot: 5, line_total_sale: 10, products: { name: "Cabo flexível 4 mm" } },
      { id: "p2", service_order_id: OS, created_at: T(2), product_id: "pr2", quantity: 1, unit_sale_snapshot: 10, unit_cost_snapshot: 5, line_total_sale: 10, products: { name: "Terminal 50mm" } },
    ],
    service_order_services: ["Instalação do inversor", "Ar-condicionado do quarto", "Fita LED externa", "Troca do disjuntor"].map((n, i) => ({
      id: `s${i + 1}`, service_order_id: OS, created_at: T(100 + i), name_snapshot: n, quantity: 1, unit_price_snapshot: 100, line_total: 100, field_status: null, field_status_note: null,
    })),
  };
}

for (const dito of ["serviço #4", "o serviço #4", "No. 4", "4️⃣", "item #4", "linha #4", "(4)", '"4"', "serviço 4)"]) {
  Deno.test(`remover: "${dito}" é o número 4 escrito de outro jeito → pergunta; a peça "Cabo flexível 4 mm" fica`, async () => {
    const db = bancoFalso(orcamentoComCabo4());
    const r = await tool(serviceOrderTools, "remove_service_order_item").execute({ service_order_id: OS, description: dito }, ctxCom(db)) as Linha;
    assertEquals(r.needs_choice, true, JSON.stringify(r));
    assertEquals(r.nada_alterado, true);
    assertStringIncludes(r.message, 'O serviço 4 da via é "Troca do disjuntor"');
    assertEquals(db.gravacoes.length, 0);
    assertEquals(db.tabelas.service_order_parts.map((p) => p.id), ["p1", "p2"]);
  });
}

Deno.test("editar: 'serviço #4' com preço novo → pergunta; o cabo de 4 mm não muda", async () => {
  const db = bancoFalso(orcamentoComCabo4());
  const r = await tool(serviceOrderTools, "edit_service_order_item").execute({ service_order_id: OS, description: "serviço #4", unit_price: 1 }, ctxCom(db)) as Linha;
  assertEquals(r.needs_choice, true, JSON.stringify(r));
  assertEquals(db.gravacoes.length, 0);
  assertEquals(db.tabelas.service_order_parts.find((p) => p.id === "p1")!.unit_sale_snapshot, 10);
});

Deno.test("remover: '4 e 5' (só números) não casa nome por palavra; 'cabo 4' acha o cabo pelo nome", async () => {
  const soNumeros = bancoFalso(orcamentoComCabo4());
  const r = await tool(serviceOrderTools, "remove_service_order_item").execute({ service_order_id: OS, description: "4 e 5" }, ctxCom(soNumeros)) as Linha;
  // sem parecido nenhum: pergunta com a lista inteira (revisão da F0, achador-3)
  assertEquals(r.needs_choice, true, JSON.stringify(r));
  assertEquals(r.options.length + r.pecas.length, 6);
  assertEquals(soNumeros.gravacoes.length, 0);
  const peloNome = bancoFalso(orcamentoComCabo4());
  const r2 = await tool(serviceOrderTools, "remove_service_order_item").execute({ service_order_id: OS, description: "cabo 4" }, ctxCom(peloNome)) as Linha;
  assert(r2.ok, JSON.stringify(r2));
  assertEquals(r2.removido.descricao, "Cabo flexível 4 mm");
  assertEquals(peloNome.tabelas.service_order_parts.map((p) => p.id), ["p2"]);
});

Deno.test("update_service_order_via: 'serviço #4' com 'Troca de 4 pneus' na linha 2 marca a linha 4, não a 2", async () => {
  const nomes = ["Alinhamento", "Troca de 4 pneus", "Balanceamento", "Revisão do freio"];
  const db = bancoFalso({
    service_orders: [{ id: OS, service_order_number: "OS-00900", status: "in_progress", technician_notes: null, internal_notes: null, check_in_at: null, check_out_at: null }],
    service_order_services: nomes.map((n, i) => ({
      id: `l${i + 1}`, service_order_id: OS, created_at: T(i + 1), name_snapshot: n, field_status: "a_fazer", field_status_note: null,
    })),
  });
  const r = await tool(fieldOpsTools, "update_service_order_via").execute(
    { service_order_id: OS, servicos: [{ servico: "serviço #4", situacao: "feito" }] },
    ctxCom(db),
  ) as Linha;
  assert(r.ok, JSON.stringify(r));
  assertEquals(r.servicos_atualizados.map((s: Linha) => [s.numero, s.servico]), [[4, "Revisão do freio"]]);
  const linha = (id: string) => db.tabelas.service_order_services.find((l) => l.id === id)!;
  assertEquals([linha("l2").field_status, linha("l4").field_status], ["a_fazer", "feito"]);
});

Deno.test("leitura das peças com erro LANÇA (não vira 'Item não encontrado'), e nada é apagado", async () => {
  const db = bancoFalso(orcamento(), { "select:service_order_parts": "timeout" });
  await assertRejects(
    () => tool(serviceOrderTools, "remove_service_order_item").execute({ service_order_id: OS, description: "Abraçadeira" }, ctxCom(db)),
    Error,
    "timeout",
  );
  const db2 = bancoFalso(orcamento(), { "select:service_order_services": "sem rede" });
  await assertRejects(
    () => tool(serviceOrderTools, "edit_service_order_item").execute({ service_order_id: OS, description: "Abraçadeira", quantity: 2 }, ctxCom(db2)),
    Error,
    "sem rede",
  );
  assertEquals(db.gravacoes.length + db2.gravacoes.length, 0);
});

Deno.test("get_service_order: cada serviço com o numero da via, na ordem created_at, id", async () => {
  const db = bancoFalso({ ...orcamento(), service_order_steps: [] });
  const r = await tool(serviceOrderTools, "get_service_order").execute({ id: OS }, ctxCom(db)) as Linha;
  assertEquals(r.services.map((s: Linha) => [s.numero, s.servico]), [[1, "Instalação do banco de baterias"], [2, "Deslocamento"]]);
});

Deno.test("update_service_order_via: '4' numa OS com LiFePO4 na linha 1 marca a linha 4 (antes marcava a 1, calado)", async () => {
  const nomes = ["Instalação de bateria LiFePO4 200 Ah", "Serviço de revisão do gerador", "Troca do inversor 3000 W", "Fita LED externa", "Deslocamento"];
  const db = bancoFalso({
    service_orders: [{ id: OS, service_order_number: "OS-00140", status: "in_progress", technician_notes: null, internal_notes: null, check_in_at: null, check_out_at: null }],
    service_order_services: nomes.map((n, i) => ({
      id: `l${i + 1}`, service_order_id: OS, created_at: T(i + 1), name_snapshot: n, field_status: "a_fazer", field_status_note: null,
    })).reverse(),
  });
  const r = await tool(fieldOpsTools, "update_service_order_via").execute(
    { service_order_id: OS, servicos: [{ servico: "4", situacao: "feito" }, { servico: "serviço 2", situacao: "feito" }] },
    ctxCom(db),
  ) as Linha;
  assert(r.ok, JSON.stringify(r));
  assertEquals(r.servicos_atualizados.map((s: Linha) => [s.numero, s.servico]), [[2, "Serviço de revisão do gerador"], [4, "Fita LED externa"]]);
  const linha = (id: string) => db.tabelas.service_order_services.find((l) => l.id === id)!;
  assertEquals([linha("l1").field_status, linha("l2").field_status, linha("l4").field_status], ["a_fazer", "feito", "feito"]);
});

Deno.test("update_service_order_via: '200' numa OS de 2 → pergunta com a lista 'N · nome', nada gravado", async () => {
  const db = bancoFalso({
    service_orders: [{ id: OS, service_order_number: "OS-00140", status: "in_progress" }],
    service_order_services: [
      { id: "a", service_order_id: OS, created_at: T(1), name_snapshot: "Bateria 200 Ah", field_status: "a_fazer", field_status_note: null },
      { id: "b", service_order_id: OS, created_at: T(2), name_snapshot: "Deslocamento", field_status: "a_fazer", field_status_note: null },
    ],
  });
  const r = await tool(fieldOpsTools, "update_service_order_via").execute(
    { service_order_id: OS, servicos: [{ servico: "200", situacao: "feito" }] },
    ctxCom(db),
  ) as Linha;
  assertEquals(r.nada_gravado, true);
  assertStringIncludes(r.error, "A OS tem 2 serviços; não existe o 200. Serviços: 1 · Bateria 200 Ah; 2 · Deslocamento.");
  assertEquals(r.servicos_da_os, ["1 · Bateria 200 Ah", "2 · Deslocamento"]);
  assertEquals(db.gravacoes.length, 0);
});

// ═══ Ordinal por extenso (revisão da F0, achador-2): "o quarto" é o 4º — e "quarto" também é o cômodo ═══════════

for (const dito of ["o quarto", "quarto", "a quarta", "o quarto serviço"]) {
  Deno.test(`remover: "${dito}" é ordinal → pergunta pelo serviço 4 E pelo "Ar-condicionado do quarto"; nada removido`, async () => {
    const db = bancoFalso(orcamentoComCabo4());
    const r = await tool(serviceOrderTools, "remove_service_order_item").execute({ service_order_id: OS, description: dito }, ctxCom(db)) as Linha;
    assertEquals(r.needs_choice, true, JSON.stringify(r));
    assertEquals(r.nada_alterado, true);
    // o cômodo entra nas opções ao lado do serviço 4, como no acharLinha (revisão final, c-4)
    assertStringIncludes(
      r.message,
      `"${dito}" pode ser o serviço 4 da via ("Troca do disjuntor") ou o que tem "quarto" no nome: 2 · Ar-condicionado do quarto.`,
    );
    assertEquals(r.options.map((o: Linha) => o.item_id), ["s4", "s2"]);
    assertEquals(db.gravacoes.length, 0);
    assertEquals(db.tabelas.service_order_services.map((s) => s.id), ["s1", "s2", "s3", "s4"]);
  });
}

// ═══ Revisão final, c-4: com o ordinal, a pergunta oferece também o item com a palavra no nome ═══════════════════════

/** A OS da sonda (rev-final/sondas/c/remover.ts): o cômodo é o serviço 1 e o 4 é o disjuntor. */
function orcamentoDoQuarto(servicos: string[], pecas: string[] = ["Disjuntor 125A"]) {
  return {
    service_orders: [{ id: OS, service_order_number: "OS-00990", status: "approved", grand_total: 1000 }],
    service_order_parts: pecas.map((n, i) => ({
      id: `p${i + 1}`, service_order_id: OS, created_at: T(i + 1), product_id: `pr${i + 1}`, quantity: 1, unit_sale_snapshot: 10, unit_cost_snapshot: 5, line_total_sale: 10, products: { name: n },
    })),
    service_order_services: servicos.map((n, i) => ({
      id: `s${i + 1}`, service_order_id: OS, created_at: T(50 + i), name_snapshot: n, quantity: 1, unit_price_snapshot: 100, line_total: 100, field_status: null, field_status_note: null,
    })),
  };
}

Deno.test("remover/editar: 'o quarto' com o cômodo no serviço 1 → as opções têm o 4 E o 1; nada removido nem editado (c-4)", async () => {
  const servicos = ["Ar-condicionado do quarto", "Fita LED", "Bomba", "Troca do disjuntor"];
  const db = bancoFalso(orcamentoDoQuarto(servicos));
  const r = await tool(serviceOrderTools, "remove_service_order_item").execute({ service_order_id: OS, description: "o quarto" }, ctxCom(db)) as Linha;
  assertEquals(r.needs_choice, true, JSON.stringify(r));
  assertEquals(r.nada_alterado, true);
  assertEquals(r.options.map((o: Linha) => o.item_id), ["s4", "s1"]);
  assertEquals(r.options.map((o: Linha) => o.descricao), ["4 · Troca do disjuntor", "1 · Ar-condicionado do quarto"]);
  assertStringIncludes(r.message, 'pode ser o serviço 4 da via ("Troca do disjuntor") ou o que tem "quarto" no nome: 1 · Ar-condicionado do quarto');
  assertStringIncludes(r.message, "item_id");
  assertEquals(r.pecas.map((p: Linha) => p.descricao), ["Disjuntor 125A"]);
  assertEquals(db.gravacoes.length, 0);
  assertEquals(db.tabelas.service_order_services.map((s) => s.id), ["s1", "s2", "s3", "s4"]);
  const ed = bancoFalso(orcamentoDoQuarto(servicos));
  const r2 = await tool(serviceOrderTools, "edit_service_order_item").execute({ service_order_id: OS, description: "o quarto", unit_price: 1 }, ctxCom(ed)) as Linha;
  assertEquals(r2.needs_choice, true, JSON.stringify(r2));
  assertEquals(r2.options.map((o: Linha) => o.item_id), ["s4", "s1"]);
  assertStringIncludes(r2.message, "editar");
  assertEquals(ed.gravacoes.length, 0);
  assertEquals(ed.tabelas.service_order_services.map((s) => s.unit_price_snapshot), [100, 100, 100, 100]);
});

Deno.test("remover: 'o quarto' sem o serviço 4 e com a PEÇA 'Luminária do quarto' → pergunta com a peça; nada removido (c-4)", async () => {
  const db = bancoFalso(orcamentoDoQuarto(["Instalação do inversor", "Fita LED"], ["Luminária do quarto", "Terminal 50mm"]));
  const r = await tool(serviceOrderTools, "remove_service_order_item").execute({ service_order_id: OS, description: "o quarto" }, ctxCom(db)) as Linha;
  assertEquals(r.needs_choice, true, JSON.stringify(r));
  assertEquals(r.nada_alterado, true);
  assertEquals(r.options, [{ item_id: "p1", descricao: "Luminária do quarto", quantidade: 1, total: 10 }]);
  assertStringIncludes(
    r.message,
    '"o quarto" pode ser o serviço 4 (este orçamento/OS tem 2 serviços) ou o que tem "quarto" no nome: Luminária do quarto.',
  );
  assertEquals(db.gravacoes.length, 0);
  assertEquals(db.tabelas.service_order_parts.map((p) => p.id), ["p1", "p2"]);
});

// ═══ Revisão final, c-2: "linha" é substantivo em náutica — "a linha de combustível" nunca apaga o filtro calado ══════

const DITOS_DA_LINHA: Array<[dito: string, pecas: string[]]> = [
  ["linha de combustível", ["Filtro de combustível", "Abraçadeira inox"]],
  ["a linha de combustível", ["Filtro de combustível", "Abraçadeira inox"]],
  ["linha d'água", ["Bomba d'água 12V", "Abraçadeira inox"]],
  ["a linha d'água", ["Bomba d'água 12V", "Abraçadeira inox"]],
  ["linha de ancoragem", ["Cabo de ancoragem 10 mm", "Manilha"]],
  ["a linha de ancoragem", ["Cabo de ancoragem 10 mm", "Manilha"]],
];

for (const [dito, pecas] of DITOS_DA_LINHA) {
  Deno.test(`remover/editar: "${dito}" com a peça "${pecas[0]}" (sem "linha" no nome) → pergunta; nada apagado nem editado`, async () => {
    const db = bancoFalso(orcamentoDoQuarto(["Revisão do motor"], pecas));
    const r = await tool(serviceOrderTools, "remove_service_order_item").execute({ service_order_id: OS, description: dito }, ctxCom(db)) as Linha;
    assertEquals(r.needs_choice, true, JSON.stringify(r));
    assertEquals(r.nada_alterado, true);
    assertEquals(r.options.map((o: Linha) => o.item_id), ["p1"]);
    assertStringIncludes(r.message, `Não achei "${dito}" pelo nome inteiro. Parecido: ${pecas[0]}.`);
    assertEquals(db.gravacoes.length, 0);
    assertEquals(db.tabelas.service_order_parts.map((p) => p.id), ["p1", "p2"]);
    const ed = bancoFalso(orcamentoDoQuarto(["Revisão do motor"], pecas));
    const r2 = await tool(serviceOrderTools, "edit_service_order_item").execute({ service_order_id: OS, description: dito, unit_price: 1 }, ctxCom(ed)) as Linha;
    assertEquals(r2.needs_choice, true, JSON.stringify(r2));
    assertEquals(r2.options.map((o: Linha) => o.item_id), ["p1"]);
    assertEquals(ed.gravacoes.length, 0);
    assertEquals(ed.tabelas.service_order_parts.map((p) => p.unit_sale_snapshot), [10, 10]);
  });
}

Deno.test("remover: 'a linha de combustível' com 'linha' no nome da peça remove direto (c-2 só pergunta quando o nome não tem 'linha')", async () => {
  const db = bancoFalso(orcamentoDoQuarto(["Revisão do motor"], ["Mangueira da linha de combustível", "Abraçadeira inox"]));
  const r = await tool(serviceOrderTools, "remove_service_order_item").execute({ service_order_id: OS, description: "a linha de combustível" }, ctxCom(db)) as Linha;
  assert(r.ok, JSON.stringify(r));
  assertEquals(r.removido.descricao, "Mangueira da linha de combustível");
  assertEquals(db.tabelas.service_order_parts.map((p) => p.id), ["p2"]);
});

// ═══ Revisão final, c-5: a pergunta do update_service_order_via usa a frase do acharLinha ═══════════════════════════

Deno.test("update_service_order_via: 'o quarto' numa OS de 2 com o cômodo na 2 → a frase diz o porquê (uma opção só), nada gravado", async () => {
  const servicos = (nomes: string[]) => nomes.map((n, i) => ({
    id: `l${i + 1}`, service_order_id: OS, created_at: T(i + 1), name_snapshot: n, field_status: "a_fazer", field_status_note: null,
  }));
  const os = (numero: string) => [{ id: OS, service_order_number: numero, status: "in_progress", technician_notes: null, internal_notes: null, check_in_at: null, check_out_at: null }];
  const db = bancoFalso({ service_orders: os("OS-00906"), service_order_services: servicos(["Instalação do inversor", "Ar-condicionado do quarto"]) });
  const r = await tool(fieldOpsTools, "update_service_order_via").execute(
    { service_order_id: OS, servicos: [{ servico: "o quarto", situacao: "feito" }] },
    ctxCom(db),
  ) as Linha;
  assertEquals(r.nada_gravado, true, JSON.stringify(r));
  assertStringIncludes(
    r.error,
    '"o quarto" pode ser o serviço 4 (a OS tem 2) ou o que tem "quarto" no nome: 2 · Ar-condicionado do quarto. Use o número. (OS-00906)',
  );
  assert(!r.error.includes("serve para mais de um serviço"), r.error);
  assertEquals(db.gravacoes.length, 0);
  // a ambiguidade comum segue dizendo que casa com mais de um, com a lista
  const duas = bancoFalso({ service_orders: os("OS-00907"), service_order_services: servicos(["Instalação do inversor", "Teste do inversor"]) });
  const r2 = await tool(fieldOpsTools, "update_service_order_via").execute(
    { service_order_id: OS, servicos: [{ servico: "inversor", situacao: "feito" }] },
    ctxCom(duas),
  ) as Linha;
  assertEquals(r2.nada_gravado, true, JSON.stringify(r2));
  assertStringIncludes(r2.error, '"inversor" casa com mais de um serviço: 1 · Instalação do inversor; 2 · Teste do inversor. Use o número. (OS-00907)');
  assertEquals(duas.gravacoes.length, 0);
});

Deno.test("editar: 'o segundo' com preço novo → pergunta (o serviço 2 é o do quarto), nada alterado", async () => {
  const db = bancoFalso(orcamentoComCabo4());
  const r = await tool(serviceOrderTools, "edit_service_order_item").execute({ service_order_id: OS, description: "o segundo", unit_price: 1 }, ctxCom(db)) as Linha;
  assertEquals(r.needs_choice, true, JSON.stringify(r));
  assertStringIncludes(r.message, 'O serviço 2 da via é "Ar-condicionado do quarto"');
  assertEquals(db.gravacoes.length, 0);
});

Deno.test("update_service_order_via: 'o quarto' com o cômodo na linha 2 → pergunta, nada gravado; sem o cômodo, marca a 4", async () => {
  const servicos = (nomes: string[]) => nomes.map((n, i) => ({
    id: `l${i + 1}`, service_order_id: OS, created_at: T(i + 1), name_snapshot: n, field_status: "a_fazer", field_status_note: null,
  }));
  const comComodo = bancoFalso({
    service_orders: [{ id: OS, service_order_number: "OS-00901", status: "in_progress", technician_notes: null, internal_notes: null, check_in_at: null, check_out_at: null }],
    service_order_services: servicos(["Instalação do inversor", "Ar-condicionado do quarto", "Fita LED", "Troca do disjuntor"]),
  });
  const r = await tool(fieldOpsTools, "update_service_order_via").execute(
    { service_order_id: OS, servicos: [{ servico: "o quarto", situacao: "feito" }] },
    ctxCom(comComodo),
  ) as Linha;
  assertEquals(r.nada_gravado, true, JSON.stringify(r));
  assertStringIncludes(r.error, "4 · Troca do disjuntor");
  assertStringIncludes(r.error, "2 · Ar-condicionado do quarto");
  assertEquals(comComodo.tabelas.service_order_services.map((l) => l.field_status), ["a_fazer", "a_fazer", "a_fazer", "a_fazer"]);
  const semComodo = bancoFalso({
    service_orders: [{ id: OS, service_order_number: "OS-00902", status: "in_progress", technician_notes: null, internal_notes: null, check_in_at: null, check_out_at: null }],
    service_order_services: servicos(["Instalação do inversor", "Troca das baterias", "Fita LED", "Troca do disjuntor"]),
  });
  const r2 = await tool(fieldOpsTools, "update_service_order_via").execute(
    { service_order_id: OS, servicos: [{ servico: "o quarto", situacao: "feito" }] },
    ctxCom(semComodo),
  ) as Linha;
  assert(r2.ok, JSON.stringify(r2));
  assertEquals(r2.servicos_atualizados.map((s: Linha) => [s.numero, s.servico]), [[4, "Troca do disjuntor"]]);
});

// ═══ "o serviço do inversor" e o rótulo "N · nome" copiado da pergunta (revisão da F0, achador-4) ═══════════════════

Deno.test("remover: 'o serviço do inversor' (com artigo) acha 'Instalação do inversor' como 'serviço do inversor' acha", async () => {
  const db = bancoFalso(orcamentoComCabo4());
  const r = await tool(serviceOrderTools, "remove_service_order_item").execute({ service_order_id: OS, description: "o serviço do inversor" }, ctxCom(db)) as Linha;
  assert(r.ok, JSON.stringify(r));
  assertEquals(r.removido.descricao, "Instalação do inversor");
  assertEquals(db.tabelas.service_order_services.map((s) => s.id), ["s2", "s3", "s4"]);
});

Deno.test("update_service_order_via: '4 · Troca do disjuntor' (rótulo copiado) marca a 4; número e nome trocados perguntam", async () => {
  const servicos = () => ["Instalação do inversor", "Ar-condicionado do quarto", "Fita LED externa", "Troca do disjuntor"].map((n, i) => ({
    id: `l${i + 1}`, service_order_id: OS, created_at: T(i + 1), name_snapshot: n, field_status: "a_fazer", field_status_note: null,
  }));
  const os = () => [{ id: OS, service_order_number: "OS-00903", status: "in_progress", technician_notes: null, internal_notes: null, check_in_at: null, check_out_at: null }];
  for (const dito of ["4 · Troca do disjuntor", "4 - Troca do disjuntor", "o serviço do disjuntor"]) {
    const db = bancoFalso({ service_orders: os(), service_order_services: servicos() });
    const r = await tool(fieldOpsTools, "update_service_order_via").execute(
      { service_order_id: OS, servicos: [{ servico: dito, situacao: "feito" }] },
      ctxCom(db),
    ) as Linha;
    assert(r.ok, `${dito}: ${JSON.stringify(r)}`);
    assertEquals(r.servicos_atualizados.map((s: Linha) => [s.numero, s.servico]), [[4, "Troca do disjuntor"]], dito);
  }
  const trocado = bancoFalso({ service_orders: os(), service_order_services: servicos() });
  const r = await tool(fieldOpsTools, "update_service_order_via").execute(
    { service_order_id: OS, servicos: [{ servico: "3 · Troca do disjuntor", situacao: "feito" }] },
    ctxCom(trocado),
  ) as Linha;
  assertEquals(r.nada_gravado, true, JSON.stringify(r));
  assertEquals(trocado.gravacoes.length, 0);
});

// ═══ Sem achar pelo nome inteiro: pergunta, nunca "Item não encontrado" seco (revisão da F0, achador-3) ═════════════

/** Peças no plural e no singular, como o catálogo grava. */
function orcamentoDoPlural() {
  return {
    service_orders: [{ id: OS, service_order_number: "ORÇ-00904", status: "draft", grand_total: 500 }],
    service_order_parts: [
      { id: "p1", service_order_id: OS, created_at: T(1), product_id: "pr1", quantity: 10, unit_sale_snapshot: 2, unit_cost_snapshot: 1, line_total_sale: 20, products: { name: "Abraçadeiras nylon" } },
      { id: "p2", service_order_id: OS, created_at: T(2), product_id: "pr2", quantity: 5, unit_sale_snapshot: 30, unit_cost_snapshot: 20, line_total_sale: 150, products: { name: "Cabos 6 mm" } },
    ],
    service_order_services: [
      { id: "s1", service_order_id: OS, created_at: T(3), name_snapshot: "Instalação do inversor", quantity: 1, unit_price_snapshot: 300, line_total: 300, field_status: null, field_status_note: null },
    ],
  };
}

Deno.test("remover: 'abraçadeira' com a peça 'Abraçadeiras nylon' → pergunta com ela como parecida; nada apagado nem estornado", async () => {
  const db = bancoFalso(orcamentoDoPlural());
  const r = await tool(serviceOrderTools, "remove_service_order_item").execute({ service_order_id: OS, description: "abraçadeira" }, ctxCom(db)) as Linha;
  assertEquals(r.needs_choice, true, JSON.stringify(r));
  assertEquals(r.nada_alterado, true);
  assertEquals(r.options, [{ item_id: "p1", descricao: "Abraçadeiras nylon", quantidade: 10, total: 20 }]);
  assertStringIncludes(r.message, 'Não achei "abraçadeira" pelo nome inteiro. Parecido: Abraçadeiras nylon.');
  assertStringIncludes(r.message, "item_id");
  assertEquals(db.gravacoes.length, 0);
  assertEquals(db.tabelas.service_order_parts.map((p) => p.id), ["p1", "p2"]);
});

Deno.test("editar: 'cabo' com a peça 'Cabos 6 mm' → pergunta, preço não muda", async () => {
  const db = bancoFalso(orcamentoDoPlural());
  const r = await tool(serviceOrderTools, "edit_service_order_item").execute({ service_order_id: OS, description: "cabo", unit_price: 1 }, ctxCom(db)) as Linha;
  assertEquals(r.needs_choice, true, JSON.stringify(r));
  assertEquals(r.options.map((o: Linha) => o.item_id), ["p2"]);
  assertStringIncludes(r.message, "editar");
  assertEquals(db.gravacoes.length, 0);
  assertEquals(db.tabelas.service_order_parts.find((p) => p.id === "p2")!.unit_sale_snapshot, 30);
});

Deno.test("remover: nada parecido ('pintura') → pergunta com todos os itens: serviços 'N · nome' e as peças à parte", async () => {
  const db = bancoFalso(orcamentoDoPlural());
  const r = await tool(serviceOrderTools, "remove_service_order_item").execute({ service_order_id: OS, description: "pintura" }, ctxCom(db)) as Linha;
  assertEquals(r.needs_choice, true, JSON.stringify(r));
  assertEquals(r.nada_alterado, true);
  assertEquals(r.options, [{ item_id: "s1", numero: 1, descricao: "1 · Instalação do inversor", quantidade: 1, total: 300 }]);
  assertEquals(r.pecas.map((p: Linha) => p.descricao), ["Abraçadeiras nylon", "Cabos 6 mm"]);
  assertEquals(db.gravacoes.length, 0);
});

Deno.test("remover/editar pelo item_id que não existe: continua o erro (o id é exato, não há o que sugerir)", async () => {
  const db = bancoFalso(orcamentoDoPlural());
  const r = await tool(serviceOrderTools, "remove_service_order_item").execute({ service_order_id: OS, item_id: "nao-existe" }, ctxCom(db)) as Linha;
  assertEquals(r.error, "Item não encontrado neste orçamento/OS.");
  assertEquals(db.gravacoes.length, 0);
});
