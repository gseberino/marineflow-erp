// Pareamento de transferências entre contas da própria empresa.
//
// Com mais de uma conta conectada, o mesmo dinheiro aparece duas vezes — sai de uma, entra
// na outra. Sem parear, vira despesa e receita fantasmas: infla faturamento e custo ao
// mesmo tempo. O resultado final até fecha, mas todos os números do meio ficam errados.
import { describe, it, expect } from "vitest";
import { findInternalTransfers } from "../../supabase/functions/_shared/banking/matching";

const tx = (o: Partial<any> & { id: string }) => ({
  transaction_date: "2026-07-20",
  description: "TRANSF ENVIADA PIX",
  amount: 5000,
  transaction_type: "debit" as const,
  bank_connection_id: "conta-c6",
  ...o,
});

describe("transferência entre contas próprias", () => {
  it("pareia saída de uma conta com entrada de outra no mesmo dia", () => {
    const pares = findInternalTransfers([
      tx({ id: "s1", transaction_type: "debit", bank_connection_id: "conta-c6" }),
      tx({ id: "e1", transaction_type: "credit", bank_connection_id: "conta-nubank" }),
    ]);
    expect(pares).toHaveLength(1);
    expect(pares[0].saida.id).toBe("s1");
    expect(pares[0].entrada.id).toBe("e1");
    expect(pares[0].defasagem).toBe(0);
  });

  it("aceita defasagem de um dia (TED entre bancos vira o dia)", () => {
    const pares = findInternalTransfers([
      tx({ id: "s1", transaction_date: "2026-07-20", transaction_type: "debit", bank_connection_id: "a" }),
      tx({ id: "e1", transaction_date: "2026-07-21", transaction_type: "credit", bank_connection_id: "b" }),
    ]);
    expect(pares).toHaveLength(1);
    expect(pares[0].defasagem).toBe(1);
  });

  it("não pareia movimento dentro da MESMA conta", () => {
    // Saída e entrada iguais na mesma conta não são transferência — são duas operações.
    const pares = findInternalTransfers([
      tx({ id: "s1", transaction_type: "debit", bank_connection_id: "conta-c6" }),
      tx({ id: "e1", transaction_type: "credit", bank_connection_id: "conta-c6" }),
    ]);
    expect(pares).toHaveLength(0);
  });

  it("não pareia valores diferentes", () => {
    const pares = findInternalTransfers([
      tx({ id: "s1", amount: 5000, transaction_type: "debit", bank_connection_id: "a" }),
      tx({ id: "e1", amount: 4990, transaction_type: "credit", bank_connection_id: "b" }),
    ]);
    expect(pares).toHaveLength(0);
  });

  it("não pareia quando a defasagem é grande demais", () => {
    const pares = findInternalTransfers([
      tx({ id: "s1", transaction_date: "2026-07-20", transaction_type: "debit", bank_connection_id: "a" }),
      tx({ id: "e1", transaction_date: "2026-07-28", transaction_type: "credit", bank_connection_id: "b" }),
    ]);
    expect(pares).toHaveLength(0);
  });

  it("usa cada perna uma única vez", () => {
    // Três transferências de mesmo valor no mesmo dia não podem gerar pares cruzados:
    // cada saída casa com uma entrada, e sobra a que não tem par.
    const pares = findInternalTransfers([
      tx({ id: "s1", transaction_type: "debit", bank_connection_id: "a" }),
      tx({ id: "s2", transaction_type: "debit", bank_connection_id: "a" }),
      tx({ id: "e1", transaction_type: "credit", bank_connection_id: "b" }),
    ]);
    expect(pares).toHaveLength(1);
    const usados = [pares[0].saida.id, pares[0].entrada.id];
    expect(new Set(usados).size).toBe(2);
  });

  it("ignora transações sem conta identificada", () => {
    // Extrato importado por arquivo não tem conexão; parear às cegas inventaria vínculo.
    const pares = findInternalTransfers([
      tx({ id: "s1", transaction_type: "debit", bank_connection_id: null }),
      tx({ id: "e1", transaction_type: "credit", bank_connection_id: "b" }),
    ]);
    expect(pares).toHaveLength(0);
  });

  it("resolve os maiores valores primeiro", () => {
    const pares = findInternalTransfers([
      tx({ id: "pequena", amount: 100, transaction_type: "debit", bank_connection_id: "a" }),
      tx({ id: "grande", amount: 90000, transaction_type: "debit", bank_connection_id: "a" }),
      tx({ id: "e-grande", amount: 90000, transaction_type: "credit", bank_connection_id: "b" }),
      tx({ id: "e-pequena", amount: 100, transaction_type: "credit", bank_connection_id: "b" }),
    ]);
    expect(pares).toHaveLength(2);
    expect(pares[0].saida.id).toBe("grande");
  });
});
