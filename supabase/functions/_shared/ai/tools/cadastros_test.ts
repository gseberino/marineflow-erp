// Frente CADASTROS (07/10/2026): busca tolerante de cliente/fornecedor, duplicado no create_client,
// indicador de IE, inativar/reativar cliente, editar marina e contatos da embarcação.
import { assert, assertEquals, assertRejects, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { clientTools } from "./clients.ts";
import { vesselTools } from "./vessels.ts";
import { purchasingTools } from "./purchasing.ts";
import { entity360Tools } from "./entity-360.ts";
import { formatarDocumento, formatarTelefone, notaDoCadastro, traduzirIndicadorIE } from "../busca-cadastro.ts";

// Banco falso: tabelas por nome; eq/in filtram; range pagina; insert/update gravam e ficam anotados.
// falhaLeitura[tabela] = mensagem → toda leitura da tabela devolve erro.
// deno-lint-ignore no-explicit-any
function bancoFalso(tabelas: Record<string, any[]>, falhaLeitura: Record<string, string> = {}) {
  // deno-lint-ignore no-explicit-any
  const chamadas = { insert: [] as [string, any][], update: [] as [string, any][], range: [] as [string, number, number][] };
  const db = {
    chamadas,
    tabelas,
    from(tabela: string) {
      const filtros: ((l: Record<string, unknown>) => boolean)[] = [];
      let faixa: [number, number] | null = null;
      const erro = () => (falhaLeitura[tabela] ? { message: falhaLeitura[tabela] } : null);
      const linhas = () => {
        const todas = (tabelas[tabela] ?? []).filter((l) => filtros.every((f) => f(l)));
        // Cópias, como o banco de verdade: o "antes" lido não pode mudar com o update.
        return (faixa ? todas.slice(faixa[0], faixa[1] + 1) : todas).map((l) => ({ ...l }));
      };
      const ler = () => (erro() ? { data: null, error: erro() } : { data: linhas(), error: null });
      // deno-lint-ignore no-explicit-any
      const q: any = {
        select: () => q,
        order: () => q,
        limit: () => q,
        or: () => q, like: () => q, ilike: () => q, gte: () => q, lte: () => q, is: () => q, not: () => q,
        eq: (c: string, v: unknown) => { filtros.push((l) => l[c] === v); return q; },
        in: (c: string, vs: unknown[]) => { filtros.push((l) => vs.includes(l[c])); return q; },
        range: (a: number, b: number) => { faixa = [a, b]; chamadas.range.push([tabela, a, b]); return q; },
        maybeSingle: () => Promise.resolve(erro() ? { data: null, error: erro() } : { data: linhas()[0] ?? null, error: null }),
        single: () => Promise.resolve(erro() ? { data: null, error: erro() } : { data: linhas()[0] ?? null, error: null }),
        // deno-lint-ignore no-explicit-any
        then: (ok: any, falha: any) => Promise.resolve(ler()).then(ok, falha),
        // deno-lint-ignore no-explicit-any
        insert: (v: any) => {
          chamadas.insert.push([tabela, v]);
          const nova = { id: `novo-${tabela}-${chamadas.insert.length}`, active: true, ...v };
          (tabelas[tabela] ??= []).push(nova);
          return { select: () => ({ single: () => Promise.resolve({ data: nova, error: null }) }) };
        },
        // deno-lint-ignore no-explicit-any
        update: (v: any) => {
          chamadas.update.push([tabela, v]);
          return {
            eq: (c: string, id: unknown) => {
              const alvo = (tabelas[tabela] ?? []).find((l) => l[c] === id);
              if (alvo) Object.assign(alvo, v);
              return { select: () => ({ single: () => Promise.resolve({ data: alvo ? { ...alvo } : null, error: null }) }) };
            },
          };
        },
      };
      return q;
    },
  };
  return db;
}
const ctxCom = (db: unknown, userRole = "admin") => ({ sb: db, admin: db, userId: "dono-1", userRole, jwt: "", appOrigin: "", settings: {} }) as never;
const tool = (nome: string) => [...clientTools, ...vesselTools, ...purchasingTools, ...entity360Tools].find((t) => t.name === nome)!;

const CLIENTES = () => [
  { id: "c1", name: "João da Silva", type: "individual", cpf_cnpj: "508.421.889-91", phone: "(47) 99165-3158", whatsapp: "(47) 99165-3158", email: null, city: "Itajaí", active: true, notes: null },
  { id: "c2", name: "Flávio da Igreja", type: "individual", cpf_cnpj: "02837819980", phone: "+55 47 99145-5678", whatsapp: null, email: null, city: null, active: true, notes: "cliente antigo" },
  { id: "c3", name: "Nelson Prates", type: "individual", cpf_cnpj: null, phone: "47988216669", whatsapp: null, email: null, city: null, active: false, notes: null },
];

// ── normalização ──────────────────────────────────────────────────────────────────────────────

Deno.test("formatos iguais aos da tela: CPF/CNPJ com máscara, telefone (47) 99999-9999 sem o +55", () => {
  assertEquals(formatarDocumento("50842188991"), "508.421.889-91");
  assertEquals(formatarDocumento("2837819980"), "028.378.199-80"); // zero que a planilha comeu
  assertEquals(formatarDocumento("12063636000161"), "12.063.636/0001-61");
  assertEquals(formatarTelefone("47991455678"), "(47) 99145-5678");
  assertEquals(formatarTelefone("+55 47 99145-5678"), "(47) 99145-5678");
  assertEquals(formatarTelefone("4733448088"), "(47) 3344-8088");
  assertEquals(formatarTelefone("+351966776422"), "+351966776422"); // estrangeiro fica como veio
});

Deno.test("indicador de IE: palavras viram 1/2/9 e o resto é recusado", () => {
  assertEquals(traduzirIndicadorIE("contribuinte"), 1);
  assertEquals(traduzirIndicadorIE("Isento"), 2);
  assertEquals(traduzirIndicadorIE("não contribuinte"), 9);
  assertEquals(traduzirIndicadorIE(9), 9);
  assertEquals(traduzirIndicadorIE(undefined), undefined);
  assert(typeof traduzirIndicadorIE("talvez") === "object");
  assert(typeof traduzirIndicadorIE(3) === "object");
});

Deno.test("nota: nome igual vale mais que contido; número casa documento e telefone por dígitos", () => {
  const campos = { texto: ["name"], documento: ["cpf_cnpj"], telefone: ["phone"] };
  const joao = CLIENTES()[0];
  assert(notaDoCadastro(joao, "joao da silva", campos) > notaDoCadastro(joao, "silva", campos));
  assert(notaDoCadastro(joao, "Silva Joao", campos) > 0); // palavras em qualquer ordem
  assertEquals(notaDoCadastro(joao, "Maria", campos), 0);
  assertEquals(notaDoCadastro(joao, "50842188991", campos), 100);
  assert(notaDoCadastro(joao, "47 99165 3158", campos) > 0);
  assert(notaDoCadastro(CLIENTES()[1], "(47) 99145-5678", campos) > 0); // gravado como +55 47 …
});

// ── search_clients / search_suppliers ─────────────────────────────────────────────────────────

Deno.test("search_clients: 'Joao' acha 'João', CPF só com dígitos acha o gravado com pontos; inativo só com incluir_inativos", async () => {
  const db = bancoFalso({ clients: CLIENTES() });
  const r1 = await tool("search_clients").execute({ query: "Joao" }, ctxCom(db)) as any;
  assertEquals(r1.results.map((c: any) => c.id), ["c1"]);
  const r2 = await tool("search_clients").execute({ query: "50842188991" }, ctxCom(db)) as any;
  assertEquals(r2.results.map((c: any) => c.id), ["c1"]);
  const r3 = await tool("search_clients").execute({ query: "Nelson" }, ctxCom(db)) as any;
  assertEquals(r3.results, []);
  const r4 = await tool("search_clients").execute({ query: "nelson", incluir_inativos: true }, ctxCom(db)) as any;
  assertEquals(r4.results.map((c: any) => [c.id, c.active]), [["c3", false]]);
  // Lê em páginas de 1000 (teto do PostgREST), nunca .limit() acima disso.
  assertEquals(db.chamadas.range[0], ["clients", 0, 999]);
});

Deno.test("search_clients: leitura que falha LANÇA (não vira 'nenhum cliente')", async () => {
  const db = bancoFalso({ clients: CLIENTES() }, { clients: "timeout" });
  await assertRejects(() => tool("search_clients").execute({ query: "Joao" }, ctxCom(db)));
});

Deno.test("search_clients: lê todas as páginas quando há mais de 1000", async () => {
  const muitos = Array.from({ length: 1500 }, (_, i) => ({ id: `x${String(i).padStart(4, "0")}`, name: `Cliente ${i}`, active: true }));
  muitos.push({ id: "z", name: "Zé Ninguém", active: true });
  const db = bancoFalso({ clients: muitos });
  const r = await tool("search_clients").execute({ query: "ze ninguem" }, ctxCom(db)) as any;
  assertEquals(r.results.map((c: any) => c.id), ["z"]);
  assertEquals(db.chamadas.range.length, 2);
});

Deno.test("search_suppliers: CNPJ sem pontos acha o gravado com máscara; sem acento", async () => {
  const db = bancoFalso({
    suppliers: [
      { id: "s1", name: "Náutica Itajaí", cnpj_cpf: "12.063.636/0001-61", phone: "554133448088", city: "Itajaí", active: true },
      { id: "s2", name: "Elétrica Sul", cnpj_cpf: "22.565.670/0001-98", phone: null, city: "Joinville", active: false },
    ],
  });
  const r1 = await tool("search_suppliers").execute({ query: "12063636000161" }, ctxCom(db)) as any;
  assertEquals(r1.results.map((s: any) => s.supplier_id), ["s1"]);
  const r2 = await tool("search_suppliers").execute({ query: "eletrica" }, ctxCom(db)) as any;
  assertEquals(r2.results.map((s: any) => [s.supplier_id, s.ativo]), [["s2", false]]);
  const r3 = await tool("search_suppliers").execute({ query: "(41) 3344-8088" }, ctxCom(db)) as any;
  assertEquals(r3.results.map((s: any) => s.supplier_id), ["s1"]);
  const falha = bancoFalso({ suppliers: [] }, { suppliers: "boom" });
  await assertRejects(() => tool("search_suppliers").execute({ query: "eletrica" }, ctxCom(falha)));
});

// ── create_client ─────────────────────────────────────────────────────────────────────────────

Deno.test("create_client: mesmo CPF (com outra máscara) NÃO cria — o caso do Flávio da Igreja", async () => {
  const db = bancoFalso({ clients: CLIENTES() });
  const r = await tool("create_client").execute({ name: "Flavio Igreja", type: "individual", cpf_cnpj: "028.378.199-80" }, ctxCom(db)) as any;
  assertEquals(r.ok, false);
  assertEquals(r.ja_cadastrado[0].client_id, "c2");
  assertEquals(db.chamadas.insert, []);
  // Nem com confirmar_duplicado: documento igual é a mesma pessoa.
  const r2 = await tool("create_client").execute({ name: "Flavio Igreja", type: "individual", cpf_cnpj: "02837819980", confirmar_duplicado: true }, ctxCom(db)) as any;
  assertEquals(r2.ok, false);
  assertEquals(db.chamadas.insert, []);
});

Deno.test("create_client: mesmo telefone pergunta; com confirmar_duplicado cria; grava no formato da tela", async () => {
  const db = bancoFalso({ clients: CLIENTES() });
  const r = await tool("create_client").execute({ name: "Maria Prates", type: "individual", phone: "47 98821-6669" }, ctxCom(db)) as any;
  assertEquals(r.ok, false);
  assertEquals(r.possiveis_duplicados.map((c: any) => [c.client_id, c.motivo, c.ativo]), [["c3", "mesmo telefone", false]]);
  assertEquals(db.chamadas.insert, []);

  const ok = await tool("create_client").execute({
    name: "Maria Prates", type: "individual", phone: "47 98821-6669", cpf_cnpj: "65725468020", ie_indicator: "não contribuinte", confirmar_duplicado: true,
  }, ctxCom(db)) as any;
  assertEquals(ok.ok, true);
  const [, gravado] = db.chamadas.insert[0];
  assertEquals(gravado.phone, "(47) 98821-6669");
  assertEquals(gravado.cpf_cnpj, "657.254.680-20");
  assertEquals(gravado.ie_indicator, 9);
  assertEquals("confirmar_duplicado" in gravado, false);
});

Deno.test("create_client: mesmo nome (sem acento) pergunta; indicador de IE inválido é recusado antes de gravar", async () => {
  const db = bancoFalso({ clients: CLIENTES() });
  const r = await tool("create_client").execute({ name: "Joao da Silva", type: "individual" }, ctxCom(db)) as any;
  assertEquals(r.possiveis_duplicados[0].motivo, "mesmo nome");
  const ie = await tool("create_client").execute({ name: "Empresa X", type: "company", ie_indicator: "simples nacional" }, ctxCom(db)) as any;
  assertStringIncludes(ie.error, "Indicador de IE");
  assertEquals(db.chamadas.insert, []);
});

Deno.test("create_client: leitura dos duplicados que falha LANÇA (não cria às cegas)", async () => {
  const db = bancoFalso({ clients: [] }, { clients: "timeout" });
  await assertRejects(() => tool("create_client").execute({ name: "Novo", type: "individual", cpf_cnpj: "50842188991" }, ctxCom(db)));
  assertEquals(db.chamadas.insert, []);
});

// ── update_client ─────────────────────────────────────────────────────────────────────────────

Deno.test("update_client: inativa com motivo nas observações (acrescentado) e reativa", async () => {
  const db = bancoFalso({ clients: CLIENTES() });
  const r = await tool("update_client").execute({ client_id: "c2", active: false, motivo: "vendeu o barco" }, ctxCom(db)) as any;
  assert(r.ok, JSON.stringify(r));
  const [, patch] = db.chamadas.update[0];
  assertEquals(patch.active, false);
  assert(String(patch.notes).startsWith("cliente antigo\n["));
  assertStringIncludes(patch.notes, "Inativado: vendeu o barco");
  assertStringIncludes(r.situacao, "inativo");

  const volta = await tool("update_client").execute({ client_id: "c2", active: true }, ctxCom(db)) as any;
  assertEquals(volta.situacao, "ativo");
});

Deno.test("update_client: troca para pessoa jurídica, traduz 'isento' e recusa CPF de outro cliente", async () => {
  const db = bancoFalso({ clients: CLIENTES() });
  const r = await tool("update_client").execute({ client_id: "c3", type: "company", ie_indicator: "isento", whatsapp: "5547988216669" }, ctxCom(db)) as any;
  assert(r.ok, JSON.stringify(r));
  assertEquals(db.chamadas.update[0][1], { type: "company", ie_indicator: 2, whatsapp: "(47) 98821-6669" });

  const dup = await tool("update_client").execute({ client_id: "c3", cpf_cnpj: "50842188991" }, ctxCom(db)) as any;
  assertStringIncludes(dup.error, "já é de outro cliente");
  assertEquals(db.chamadas.update.length, 1);

  const ruim = await tool("update_client").execute({ client_id: "c3", ie_indicator: "3" }, ctxCom(db)) as any;
  assertStringIncludes(ruim.error, "Indicador de IE");
});

Deno.test("update_client: cliente que não existe e leitura que falha", async () => {
  const db = bancoFalso({ clients: CLIENTES() });
  const r = await tool("update_client").execute({ client_id: "nao-existe", active: false }, ctxCom(db)) as any;
  assertEquals(r.error, "Cliente não encontrado.");
  const falha = bancoFalso({ clients: CLIENTES() }, { clients: "boom" });
  await assertRejects(() => tool("update_client").execute({ client_id: "c1", active: false }, ctxCom(falha)));
  assertEquals(falha.chamadas.update, []);
});

// ── marina ────────────────────────────────────────────────────────────────────────────────────

const MARINAS = () => [
  { id: "m1", name: "Marina Porto Belo", contact_name: "Rita", phone: "(47) 3369-0000", city: "Porto Belo", state: "SC", active: true, address_line_1: null },
  { id: "m2", name: "Marina Itajaí", contact_name: null, phone: null, city: "Itajaí", state: "SC", active: true, address_line_1: null },
  { id: "m3", name: "Marina Itajaí Sul", contact_name: null, phone: null, city: "Itajaí", state: "SC", active: false, address_line_1: null },
];

Deno.test("update_marina: pelo nome dito, telefone no formato da tela, endereço num campo só", async () => {
  const db = bancoFalso({ marinas: MARINAS() });
  const r = await tool("update_marina").execute({
    marina: "Porto Belo", phone: "47 99999 1234", address_line_1: "Av. Gov. Celso Ramos", address_number: "100", postal_code: "88210000", state: "sc",
  }, ctxCom(db)) as any;
  assert(r.ok, JSON.stringify(r));
  assertEquals(db.chamadas.update[0][1], {
    phone: "(47) 99999-1234", address_line_1: "Av. Gov. Celso Ramos, 100", postal_code: "88210-000", state: "SC",
  });
  assertEquals(r.alterado.phone, { de: "(47) 3369-0000", para: "(47) 99999-1234" });
});

Deno.test("update_marina: nome exato desempata; ambíguo devolve opções; desativa; número sem rua é recusado", async () => {
  const db = bancoFalso({ marinas: MARINAS() });
  const exata = await tool("update_marina").execute({ marina: "itajai", active: false }, ctxCom(db)) as any;
  assert(exata.ok, JSON.stringify(exata)); // "Marina Itajaí" == "marina " + "itajai"
  assertEquals(db.chamadas.update[0][1], { active: false });
  assertEquals(db.tabelas.marinas.find((m: any) => m.id === "m2").active, false);

  const db2 = bancoFalso({ marinas: [...MARINAS(), { id: "m4", name: "Itajaí Marine Center", active: true }] });
  const amb = await tool("update_marina").execute({ marina: "Itajaí Sul Marina X", phone: "1" }, ctxCom(db2)) as any;
  assertStringIncludes(amb.error, "Nenhuma marina");
  const amb2 = await tool("update_marina").execute({ marina: "Itaj", phone: "47999991234" }, ctxCom(db2)) as any;
  assertEquals(amb2.opcoes.length, 3);
  assertEquals(db2.chamadas.update, []);

  const semRua = await tool("update_marina").execute({ marina_id: "m1", address_number: "12" }, ctxCom(db)) as any;
  assertStringIncludes(semRua.error, "rua");
});

// 07/10/2026: a tabela ganhou o bairro (migration 20261007161000_marina_bairro) — antes o campo
// "bairro" não existia nem na tool nem na tabela.
Deno.test("update_marina e create_marina: bairro vai para a coluna própria, fora da rua", async () => {
  const db = bancoFalso({ marinas: MARINAS() });
  const r = await tool("update_marina").execute({ marina: "Porto Belo", neighborhood: " Centro " }, ctxCom(db)) as any;
  assert(r.ok, JSON.stringify(r));
  assertEquals(db.chamadas.update[0][1], { neighborhood: "Centro" });
  const c = await tool("create_marina").execute({
    name: "Marina Penha", address_line_1: "Rua B", address_number: "7", neighborhood: "Armação",
  }, ctxCom(db)) as any;
  assert(c.ok, JSON.stringify(c));
  assertEquals(db.chamadas.insert[0][1], { name: "Marina Penha", address_line_1: "Rua B, 7", neighborhood: "Armação" });
});

Deno.test("update_marina: leitura que falha lança", async () => {
  const db = bancoFalso({ marinas: MARINAS() }, { marinas: "boom" });
  await assertRejects(() => tool("update_marina").execute({ marina: "Porto Belo", phone: "47999991234" }, ctxCom(db)));
  assertEquals(db.chamadas.update, []);
});

Deno.test("create_marina: campos da tela e nome repetido pergunta", async () => {
  const db = bancoFalso({ marinas: MARINAS() });
  const dup = await tool("create_marina").execute({ name: "marina porto belo" }, ctxCom(db)) as any;
  assertEquals(dup.ok, false);
  assertEquals(dup.ja_cadastrada[0].marina_id, "m1");
  const r = await tool("create_marina").execute({
    name: "Marina Bombinhas", phone: "4733690001", access_notes: "Portaria pede RG", billing_notes: "Boleto", address_line_1: "Rua A", address_complement: "Galpão 2",
  }, ctxCom(db)) as any;
  assert(r.ok);
  assertEquals(db.chamadas.insert[0][1], {
    name: "Marina Bombinhas", phone: "(47) 3369-0001", access_notes: "Portaria pede RG", billing_notes: "Boleto", address_line_1: "Rua A, Galpão 2",
  });
});

Deno.test("list_marinas: sem acento e com inativas a pedido", async () => {
  const db = bancoFalso({ marinas: MARINAS() });
  const r = await tool("list_marinas").execute({ query: "itajai" }, ctxCom(db)) as any;
  assertEquals(r.results.map((m: any) => m.id), ["m2"]);
  const r2 = await tool("list_marinas").execute({ query: "itajai", incluir_inativas: true }, ctxCom(db)) as any;
  assertEquals(r2.results.map((m: any) => m.id), ["m2", "m3"]);
});

// ── contatos da embarcação ────────────────────────────────────────────────────────────────────

const BASE_BARCOS = () => ({
  vessels: [{ id: "v1", name: "Netuno", client_id: "c3", active: true, marina_id: "m1", marinas: { name: "Marina Porto Belo", contact_name: "Rita", phone: "(47) 3369-0000" } }],
  vessel_contacts: [{ id: "vc1", vessel_id: "v1", full_name: "Seu Zé", role: "owner", phone: "(47) 98888-1111", email: null, notes: null, active: true }],
  service_orders: [],
});

Deno.test("add_vessel_contact: marinheiro Carlos na Netuno, função em português, telefone da tela", async () => {
  const db = bancoFalso(BASE_BARCOS());
  const r = await tool("add_vessel_contact").execute({ vessel_id: "v1", full_name: "Carlos", role: "marinheiro", phone: "47 99123-4567" }, ctxCom(db)) as any;
  assert(r.ok, JSON.stringify(r));
  assertEquals(db.chamadas.insert[0], ["vessel_contacts", { vessel_id: "v1", full_name: "Carlos", role: "sailor", phone: "(47) 99123-4567" }]);
  assertEquals(r.contato.funcao, "Marinheiro");
  assertEquals(r.embarcacao, "Netuno");
});

Deno.test("add_vessel_contact: não duplica (mesmo telefone), recusa função desconhecida e embarcação inexistente", async () => {
  const db = bancoFalso(BASE_BARCOS());
  const dup = await tool("add_vessel_contact").execute({ vessel_id: "v1", full_name: "José", phone: "5547988881111" }, ctxCom(db)) as any;
  assertEquals(dup.ok, false);
  assertEquals(dup.ja_e_contato.contact_id, "vc1");
  const funcao = await tool("add_vessel_contact").execute({ vessel_id: "v1", full_name: "Ana", role: "cozinheira" }, ctxCom(db)) as any;
  assertStringIncludes(funcao.error, "Função");
  const sem = await tool("add_vessel_contact").execute({ vessel_id: "v9", full_name: "Ana" }, ctxCom(db)) as any;
  assertStringIncludes(sem.error, "Embarcação não encontrada");
  assertEquals(db.chamadas.insert, []);
  const falha = bancoFalso(BASE_BARCOS(), { vessel_contacts: "boom" });
  await assertRejects(() => tool("add_vessel_contact").execute({ vessel_id: "v1", full_name: "Ana" }, ctxCom(falha)));
  assertEquals(falha.chamadas.insert, []);
});

Deno.test("update_vessel_contact: corrige telefone e remove (desativa, não apaga)", async () => {
  const db = bancoFalso(BASE_BARCOS());
  const r = await tool("update_vessel_contact").execute({ contact_id: "vc1", phone: "47977776666", role: "comandante" }, ctxCom(db)) as any;
  assert(r.ok);
  assertEquals(db.chamadas.update[0][1], { phone: "(47) 97777-6666", role: "captain" });
  const rem = await tool("update_vessel_contact").execute({ contact_id: "vc1", ativo: false }, ctxCom(db)) as any;
  assertEquals(rem.removido, true);
  assertEquals(db.chamadas.update[1][1], { active: false });
  const nada = await tool("update_vessel_contact").execute({ contact_id: "vc1" }, ctxCom(db)) as any;
  assertStringIncludes(nada.error, "Nada para atualizar");
});

Deno.test("get_vessel_history e get_client_360 trazem contatos e a marina; leitura dos contatos que falha lança", async () => {
  const db = bancoFalso({ ...BASE_BARCOS(), clients: CLIENTES(), receivables: [], whatsapp_messages: [], issued_fiscal_documents: [], ai_operator_memory_notes: [] });
  const h = await tool("get_vessel_history").execute({ vessel_id: "v1" }, ctxCom(db)) as any;
  assertEquals(h.contatos.map((c: any) => [c.contact_id, c.nome, c.funcao]), [["vc1", "Seu Zé", "Proprietário"]]);
  assertEquals(h.marina, { nome: "Marina Porto Belo", contato: "Rita", telefone: "(47) 3369-0000" });

  const c = await tool("get_client_360").execute({ client_id: "c3" }, ctxCom(db)) as any;
  assertEquals(c.ativos[0].contatos[0].nome, "Seu Zé");
  assertEquals(c.ativos[0].marina.nome, "Marina Porto Belo");

  const falha = bancoFalso({ ...BASE_BARCOS(), clients: CLIENTES() }, { vessel_contacts: "boom" });
  await assertRejects(() => tool("get_vessel_history").execute({ vessel_id: "v1" }, ctxCom(falha)));
  await assertRejects(() => tool("get_client_360").execute({ client_id: "c3" }, ctxCom(falha)));
});
