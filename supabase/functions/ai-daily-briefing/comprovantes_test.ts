// O resumo das 07:30 com os comprovantes (F3, spec-f3.md 5.3): SÓ REMOÇÃO. O débito sem loja que um
// CMP ligou (ou que a pergunta do extrato espera) sai da pergunta do dia; a anotação de um CMP vivo
// sai de "não aplicadas"; o número de anotados esperando é o de antes; erro na R2 = o bloco de antes.
// Rodar com:
//   deno test --allow-all --no-check --node-modules-dir=none supabase/functions/ai-daily-briefing/comprovantes_test.ts
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { canceladasSemComprovante, debitosSemComprovante, linhasDosComprovantes } from "./comprovantes.ts";
import { linhasDoExtratoNoResumo } from "./extrato.ts";

// deno-lint-ignore no-explicit-any
type Qualquer = any;

const TX_DO_CMP = "55555555-0000-4000-8000-000000000001";
const TX_CANDIDATA = "55555555-0000-4000-8000-000000000002";
const TX_LIVRE = "55555555-0000-4000-8000-000000000003";
const TX_ANOTADA = "55555555-0000-4000-8000-000000000004";
const ANOTACAO_DO_CMP = "66666666-0000-4000-8000-000000000001";
const ANOTACAO_SOLTA = "66666666-0000-4000-8000-000000000002";

function adminFalso(r2: { data?: unknown; error?: unknown } | Error) {
  const chamadas: Array<{ nome: string; args: Qualquer }> = [];
  return {
    chamadas,
    admin: {
      rpc(nome: string, args: Qualquer) {
        chamadas.push({ nome, args });
        if (r2 instanceof Error) return Promise.reject(r2);
        return Promise.resolve({ data: r2.data ?? null, error: r2.error ?? null });
      },
    },
  };
}

const R2 = {
  linhas: [
    { bank_transaction_id: TX_DO_CMP, codigo: "CMP-00124", papel: "ligada", conta_aberta_id: null },
    { bank_transaction_id: TX_CANDIDATA, codigo: "CMP-00125", papel: "candidata", conta_aberta_id: null },
  ],
  anotacoes: [ANOTACAO_DO_CMP],
};

const debito = (tx: string, anotacao: unknown = null) => ({
  bank_transaction_id: tx, suggested_amount: 50.98, suggested_date: "2026-10-08", evidencia: anotacao ? { anotacao } : {},
  bank_transactions: { description: "DEBITO DE CARTAO", counterparty_name: null, counterparty_document: null },
});

Deno.test("R2 sem filtro de linhas (a anotação cancelada não tem linha); erro = vazio, nunca lança", async () => {
  const b = adminFalso({ data: R2 });
  const r = await linhasDosComprovantes(b.admin);
  assertEquals(b.chamadas, [{ nome: "comprovantes_linhas_da_conciliacao", args: { p_transacoes: null } }]);
  assertEquals([...r.linhas], [TX_DO_CMP, TX_CANDIDATA]);
  assertEquals([...r.anotacoes], [ANOTACAO_DO_CMP]);
  for (const ruim of [{ error: { code: "42883" } }, new Error("rede")]) {
    const original = console.warn;
    console.warn = () => {};
    try {
      const v = await linhasDosComprovantes(adminFalso(ruim).admin);
      assertEquals([v.linhas.size, v.anotacoes.size], [0, 0]);
    } finally {
      console.warn = original;
    }
  }
});

Deno.test("débito sem loja: a linha do CMP e a candidata saem da pergunta; a anotada continua contando como antes", () => {
  const doCmp = { linhas: new Set([TX_DO_CMP, TX_CANDIDATA]), anotacoes: new Set([ANOTACAO_DO_CMP]) };
  const semLoja = [debito(TX_DO_CMP), debito(TX_CANDIDATA), debito(TX_LIVRE), debito(TX_ANOTADA, { id: ANOTACAO_SOLTA })];
  const { debitos, anotadosEsperando } = debitosSemComprovante(semLoja, doCmp);
  assertEquals(debitos.map((d) => d.bank_transaction_id), [TX_LIVRE]);
  assertEquals(anotadosEsperando, 1);
  // sem a R2 (erro): o bloco de antes da F3
  const antes = debitosSemComprovante(semLoja, { linhas: new Set(), anotacoes: new Set() });
  assertEquals(antes.debitos.map((d) => d.bank_transaction_id), [TX_DO_CMP, TX_CANDIDATA, TX_LIVRE]);
  assertEquals(antes.anotadosEsperando, 1);
  // o texto do resumo só perde a linha (nada novo entra)
  const fmt = (v: number) => `R$ ${v.toFixed(2)}`;
  const com = linhasDoExtratoNoResumo([], debitos, fmt, { anoAtual: 2026, anotadosEsperando });
  const sem = linhasDoExtratoNoResumo([], antes.debitos, fmt, { anoAtual: 2026, anotadosEsperando: antes.anotadosEsperando });
  assertEquals(com.linhas.length <= sem.linhas.length, true);
  assertEquals(JSON.stringify(com).includes("CMP"), false, "o resumo não ganha nada sobre comprovante");
});

Deno.test("não aplicadas: a anotação de um CMP vivo sai; as outras ficam", () => {
  const doCmp = { linhas: new Set<string>(), anotacoes: new Set([ANOTACAO_DO_CMP]) };
  const canceladas = [{ id: ANOTACAO_DO_CMP, valor: 50.98 }, { id: ANOTACAO_SOLTA, valor: 800 }];
  assertEquals(canceladasSemComprovante(canceladas, doCmp).map((a) => a.id), [ANOTACAO_SOLTA]);
  assertEquals(canceladasSemComprovante(canceladas, { linhas: new Set(), anotacoes: new Set() }).length, 2);
});
