// O cartão de confirmação (vai ao WhatsApp do dono) troca o id pelo texto do registro — a linha do extrato, o título
// da fila. Esse texto pode trazer o CPF que o banco escreve no nome ("12345678901-MARIA"): sai mascarado (leva 8, LGPD).
// O telefone dito pelo usuário continua inteiro: é o que ele confere antes do sim.
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { buildPendingSummary } from "./agent.ts";

const LINHA = "44444444-4444-4444-8444-444444444444";

// deno-lint-ignore no-explicit-any
const admin: any = {
  from(tabela: string) {
    const q = {
      select: () => q,
      eq: () => q,
      maybeSingle: () => Promise.resolve({
        data: tabela === "bank_transactions"
          ? { transaction_date: "2026-10-23", counterparty_name: "12345678901-MARIA SILVA", description: "PIX", amount: 1500 }
          : null,
        error: null,
      }),
    };
    return q;
  },
};

Deno.test("cartão genérico: a linha do extrato sai com o CPF do nome mascarado; o telefone dito, inteiro", async () => {
  const r = await buildPendingSummary(admin, "ferramenta_de_teste", { bank_transaction_id: LINHA, telefone: "47999990000" });
  assert(r.includes("***.456.789-**-MARIA SILVA"), r);
  assertEquals(/12345678901/.test(r), false, r);
  assert(r.includes("47999990000"), r);
});
