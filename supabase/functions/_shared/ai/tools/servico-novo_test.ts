// Cadastro de serviço (aprovação em lote, Fase 1, 29/10/2026): o cartão em português e a recusa do nome que já está no
// catálogo. Os payloads são os das 2 pendências reais de 28/10 (ai_operator_pending_actions) e o catálogo é o que ficou
// depois do "sim" das 18:57. Rodar com:
//   deno test --allow-all supabase/functions/_shared/ai/tools/servico-novo_test.ts
import { assert, assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { buildPendingSummary, resumoQueRecusa, tituloDaAcao } from "../agent.ts";
import { productTools, resumirServicoNovo, servicoComMesmoNome } from "./products.ts";

const PEDIDO_1854 = { billing_unit: "unit", default_price: 1135, name: "Realocação do banco de baterias" };
const PEDIDO_2019 = { billing_unit: "unit", default_price: 920, name: "Realocação e ligação dos controladores solares" };
const NO_CATALOGO_1857 = { id: "s-bat", name: "Realocação do banco de baterias", created_at: "2026-10-28T21:57:00Z" };

/** O catálogo de serviços ativos (só o que a consulta lê) e o que for inserido. */
function catalogo(ativos: Array<{ id: string; name: string; created_at: string | null }>) {
  const inseridos: Record<string, unknown>[] = [];
  const consulta = {
    select: () => consulta,
    eq: () => consulta,
    order: () => consulta,
    range: async (de: number, ate: number) => ({ data: ativos.slice(de, ate + 1), error: null }),
  };
  const admin = {
    from: (t: string) => {
      assertEquals(t, "services");
      return {
        ...consulta,
        insert: (linha: Record<string, unknown>) => {
          inseridos.push(linha);
          return { select: () => ({ single: async () => ({ data: { id: "novo", ...linha }, error: null }) }) };
        },
      };
    },
  };
  return { admin, inseridos };
}

const semEspacoFixo = (t: string) => t.replace(/ /g, " ");

Deno.test("dado real 28/10 18:54: o cartão sai 'Cadastrar serviço' / Nome / Cobrança: por unidade / Preço: R$ 1.135,00", async () => {
  const { admin } = catalogo([]);
  assertEquals(tituloDaAcao("create_service"), "Cadastrar serviço");
  assertEquals(semEspacoFixo(await resumirServicoNovo(admin, PEDIDO_1854)),
    "- Nome: Realocação do banco de baterias\n- Cobrança: por unidade\n- Preço: R$ 1.135,00");
  // pelo mesmo caminho da pendência (buildPendingSummary), e não é recusa
  const resumo = await buildPendingSummary(admin, "create_service", PEDIDO_1854);
  assertEquals(resumoQueRecusa("create_service", resumo), null);
});

Deno.test("dado real 28/10 20:19: um serviço diferente com o primeiro já no catálogo passa", async () => {
  const { admin } = catalogo([NO_CATALOGO_1857]);
  assertEquals(semEspacoFixo(await resumirServicoNovo(admin, PEDIDO_2019)),
    "- Nome: Realocação e ligação dos controladores solares\n- Cobrança: por unidade\n- Preço: R$ 920,00");
});

Deno.test("um terceiro 'Realocação do banco de baterias' é recusado: está no catálogo desde as 18:57 (sem diferenciar acento)", async () => {
  const { admin } = catalogo([NO_CATALOGO_1857]);
  for (const nome of ["Realocação do banco de baterias", "realocacao do banco  de baterias", " REALOCAÇÃO DO BANCO DE BATERIAS "]) {
    const resumo = await buildPendingSummary(admin, "create_service", { ...PEDIDO_1854, name: nome });
    assertEquals(resumo, '⚠️ O serviço "Realocação do banco de baterias" já está no catálogo desde 28/10/2026, 18:57. Nada foi registrado: use o que já existe.');
    const recusa = resumoQueRecusa("create_service", resumo);
    assert(recusa, "vira recusa, não pendência");
    assertEquals(recusa.nada_registrado, true);
  }
});

Deno.test("leitura do catálogo que falha também recusa (o genérico pediria um 'sim' sem saber se já existe)", async () => {
  const quebrado = { from: () => ({ select: () => ({ eq: () => ({ order: () => ({ range: async () => ({ data: null, error: { message: "timeout" } }) }) }) }) }) };
  const resumo = await buildPendingSummary(quebrado, "create_service", PEDIDO_1854);
  assertStringIncludes(resumo, "⚠️ Não consegui conferir o catálogo de serviços agora (timeout)");
  assert(resumoQueRecusa("create_service", resumo));
});

Deno.test("servicoComMesmoNome: lê em páginas de 1000 (o teto do PostgREST) até achar", async () => {
  const muitos = Array.from({ length: 1500 }, (_, i) => ({ id: `s${i}`, name: `Serviço ${i}`, created_at: null }));
  const { admin } = catalogo(muitos);
  assertEquals((await servicoComMesmoNome(admin, "serviço 1499"))?.id, "s1499");
  assertEquals(await servicoComMesmoNome(admin, "não existe"), null);
  assertEquals(await servicoComMesmoNome(admin, "  "), null);
});

const criar = productTools.find((t) => t.name === "create_service")!;
const ctx = (admin: unknown) => ({ sb: admin, admin, userId: "u1", userRole: "admin" as const, jwt: "", appOrigin: "", settings: {} });

Deno.test("execute: dois cartões do mesmo nome aprovados em seguida não viram dois serviços", async () => {
  const { admin, inseridos } = catalogo([NO_CATALOGO_1857]);
  const r = await criar.execute({ ...PEDIDO_1854 }, ctx(admin)) as Record<string, unknown>;
  assertEquals(r.ja_cadastrado, true);
  assertStringIncludes(String(r.error), "já está no catálogo");
  assertEquals(inseridos, []);
});

Deno.test("execute: só os 4 campos da ferramenta vão ao insert (uma chave a mais derrubava o cadastro)", async () => {
  const { admin, inseridos } = catalogo([]);
  const r = await criar.execute({ ...PEDIDO_2019, name: "  Realocação e ligação dos controladores solares ", _pedido: "x", outra: 1 }, ctx(admin)) as Record<string, unknown>;
  assertEquals(r.ok, true);
  assertEquals(inseridos, [{ name: "Realocação e ligação dos controladores solares", billing_unit: "unit", default_price: 920 }]);
});
