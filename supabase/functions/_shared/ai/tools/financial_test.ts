// O fechamento do período do assistente conta "entrou" e "saiu" pelo extrato, com a MESMA regra
// da Central de relatórios e do painel inicial (revisão de 27/09/2026).
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { financialTools, periodoDoFechamento } from "./financial.ts";
import { hojeEmBrasilia, somarDias } from "../../banking/fluxo-de-caixa.ts";

Deno.test("fechamento: os recortes são datas de Brasília, sem fuso no caminho", () => {
  assertEquals(periodoDoFechamento("hoje", "2026-09-26"), { de: "2026-09-26", ate: "2026-09-26" });
  assertEquals(periodoDoFechamento("ontem", "2026-09-01"), { de: "2026-08-31", ate: "2026-08-31" });
  assertEquals(periodoDoFechamento("semana", "2026-09-03"), { de: "2026-08-28", ate: "2026-09-03" });
  assertEquals(periodoDoFechamento("mes", "2026-09-26"), { de: "2026-09-01", ate: "2026-09-26" });
  assertEquals(periodoDoFechamento("qualquer", "2026-09-26"), { de: "2026-09-26", ate: "2026-09-26" });
});

/** Um cliente do banco de mentira: guarda os filtros de cada consulta e devolve as linhas da tabela. */
function sbFalso(tabelas: Record<string, unknown[]>) {
  const pedidos: Array<{ tabela: string; filtros: unknown[][] }> = [];
  return {
    pedidos,
    from(tabela: string) {
      const pedido = { tabela, filtros: [] as unknown[][] };
      pedidos.push(pedido);
      // deno-lint-ignore no-explicit-any
      const q: any = {};
      for (const m of ["select", "in", "gte", "lte", "lt", "gt", "eq", "order", "range"]) {
        q[m] = (...a: unknown[]) => { pedido.filtros.push([m, ...a]); return q; };
      }
      // deno-lint-ignore no-explicit-any
      q.then = (ok: any, erro: any) => Promise.resolve({ data: tabelas[tabela] ?? [], error: null, count: 0 }).then(ok, erro);
      return q;
    },
  };
}

Deno.test("fechamento do mês: entrou e saiu pelo extrato — transferência pareada e duplicata fora", async () => {
  const hoje = hojeEmBrasilia();
  const dia1 = `${hoje.slice(0, 7)}-01`;
  const linha = (id: string, amount: number, transaction_type: string, extra: Record<string, unknown> = {}) => ({
    id, transaction_date: dia1, amount, transaction_type, source_type: "bank", provider: "pluggy",
    bank_connection_id: "c6", dismissed_kind: null, tx_status: "POSTED", import_batch_id: null, ...extra,
  });
  const sb = sbFalso({
    bank_transactions: [
      linha("a", 1000, "credit"),
      linha("b", 300, "debit"),
      linha("d", 50, "credit", { dismissed_kind: "duplicata" }),
      linha("t1", 2900, "debit", { dismissed_kind: "transferencia" }),
      linha("t2", 2900, "credit", { dismissed_kind: "transferencia", bank_connection_id: "nubank" }),
      // A marca "transferência" sem a outra perna é dinheiro de verdade (a fatura do cartão).
      linha("f", 400, "debit", { dismissed_kind: "transferencia" }),
    ],
  });
  const t = financialTools.find((x) => x.name === "get_period_summary")!;
  const ctx = { sb, admin: {}, userId: "u", userRole: "admin" as const, jwt: "", appOrigin: "", settings: {} };
  // deno-lint-ignore no-explicit-any
  const r = await t.execute({ period: "mes" }, ctx as never) as any;

  assertEquals([r.entrou, r.saiu, r.saldo], [1000, 700, 300]);
  assertEquals(r.a_parte_sem_somar.transferencias_entre_contas_proprias, { entrou: 2900, saiu: 2900 });
  assertEquals(r.fora_da_conta["linha repetida da importação"], { quantidade: 1, valor: 50 });
  assertEquals([r.de, r.ate], [dia1, hoje]);

  // A leitura é do extrato de conta e Caixa, com a margem de dias para parear, e em páginas.
  const leitura = sb.pedidos.find((p) => p.tabela === "bank_transactions")!;
  const filtro = (m: string) => leitura.filtros.find((f) => f[0] === m);
  assertEquals(filtro("in"), ["in", "source_type", ["bank", "cash"]]);
  assertEquals(filtro("gte"), ["gte", "transaction_date", somarDias(dia1, -3)]);
  assertEquals(filtro("lte"), ["lte", "transaction_date", somarDias(hoje, 3)]);
  assertEquals(filtro("range"), ["range", 0, 999]);
  // O painel de pagamentos não é mais a fonte do "entrou".
  assertEquals(sb.pedidos.some((p) => p.tabela === "payments"), false);
});

Deno.test("fechamento: erro ao ler o extrato vira mensagem, não um zero", async () => {
  const sb = {
    from() {
      // deno-lint-ignore no-explicit-any
      const q: any = {};
      for (const m of ["select", "in", "gte", "lte", "lt", "gt", "eq", "order", "range"]) q[m] = () => q;
      // deno-lint-ignore no-explicit-any
      q.then = (ok: any, erro: any) => Promise.resolve({ data: null, error: { message: "permission denied" } }).then(ok, erro);
      return q;
    },
  };
  const t = financialTools.find((x) => x.name === "get_period_summary")!;
  const ctx = { sb, admin: {}, userId: "u", userRole: "admin" as const, jwt: "", appOrigin: "", settings: {} };
  const r = await t.execute({ period: "hoje" }, ctx as never) as { error?: string };
  assertEquals(r.error, "Não consegui ler o extrato: permission denied");
});
