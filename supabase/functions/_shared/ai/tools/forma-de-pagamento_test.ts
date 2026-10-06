// Forma de pagamento (05/10/2026). Caso real: o sinal de R$ 800 em dinheiro da MP Motor Homes
// (ORÇ-00095) falhou DEPOIS do "sim <PIN>" com "violates check constraint
// payments_payment_method_check" — o modelo mandou "dinheiro" e o banco só aceita os códigos.
import { assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { formaDePagamento, validarForma } from "./forma-de-pagamento.ts";
import { financialTools } from "./financial.ts";
import { flowMacroTools } from "./flow-macros.ts";

Deno.test("o que o dono diz vira o código do banco", () => {
  const casos: Record<string, string> = {
    dinheiro: "cash", "Dinheiro": "cash", "em espécie": "cash", cash: "cash",
    pix: "pix", PIX: "pix",
    "cartão de crédito": "credit_card", crédito: "credit_card", credit_card: "credit_card",
    "cartão de débito": "debit_card", debito: "debit_card", "debit-card": "debit_card",
    transferência: "bank_transfer", TED: "bank_transfer", "depósito": "bank_transfer", boleto: "bank_transfer", bank_transfer: "bank_transfer",
    cheque: "check", check: "check",
  };
  for (const [dito, codigo] of Object.entries(casos)) assertEquals(formaDePagamento(dito), codigo, dito);
});

Deno.test("ambíguo ou desconhecido não vira nada — 'cartão' sozinho pede crédito ou débito", () => {
  for (const v of ["cartão", "", null, undefined, "permuta"]) assertEquals(formaDePagamento(v), null, String(v));
  assertStringIncludes(validarForma({ payment_method: "cartão" })!.error, "crédito ou débito");
  assertEquals(validarForma({ payment_method: "dinheiro" }), null);
});

const tool = (nome: string) => [...financialTools, ...flowMacroTools].find((t) => t.name === nome)!;

Deno.test("as três tools recusam a forma desconhecida ANTES da pendência e listam a forma no esquema", () => {
  for (const nome of ["register_payment", "register_deposit_and_convert", "approve_quote_full"]) {
    const t = tool(nome);
    assertStringIncludes(t.preValidar!({ payment_method: "permuta" }, {} as never)!.error, "não reconhecida", nome);
    assertEquals(t.preValidar!({ payment_method: "dinheiro" }, {} as never), null, nome);
    assertEquals((t.input_schema.properties as any).payment_method.enum, ["pix", "cash", "credit_card", "debit_card", "bank_transfer", "check"], nome);
  }
});

Deno.test("o caso da MP Motor Homes: 'dinheiro' chega ao banco como 'cash'", async () => {
  const chamadas: Record<string, unknown>[] = [];
  // A tool também lê o orçamento para lançar o saldo (06/10/2026): orçamento sem itens, saldo zero.
  const semLinhas = { select: () => semLinhas, eq: () => semLinhas, maybeSingle: () => Promise.resolve({ data: { service_order_number: "ORÇ-00095", grand_total: 800 }, error: null }) };
  const admin = { from: () => semLinhas, rpc: (_n: string, p: Record<string, unknown>) => { chamadas.push(p); return Promise.resolve({ data: { ok: true }, error: null }); } };
  const ctx = { sb: admin, admin, userId: "u1", userRole: "admin", jwt: "", appOrigin: "", settings: {} } as never;
  const r = await tool("register_deposit_and_convert").execute(
    { service_order_id: "92165492-234f-4f16-802e-0ecb13f752b6", amount: 800, payment_date: "2026-10-03", payment_method: "dinheiro" },
    ctx,
  ) as any;
  assertEquals(r.ok, true, JSON.stringify(r));
  assertEquals(chamadas[0].p_payment_method, "cash");
  // Pendência antiga, gravada com forma que não se reconhece: a execução recusa sem chamar o banco.
  const recusa = await tool("register_payment").execute({ amount: 10, payment_date: "2026-10-03", payment_method: "permuta" }, ctx) as any;
  assertStringIncludes(recusa.error, "não reconhecida");
  assertEquals(chamadas.length, 1);
});
