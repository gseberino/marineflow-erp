// O que vence, fatia 2: a baixa pelo boleto na varredura. O que se protege: a RPC recebe as reservadas da rodada (sem
// repetição); erro nunca derruba a varredura (vai para app_error_logs); função ausente é silêncio; conta que o banco
// não conseguiu baixar (barradas) não fica calada; a frase só aparece quando houve baixa.
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { baixarPeloBoleto, mensagemDaBaixa, RPC_BAIXA } from "./baixa-boleto.ts";

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

Deno.test("baixarPeloBoleto: passa as reservadas (sem repetir) e devolve o que foi baixado", async () => {
  const db = bancoFalso(() => ({
    data: { baixadas: 2, ambiguas: 1, barradas: 0, erros: [], itens: [{ transacao: "t1", conta: "c1" }, { transacao: "t2", conta: "c2" }] },
    error: null,
  }));
  assertEquals(await baixarPeloBoleto(db, new Set(["r1", "r2", "r1"])), { baixadas: 2, transacoes: ["t1", "t2"] });
  assertEquals(db.rpcs, [[RPC_BAIXA, { p_exceto: ["r1", "r2"] }]]);
});

Deno.test("baixarPeloBoleto: sem reservadas manda lista vazia", async () => {
  const db = bancoFalso(() => ({ data: { baixadas: 0, itens: [] }, error: null }));
  assertEquals(await baixarPeloBoleto(db), { baixadas: 0, transacoes: [] });
  assertEquals(db.rpcs, [[RPC_BAIXA, { p_exceto: [] }]]);
});

Deno.test("baixarPeloBoleto: a função ausente (migration não aplicada) é silêncio — nada em app_error_logs", async () => {
  for (const code of ["PGRST202", "42883"]) {
    const db = bancoFalso(() => ({ data: null, error: { code, message: "não existe" } }));
    assertEquals(await baixarPeloBoleto(db, []), { baixadas: 0, transacoes: [] });
    assertEquals(db.rpcs.map((x) => x[0]), [RPC_BAIXA]);
  }
});

Deno.test("baixarPeloBoleto: erro do banco ou exceção NUNCA lança — vai para app_error_logs (finance-review, baixa-pelo-boleto)", async () => {
  const comErro = bancoFalso(() => ({ data: null, error: { code: "42501", message: "sem permissão" } }));
  assertEquals(await baixarPeloBoleto(comErro, []), { baixadas: 0, transacoes: [] });
  const log = comErro.rpcs.find((x) => x[0] === "log_app_error")!;
  assertEquals([log[1].p_context, log[1].p_action, log[1].p_level], ["finance-review", "baixa-pelo-boleto", "error"]);
  assert(String(log[1].p_message).includes("42501"));

  const explode = bancoFalso(() => { throw new Error("rede caiu"); });
  assertEquals(await baixarPeloBoleto(explode, []), { baixadas: 0, transacoes: [] });
  assert(explode.rpcs.some((x) => x[0] === "log_app_error"));
});

Deno.test("baixarPeloBoleto: conta que o banco não conseguiu baixar (barradas) vai para app_error_logs com o motivo; as baixadas voltam", async () => {
  const db = bancoFalso(() => ({
    data: { baixadas: 1, barradas: 1, erros: ["P0001: O período 2026-10 está fechado"], itens: [{ transacao: "t1" }] },
    error: null,
  }));
  assertEquals(await baixarPeloBoleto(db, []), { baixadas: 1, transacoes: ["t1"] });
  const log = db.rpcs.find((x) => x[0] === "log_app_error")!;
  assert(String(log[1].p_message).includes("período 2026-10 está fechado"));
});

Deno.test("baixarPeloBoleto: chave desligada (pulado) não é erro e não baixa nada", async () => {
  const db = bancoFalso(() => ({ data: { pulado: true }, error: null }));
  assertEquals(await baixarPeloBoleto(db, []), { baixadas: 0, transacoes: [] });
  assertEquals(db.rpcs.length, 1);
});

Deno.test("mensagemDaBaixa: só fala quando houve baixa", () => {
  assertEquals(mensagemDaBaixa(0), "");
  assertEquals(mensagemDaBaixa(1), '1 conta baixada pelo boleto — veja em "Lançados sozinhos"');
  assertEquals(mensagemDaBaixa(3), '3 contas baixadas pelo boleto — veja em "Lançados sozinhos"');
});
