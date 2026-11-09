// Retorno F3 (P10): as guardas de cadastro e de catálogo. Unidade duplicada, serviço pendente de catálogo (flag desligada) e
// duplicar orçamento sem copiar a origem nem a validade antiga. Nomes e números inventados.
import { assert, assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { criarUnidadeSemDuplicado, vesselTools } from "./vessels.ts";
import { resolverServicoDaLinha, serviceOrderTools } from "./service-orders.ts";
import { soOpsTools } from "./so-ops.ts";
import { montarOrcamento } from "./quote-builder.ts";

// deno-lint-ignore no-explicit-any
type Linha = Record<string, any>;

function bancoFalso(tabelas: Record<string, Linha[]>, op: { erroInsert?: Record<string, string>; erroSelect?: Record<string, string> } = {}) {
  const insercoes: Record<string, Linha[]> = {};
  const rpcs: Array<[string, Linha]> = [];
  function consulta(tabela: string) {
    const filtros: Array<[string, unknown]> = [];
    let modo: "select" | "insert" | "update" | "delete" = "select";
    let inserida: Linha | Linha[] | null = null;
    const resolver = (): Promise<{ data: unknown; error: { message: string } | null }> => {
      if (modo === "insert") {
        const erro = op.erroInsert?.[tabela];
        if (erro) return Promise.resolve({ data: null, error: { message: erro } });
        (insercoes[tabela] ??= []).push(...(Array.isArray(inserida) ? inserida : [inserida as Linha]));
        const primeira = Array.isArray(inserida) ? inserida[0] : inserida;
        return Promise.resolve({ data: { id: `nova-${tabela}`, service_order_number: "ORÇ-00151", ...primeira }, error: null });
      }
      if (modo !== "select") return Promise.resolve({ data: null, error: null });
      if (op.erroSelect?.[tabela]) return Promise.resolve({ data: null, error: { message: op.erroSelect[tabela] } });
      const linhas = (tabelas[tabela] ?? []).filter((l) => filtros.every(([c, v]) => l[c] === undefined || l[c] === v));
      return Promise.resolve({ data: linhas, error: null });
    };
    // deno-lint-ignore no-explicit-any
    const q: any = {
      select: () => q, gte: () => q, gt: () => q, neq: () => q, order: () => q, limit: () => q, range: () => q, ilike: () => q,
      eq: (c: string, v: unknown) => { filtros.push([c, v]); return q; },
      in: () => q,
      insert: (l: Linha | Linha[]) => { modo = "insert"; inserida = l; return q; },
      update: () => { modo = "update"; return q; },
      delete: () => { modo = "delete"; return q; },
      maybeSingle: async () => { const r = await resolver(); return { data: Array.isArray(r.data) ? (r.data[0] ?? null) : r.data, error: r.error }; },
      single: async () => { const r = await resolver(); return { data: Array.isArray(r.data) ? (r.data[0] ?? null) : r.data, error: r.error }; },
      then: (ok: (v: unknown) => unknown, nao: (e: unknown) => unknown) => resolver().then(ok, nao),
    };
    return q;
  }
  const db = {
    from: consulta,
    rpc: (fn: string, args: Linha) => {
      rpcs.push([fn, args]);
      if (fn === "next_document_number") return Promise.resolve({ data: 151, error: null });
      return Promise.resolve({ data: null, error: null });
    },
  };
  return { db, insercoes, rpcs, linhas: (t: string) => insercoes[t] ?? [] };
}

// deno-lint-ignore no-explicit-any
const ctxDe = (db: unknown, extra: Record<string, unknown> = {}): any =>
  ({ sb: db, admin: db, userId: "dono-1", userRole: "admin", jwt: "", appOrigin: "", settings: {}, ...extra });

// ─── create_vessel sem duplicado (P10.1) ────────────────────────────────────────────────────

const createVessel = vesselTools.find((t) => t.name === "create_vessel")!;
const UNIDADES = [
  { id: "v-1", name: "Brisa do Mar", client_id: "c-1", hull_id_or_registration: "ABC-123", active: true },
  { id: "v-2", name: "Veleiro Azul", client_id: "c-2", hull_id_or_registration: "ZZZ-999", active: true },
];

Deno.test("create_vessel: mesmo nome com acento e maiúscula diferentes devolve ja_cadastrada, sem insert", async () => {
  const b = bancoFalso({ vessels: UNIDADES });
  // deno-lint-ignore no-explicit-any
  const r = await createVessel.execute({ client_id: "c-1", name: "BRISA DO MÁR", asset_type: "Lancha" }, ctxDe(b.db)) as any;
  assertEquals(r.ok, false);
  assertEquals(r.ja_cadastrada[0].vessel_id, "v-1");
  assertStringIncludes(r.pergunta, "É a mesma?");
  assertEquals(b.linhas("vessels"), []);
});

Deno.test("create_vessel: mesmo registro idem, e o input_schema oferece o campo", async () => {
  // deno-lint-ignore no-explicit-any
  const props = createVessel.input_schema.properties as any;
  assert(props.hull_id_or_registration);
  assertStringIncludes(props.confirmar_duplicado.description, "true só depois que o dono confirmar que é outra unidade");
  const b = bancoFalso({ vessels: UNIDADES });
  // deno-lint-ignore no-explicit-any
  const r = await createVessel.execute({ client_id: "c-1", name: "Outro Nome", asset_type: "Lancha", hull_id_or_registration: "abc-123" }, ctxDe(b.db)) as any;
  assertEquals(r.ok, false);
  assertEquals(b.linhas("vessels"), []);
});

Deno.test("create_vessel: nome diferente nunca casa, e outro cliente passa", async () => {
  const b = bancoFalso({ vessels: UNIDADES });
  // deno-lint-ignore no-explicit-any
  const parecido = await createVessel.execute({ client_id: "c-1", name: "Brisa", asset_type: "Lancha" }, ctxDe(b.db)) as any;
  assertEquals(parecido.ok, true);
  const c = bancoFalso({ vessels: UNIDADES });
  // deno-lint-ignore no-explicit-any
  const outro = await createVessel.execute({ client_id: "c-9", name: "Brisa do Mar", asset_type: "Lancha" }, ctxDe(c.db)) as any;
  assertEquals(outro.ok, true);
  assertEquals(c.linhas("vessels").length, 1);
});

Deno.test("create_vessel: confirmar_duplicado passa, e o campo não vai ao banco", async () => {
  const b = bancoFalso({ vessels: UNIDADES });
  // deno-lint-ignore no-explicit-any
  const r = await createVessel.execute({ client_id: "c-1", name: "Brisa do Mar", asset_type: "Lancha", confirmar_duplicado: true }, ctxDe(b.db)) as any;
  assertEquals(r.ok, true);
  assertEquals("confirmar_duplicado" in b.linhas("vessels")[0], false);
  assertEquals(b.linhas("vessels")[0].name, "Brisa do Mar");
});

Deno.test("criarUnidadeSemDuplicado responde igual ao execute", async () => {
  const b = bancoFalso({ vessels: UNIDADES });
  const campos = { client_id: "c-1", name: "brisa do mar", asset_type: "Lancha" };
  const direto = await criarUnidadeSemDuplicado(b.db, campos);
  const pelaTool = await createVessel.execute(campos, ctxDe(b.db));
  assertEquals(direto, pelaTool);

  const c = bancoFalso({ vessels: [] });
  // deno-lint-ignore no-explicit-any
  const criada = await criarUnidadeSemDuplicado(c.db, { client_id: "c-1", name: "Nova", asset_type: "Lancha" }) as any;
  assertEquals(criada.ok, true);
  assertEquals(criada.vessel.name, "Nova");
});

// ─── Serviço pendente de catálogo (P10.2) ───────────────────────────────────────────────────

const CATALOGO = [{ id: "s-1", name: "Instalação Elétrica", created_at: "2026-01-01T00:00:00Z", active: true }];

Deno.test("resolverServicoDaLinha: nome igual, sem acento nem caixa, reaproveita", async () => {
  const b = bancoFalso({ services: CATALOGO });
  assertEquals(await resolverServicoDaLinha(b.db, b.db, "instalacao eletrica", 500), { service_id: "s-1", criado: false });
  assertEquals(b.linhas("services"), []);
});

Deno.test("resolverServicoDaLinha: nome novo insere com a categoria", async () => {
  const b = bancoFalso({ services: CATALOGO });
  const r = await resolverServicoDaLinha(b.db, b.db, "Regulagem de cabos", 350, "visit");
  assertEquals(r, { service_id: "nova-services", criado: true });
  const [s] = b.linhas("services");
  assertEquals(s.name, "Regulagem de cabos");
  assertEquals(s.billing_unit, "visit");
  assertEquals(s.default_price, 350);
  assertEquals(s.category, "Pendente de catálogo");
  assertEquals(s.description, "Criado automaticamente pela mão de obra de um orçamento. Conferir nome e preço.");
  assertEquals(s.active, true);

  const u = bancoFalso({ services: [] });
  await resolverServicoDaLinha(u.db, u.db, "Outro serviço", 100);
  assertEquals(u.linhas("services")[0].billing_unit, "unit");
});

Deno.test("resolverServicoDaLinha: erro de leitura ou de gravação não lança e segue sem service_id", async () => {
  const leitura = bancoFalso({}, { erroSelect: { services: "falhou" } });
  assertEquals(await resolverServicoDaLinha(leitura.db, leitura.db, "Algo", 10), { service_id: null, criado: false });
  const gravacao = bancoFalso({ services: [] }, { erroInsert: { services: "falhou" } });
  assertEquals(await resolverServicoDaLinha(gravacao.db, gravacao.db, "Algo", 10), { service_id: null, criado: false });
  const vazio = bancoFalso({ services: [] });
  assertEquals(await resolverServicoDaLinha(vazio.db, vazio.db, "   ", 10), { service_id: null, criado: false });
  assertEquals(vazio.linhas("services"), []);
});

const addService = serviceOrderTools.find((t) => t.name === "add_service_to_order")!;
const FLAG_ON = { settings: { ai_servico_pendente_catalogo: "on" } };

Deno.test("add_service_to_order com a flag desligada não toca em services", async () => {
  const b = bancoFalso({ services: CATALOGO });
  await addService.execute({ service_order_id: "os-1", service_name: "Instalação Elétrica", unit_price: 500 }, ctxDe(b.db));
  assertEquals(b.linhas("services"), []);
  assertEquals(b.linhas("service_order_services")[0].service_id, null);
});

Deno.test("add_service_to_order com a flag ligada grava o service_id, e com service_id não procura", async () => {
  const b = bancoFalso({ services: CATALOGO });
  await addService.execute({ service_order_id: "os-1", service_name: "Instalação Elétrica", unit_price: 500 }, ctxDe(b.db, FLAG_ON));
  assertEquals(b.linhas("service_order_services")[0].service_id, "s-1");

  const novo = bancoFalso({ services: CATALOGO });
  await addService.execute({ service_order_id: "os-1", service_name: "Regulagem de cabos", unit_price: 350, billing_unit: "hour" }, ctxDe(novo.db, FLAG_ON));
  assertEquals(novo.linhas("services")[0].billing_unit, "hour");
  assertEquals(novo.linhas("service_order_services")[0].service_id, "nova-services");

  const comId = bancoFalso({ services: CATALOGO });
  await addService.execute({ service_order_id: "os-1", service_name: "Qualquer", service_id: "s-9", unit_price: 1 }, ctxDe(comId.db, FLAG_ON));
  assertEquals(comId.linhas("services"), []);
  assertEquals(comId.linhas("service_order_services")[0].service_id, "s-9");
});

const CLIENTE_E_UNIDADE = { clients: [{ id: "c-1", name: "Paulo", generico: false }], vessels: [{ id: "v-1", name: "Brisa" }], services: CATALOGO };
const LABOR = { client_id: "c-1", vessel_id: "v-1", title: "x", items: [], labor: [{ description: "Instalação Elétrica", price: 500 }] };

Deno.test("montarOrcamento: labor sem service_id só resolve o catálogo com a flag ligada", async () => {
  const b = bancoFalso(CLIENTE_E_UNIDADE);
  await montarOrcamento(LABOR, ctxDe(b.db));
  assertEquals(b.linhas("service_order_services")[0].service_id, null);

  const on = bancoFalso(CLIENTE_E_UNIDADE);
  await montarOrcamento(LABOR, ctxDe(on.db, FLAG_ON));
  assertEquals(on.linhas("service_order_services")[0].service_id, "s-1");
});

Deno.test("montarOrcamento: labor da proposta com service_id não passa pelo catálogo; sem service_id, cria com a flag", async () => {
  const b = bancoFalso(CLIENTE_E_UNIDADE);
  const origem = { origem: { valor: "retorno_previa" as const, chave8: "12345678" } };
  await montarOrcamento({ ...LABOR, labor: [{ service_id: "s-7", description: "Outra", price: 90, quantity: 1, billing_unit: "visit" }] }, ctxDe(b.db, FLAG_ON), origem);
  assertEquals(b.linhas("service_order_services")[0].service_id, "s-7");
  assertEquals(b.linhas("services"), []);

  const c = bancoFalso(CLIENTE_E_UNIDADE);
  await montarOrcamento({ ...LABOR, labor: [{ description: "Regulagem de cabos", price: 350, quantity: 1, billing_unit: "unit" }] }, ctxDe(c.db, FLAG_ON), origem);
  assertEquals(c.linhas("service_order_services")[0].service_id, "nova-services");
  assertEquals(c.linhas("services").length, 1);
});

// ─── duplicate_service_order (P8.4 e P10.3) ─────────────────────────────────────────────────

const duplicar = soOpsTools.find((t) => t.name === "duplicate_service_order")!;
const ORIGINAL = {
  id: "orc-1", service_order_number: "ORÇ-00100", client_id: "c-1", vessel_id: "v-1", status: "draft", priority: "normal",
  origem: "retorno_ditado", origem_chave8: "12345678", origem_parceiro_id: "p-1", quote_validity_date: "2026-09-01",
  discount_amount: 0, tax_amount: 0, service_order_parts: [], service_order_services: [],
};

Deno.test("duplicar com a sessão amarrada recusa, e nada é gravado", async () => {
  const b = bancoFalso({ service_orders: [ORIGINAL] });
  // deno-lint-ignore no-explicit-any
  const r = await duplicar.execute({ service_order_id: "orc-1" }, ctxDe(b.db, { sessaoAmarrada: true })) as any;
  assertEquals(r.error, "Com o caso amarrado, use a proposta do cartão: duplicar copiaria preço antigo sem você ver.");
  assertEquals(b.linhas("service_orders"), []);
  assertEquals(b.rpcs.length, 0);
});

Deno.test("a cópia sem amarra nasce com as três colunas nulas e quote_validity_date nulo", async () => {
  const b = bancoFalso({ service_orders: [ORIGINAL] });
  // deno-lint-ignore no-explicit-any
  const r = await duplicar.execute({ service_order_id: "orc-1" }, ctxDe(b.db)) as any;
  assert(!r.error, JSON.stringify(r));
  const [copia] = b.linhas("service_orders");
  for (const campo of ["origem", "origem_chave8", "origem_parceiro_id", "quote_validity_date"]) {
    assertEquals(campo in copia, false, campo);
  }
  assertEquals(copia.service_order_number, "ORÇ-00151");
});
