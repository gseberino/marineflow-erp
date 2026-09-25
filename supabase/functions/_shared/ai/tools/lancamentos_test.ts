import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { alvoDoLancamento, faixaDeValor, lancamentoTools, mensagemDoBanco, termoDeBusca } from "./lancamentos.ts";
import { camposDaCorrecao, financialTools } from "./financial.ts";
import { SEMPRE_NO_PERFIL } from "../agent.ts";

/* O assistente corrige, desfaz e cancela pelas MESMAS funções do banco que a tela usa.
   Estes testes fixam a parte que é só do assistente: traduzir o pedido em argumentos sem
   apagar nada sem querer, e nunca mexer sem dizer qual lançamento. */

Deno.test("alvoDoLancamento: exige exatamente um lançamento", () => {
  assertEquals(alvoDoLancamento({ payable_id: "a" }), { tipo: "payable", id: "a" });
  assertEquals(alvoDoLancamento({ receivable_id: " b " }), { tipo: "receivable", id: "b" });
  assertEquals("error" in alvoDoLancamento({}), true);
  assertEquals("error" in alvoDoLancamento({ payable_id: "a", receivable_id: "b" }), true);
  assertEquals("error" in alvoDoLancamento({ payable_id: "  " }), true);
});

Deno.test("camposDaCorrecao: vazio não apaga; limpar apaga só o que foi pedido", () => {
  const perm = ["expense_category", "linked_service_order_id", "description", "amount", "notes"];
  // Campo vazio vindo do modelo é "não mexer", nunca "apagar".
  assertEquals(camposDaCorrecao("payable", { expense_category: "Alimentação de campo", notes: "", description: null }, perm),
    { campos: { expense_category: "Alimentação de campo" } });
  // "tira a OS dessa despesa"
  assertEquals(camposDaCorrecao("payable", { limpar: ["os"] }, perm), { campos: { linked_service_order_id: null } });
  // recebível não tem fornecedor
  assertEquals("error" in camposDaCorrecao("receivable", { limpar: ["fornecedor"] }, ["notes"]), true);
  // pedir para mudar e limpar o mesmo campo é contraditório
  assertEquals("error" in camposDaCorrecao("payable", { expense_category: "X", limpar: ["categoria"] }, perm), true);
  assertEquals("error" in camposDaCorrecao("payable", {}, perm), true);
  // campo fora da lista não passa (status, paid_amount…)
  assertEquals(camposDaCorrecao("payable", { status: "paid", amount: 10 }, perm), { campos: { amount: 10 } });
});

Deno.test("busca: faixa de valor e termo seguro para o filtro", () => {
  assertEquals(faixaDeValor(50), [49.5, 50.5]);
  assertEquals(faixaDeValor(0.5), [0.49, 0.51]);
  // vírgula e parêntese quebrariam o `or` do PostgREST
  assertEquals(termoDeBusca("Coremma (Itajaí), filial"), "Coremma Itajaí filial");
  assertEquals(termoDeBusca("a"), null);
  assertEquals(termoDeBusca(undefined), null);
});

Deno.test("mensagemDoBanco: tira o código e deixa a frase para a pessoa", () => {
  assertEquals(mensagemDoBanco({ message: "P0001: O mês 09/2026 está fechado." }), "O mês 09/2026 está fechado.");
  assertEquals(mensagemDoBanco({ message: "Diga por que o lançamento está sendo cancelado." }), "Diga por que o lançamento está sendo cancelado.");
});

type Chamada = { nome: string; args: Record<string, unknown> };
function ctxFalso(chamadas: Chamada[], resposta: unknown = { ok: true, message: "feito" }) {
  return {
    sb: { rpc: (nome: string, args: Record<string, unknown>) => { chamadas.push({ nome, args }); return Promise.resolve({ data: resposta, error: null }); } },
    admin: {}, userId: "u-dono", userRole: "admin" as const, jwt: "", appOrigin: "", settings: {},
  };
}
const tool = (nome: string) => [...lancamentoTools, ...financialTools].find((t) => t.name === nome)!;

Deno.test("update_payable corrige pago pela função do banco, com quem pediu", async () => {
  const chamadas: Chamada[] = [];
  await tool("update_payable").execute(
    { payable_id: "p1", expense_category: "Alimentação de campo", linked_service_order_id: "os1", motivo: "era almoço" },
    ctxFalso(chamadas) as never,
  );
  assertEquals(chamadas, [{
    nome: "corrigir_lancamento",
    args: {
      p_tipo: "payable", p_id: "p1",
      p_campos: { linked_service_order_id: "os1", expense_category: "Alimentação de campo" },
      p_motivo: "era almoço", p_autor: "u-dono",
    },
  }]);
});

Deno.test("desfazer, cancelar e casar chamam a função certa; cancelar sem motivo não chama nada", async () => {
  const chamadas: Chamada[] = [];
  const ctx = ctxFalso(chamadas) as never;
  await tool("desfazer_aprovacao_de_lancamento").execute({ receivable_id: "r1" }, ctx);
  const semMotivo = await tool("cancelar_lancamento").execute({ payable_id: "p1", motivo: " " }, ctx) as { error?: string };
  await tool("cancelar_lancamento").execute({ payable_id: "p1", motivo: "despesa pessoal" }, ctx);
  await tool("casar_lancamento_com_extrato").execute({ payable_id: "p2", bank_transaction_id: "t1" }, ctx);
  assertEquals(typeof semMotivo.error, "string");
  assertEquals(chamadas.map((c) => c.nome), ["desfazer_aprovacao", "cancelar_lancamento", "conciliar_lancamento"]);
  assertEquals(chamadas[2].args, { p_tipo: "payable", p_id: "p2", p_transacao: "t1", p_autor: "u-dono" });
});

Deno.test("erro da função volta legível para o modelo", async () => {
  const ctx = {
    sb: { rpc: () => Promise.resolve({ data: null, error: { message: "P0001: O mês 08/2026 está fechado. Reabra-o em Financeiro › Fechamento para corrigir este lançamento." } }) },
    admin: {}, userId: "u", userRole: "admin" as const, jwt: "", appOrigin: "", settings: {},
  };
  const r = await tool("update_receivable").execute({ receivable_id: "r1", category: "Serviços" }, ctx as never) as { error: string };
  assertEquals(r.error.startsWith("O mês 08/2026 está fechado"), true);
});

Deno.test("técnico não corrige, não desfaz, não cancela", async () => {
  const chamadas: Chamada[] = [];
  const ctx = { ...ctxFalso(chamadas), userRole: "technician" as const };
  for (const nome of ["update_payable", "desfazer_aprovacao_de_lancamento", "cancelar_lancamento", "casar_lancamento_com_extrato", "buscar_lancamentos"]) {
    const r = await tool(nome).execute({ payable_id: "p1", motivo: "x x x", bank_transaction_id: "t", texto: "almoço" }, ctx as never) as { error?: string };
    assertEquals(typeof r.error, "string", nome);
  }
  assertEquals(chamadas.length, 0);
});

Deno.test("mexer em dinheiro sempre pede confirmação; as novas estão visíveis no perfil", () => {
  for (const nome of ["update_payable", "update_receivable", "desfazer_aprovacao_de_lancamento", "cancelar_lancamento", "casar_lancamento_com_extrato"]) {
    assertEquals(tool(nome).risk !== "low", true, nome);
  }
  assertEquals(tool("buscar_lancamentos").risk, "low");
  // cancelar é "high" e entra sempre; as de risco médio/baixo precisam estar na lista fixa.
  for (const nome of ["buscar_lancamentos", "desfazer_aprovacao_de_lancamento", "casar_lancamento_com_extrato", "get_whatsapp_conversation"]) {
    assertEquals(SEMPRE_NO_PERFIL.has(nome), true, nome);
  }
});
