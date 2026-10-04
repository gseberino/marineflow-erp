// montarSugestoes (03/10/2026): o cálculo saiu da banking-reconcile para ser usado também pela
// ferramenta do assistente. O que se protege: lê só pendentes (com filtro por id e limite), erro
// de leitura derruba em vez de virar "nada a conciliar", não carrega candidatos à toa, pontua a
// conta certa e tira transferência entre contas próprias da caça a candidatos.
import { assert, assertEquals, assertRejects } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { montarSugestoes } from "./sugestoes.ts";
import type { Candidate } from "./types.ts";

type Chamada = { tabela: string; metodo: string; args: unknown[] };

function bancoFalso(dados: Record<string, unknown>, erro: Record<string, unknown> = {}) {
  const chamadas: Chamada[] = [];
  return {
    chamadas,
    admin: {
      from(tabela: string) {
        const b: Record<string, unknown> = {};
        for (const m of ["select", "eq", "order", "limit", "in", "not"]) {
          b[m] = (...args: unknown[]) => {
            chamadas.push({ tabela, metodo: m, args });
            return b;
          };
        }
        const resposta = () => ({ data: dados[tabela] ?? null, error: erro[tabela] ?? null });
        b.maybeSingle = () => Promise.resolve(resposta());
        b.then = (ok: (v: unknown) => unknown) => Promise.resolve(resposta()).then(ok);
        return b;
      },
    } as never,
  };
}

const pix = {
  id: "tx-1", transaction_date: "2026-10-02", description: "PIX RECEBIDO MARCELO SOUZA", amount: 1500,
  transaction_type: "credit", counterparty_name: "MARCELO SOUZA", counterparty_document: null, bank_connection_id: null,
};
const transferencia = {
  id: "tx-2", transaction_date: "2026-10-02", description: "TED HBR MARINE LTDA", amount: 800,
  transaction_type: "credit", counterparty_name: "HBR MARINE LTDA", counterparty_document: null, bank_connection_id: null,
};
const contaDoMarcelo: Candidate = {
  kind: "receivable", id: "rec-1", label: "Sinal OS-00045", amount: 1500, direction: "credit",
  dueDate: "2026-10-01", clientId: "c1", clientName: "Marcelo Souza", serviceOrderId: "os-45",
};

Deno.test("sem pendentes: devolve vazio e nem carrega candidatos", async () => {
  const { admin } = bancoFalso({ bank_transactions: [] });
  let carregou = false;
  const r = await montarSugestoes(admin, {}, { carregarCandidatos: () => { carregou = true; return Promise.resolve([]); } });
  assertEquals(r, { porTransacao: [], candidatosAvaliados: 0, transferenciasInternas: 0 });
  assertEquals(carregou, false);
});

Deno.test("lê só não conciliadas, limite 200 por padrão, e filtra pelo id quando pedido", async () => {
  const { admin, chamadas } = bancoFalso({ bank_transactions: [] });
  await montarSugestoes(admin, { transactionId: "tx-9" }, { carregarCandidatos: () => Promise.resolve([]) });
  const doExtrato = chamadas.filter((c) => c.tabela === "bank_transactions");
  assert(doExtrato.some((c) => c.metodo === "eq" && c.args[0] === "reconciled" && c.args[1] === false));
  assert(doExtrato.some((c) => c.metodo === "limit" && c.args[0] === 200));
  assert(doExtrato.some((c) => c.metodo === "eq" && c.args[0] === "id" && c.args[1] === "tx-9"));
});

Deno.test("erro ao ler o extrato derruba (nunca vira 'nada a conciliar')", async () => {
  const { admin } = bancoFalso({}, { bank_transactions: { message: "falhou" } });
  await assertRejects(() => montarSugestoes(admin, {}, { carregarCandidatos: () => Promise.resolve([]) }));
});

Deno.test("pontua a conta certa e tira a transferência entre contas próprias da caça", async () => {
  const { admin } = bancoFalso({
    bank_transactions: [pix, transferencia],
    app_settings: { value: "HBR Marine Ltda" },
    reconciliation_memory: [],
  });
  const r = await montarSugestoes(admin, {}, { carregarCandidatos: () => Promise.resolve([contaDoMarcelo]) });
  assertEquals(r.candidatosAvaliados, 1);
  const doPix = r.porTransacao.find((p) => p.transaction.id === "tx-1")!;
  assertEquals(doPix.internalTransfer, false);
  assertEquals(doPix.suggestions[0]?.candidate.id, "rec-1");
  const daTransferencia = r.porTransacao.find((p) => p.transaction.id === "tx-2")!;
  assertEquals(daTransferencia.internalTransfer, true);
  assertEquals(daTransferencia.suggestions, []);
});
