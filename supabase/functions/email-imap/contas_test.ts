// O que vence, fatia 1: o boleto do e-mail vira conta a pagar. O que se protege: a RPC é chamada com o id do e-mail; erro
// nunca derruba a leitura (vai para app_error_logs); função ausente é silêncio; boleto que o banco não conseguiu lançar
// (barradas) não fica calado.
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { registrarContas, RPC_CONTAS, temBoleto } from "./contas.ts";

type Resposta = { data?: unknown; error?: { code?: string; message: string } | null };

function bancoFalso(rpc: (nome: string, args: Record<string, unknown>) => Resposta | Promise<Resposta>) {
  const rpcs: [string, Record<string, unknown>][] = [];
  return {
    rpcs,
    rpc: async (nome: string, args: Record<string, unknown>) => {
      rpcs.push([nome, args]);
      if (nome === "log_app_error") return { data: null, error: null };
      return await rpc(nome, args);
    },
  };
}

const boleto = { linha: "1".repeat(47), valor: 10, vencimento: "2026-12-01", origem: "pdf" as const };

Deno.test("registrarContas: chama a RPC com o id do e-mail e devolve o que ela disse", async () => {
  const r = { criadas: 1, ligadas: 0, ja_existiam: 0, ignoradas: 0, parecem_pagas: 0, antigas: 0, barradas: 0, erros: [] };
  const db = bancoFalso(() => ({ data: r, error: null }));
  assertEquals(await registrarContas(db, "e1"), r);
  assertEquals(db.rpcs, [[RPC_CONTAS, { p_email_message_id: "e1" }]]);
});

Deno.test("registrarContas: a função ausente (migration não aplicada) é silêncio — nada em app_error_logs", async () => {
  for (const code of ["PGRST202", "42883"]) {
    const db = bancoFalso(() => ({ data: null, error: { code, message: "não existe" } }));
    assertEquals(await registrarContas(db, "e1"), null);
    assertEquals(db.rpcs.map((x) => x[0]), [RPC_CONTAS]);
  }
});

Deno.test("registrarContas: erro do banco ou exceção NUNCA lança — vai para app_error_logs (email-imap, financeiro:contas-do-boleto)", async () => {
  const comErro = bancoFalso(() => ({ data: null, error: { code: "23514", message: "check" } }));
  assertEquals(await registrarContas(comErro, "e1"), null);
  const log = comErro.rpcs.find((x) => x[0] === "log_app_error")!;
  assertEquals([log[1].p_context, log[1].p_action, log[1].p_level], ["email-imap", "financeiro:contas-do-boleto", "error"]);
  assert(String(log[1].p_message).includes("e1"));

  const explode = bancoFalso(() => { throw new Error("rede caiu"); });
  assertEquals(await registrarContas(explode, "e2"), null);
  assert(explode.rpcs.some((x) => x[0] === "log_app_error"));
});

Deno.test("registrarContas: boleto que o banco não conseguiu lançar (barradas) vai para app_error_logs com o motivo, e o resultado volta", async () => {
  const r = { criadas: 0, barradas: 1, erros: ["P0001: O período 2026-11 está fechado"] };
  const db = bancoFalso(() => ({ data: r, error: null }));
  assertEquals(await registrarContas(db, "e3"), r);
  const log = db.rpcs.find((x) => x[0] === "log_app_error")!;
  assert(String(log[1].p_message).includes("período 2026-11 está fechado"));
  assert(String(log[1].p_message).includes("e3"));
});

Deno.test("registrarContas: chave desligada (pulado) não é erro", async () => {
  const db = bancoFalso(() => ({ data: { pulado: true }, error: null }));
  assertEquals(await registrarContas(db, "e1"), { pulado: true });
  assertEquals(db.rpcs.length, 1);
});

Deno.test("temBoleto: só chama a RPC quando o e-mail trouxe boleto", () => {
  assertEquals(temBoleto(null), false);
  assertEquals(temBoleto({}), false);
  assertEquals(temBoleto({ boletos: [] }), false);
  assertEquals(temBoleto({ boletos: [boleto] }), true);
});
