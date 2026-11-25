// O que vence, fatia 2: a baixa pelo boleto na varredura. O que se protege: a RPC recebe as reservadas da rodada (sem
// repetição); erro nunca derruba a varredura (vai para app_error_logs); função ausente é silêncio; conta que o banco
// não conseguiu baixar (barradas) não fica calada; a frase só aparece quando houve baixa.
// 24/11/2026: os mesmos casos para o lado do cliente (baixarRecebidoPeloBoleto), porque as duas baixas dividem o
// código — o que se protege a mais é que cada lado chama a SUA RPC e registra o erro com a SUA action.
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  baixarPeloBoleto, baixarRecebidoPeloBoleto, mensagemDaBaixa, mensagemDoRecebimento, RPC_BAIXA, RPC_BAIXA_RECEBIDO,
} from "./baixa-boleto.ts";

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

// ── O lado do cliente (24/11/2026): a conta a RECEBER de NF-e baixada pelo 'CREDITO DE BOLETO' ──────────────────────

Deno.test("baixarRecebidoPeloBoleto: chama a RPC do recebimento (não a das contas a pagar), passa as reservadas (sem repetir) e devolve o que foi baixado", async () => {
  assertEquals(RPC_BAIXA_RECEBIDO, "baixar_recebido_pelo_boleto");
  const db = bancoFalso(() => ({
    data: {
      baixadas: 2, ambiguas: 1, barradas: 0, erros: [],
      itens: [
        { transacao: "t1", conta: "c1", cliente: "Cliente A", descricao: "NF-e 2/25 (parcela 2/3)", valor: 5237.99, vencimento: "2026-10-16", pago_em: "2026-10-16" },
        { transacao: "t2", conta: "c2" },
      ],
    },
    error: null,
  }));
  assertEquals(await baixarRecebidoPeloBoleto(db, new Set(["r1", "r2", "r1"])), { baixadas: 2, transacoes: ["t1", "t2"] });
  assertEquals(db.rpcs, [[RPC_BAIXA_RECEBIDO, { p_exceto: ["r1", "r2"] }]]);
});

Deno.test("baixarRecebidoPeloBoleto: sem reservadas manda lista vazia — e nunca manda p_hoje nem p_simular (valem os padrões do banco)", async () => {
  const db = bancoFalso(() => ({ data: { baixadas: 0, itens: [] }, error: null }));
  assertEquals(await baixarRecebidoPeloBoleto(db), { baixadas: 0, transacoes: [] });
  assertEquals(db.rpcs, [[RPC_BAIXA_RECEBIDO, { p_exceto: [] }]]);
});

Deno.test("baixarRecebidoPeloBoleto: a função ausente (migration não aplicada) é silêncio — nada em app_error_logs", async () => {
  for (const code of ["PGRST202", "42883"]) {
    const db = bancoFalso(() => ({ data: null, error: { code, message: "não existe" } }));
    assertEquals(await baixarRecebidoPeloBoleto(db, []), { baixadas: 0, transacoes: [] });
    assertEquals(db.rpcs.map((x) => x[0]), [RPC_BAIXA_RECEBIDO]);
  }
});

Deno.test("baixarRecebidoPeloBoleto: erro do banco ou exceção NUNCA lança — vai para app_error_logs (finance-review, baixa-recebido-pelo-boleto)", async () => {
  const comErro = bancoFalso(() => ({ data: null, error: { code: "42501", message: "sem permissão" } }));
  assertEquals(await baixarRecebidoPeloBoleto(comErro, []), { baixadas: 0, transacoes: [] });
  const log = comErro.rpcs.find((x) => x[0] === "log_app_error")!;
  assertEquals([log[1].p_context, log[1].p_action, log[1].p_level], ["finance-review", "baixa-recebido-pelo-boleto", "error"]);
  assert(String(log[1].p_message).includes("42501"));
  assert(String(log[1].p_message).startsWith("baixa do recebimento pelo boleto não rodou"));

  const explode = bancoFalso(() => { throw new Error("rede caiu"); });
  assertEquals(await baixarRecebidoPeloBoleto(explode, []), { baixadas: 0, transacoes: [] });
  const logDaExcecao = explode.rpcs.find((x) => x[0] === "log_app_error")!;
  assertEquals(logDaExcecao[1].p_action, "baixa-recebido-pelo-boleto");
  assert(String(logDaExcecao[1].p_message).includes("rede caiu"));
});

Deno.test("baixarRecebidoPeloBoleto: recebimento que o banco não conseguiu baixar (barradas) vai para app_error_logs com o motivo; os baixados voltam", async () => {
  const db = bancoFalso(() => ({
    data: { baixadas: 1, barradas: 1, erros: ["P0001: O período 2026-10 está fechado"], itens: [{ transacao: "t1" }] },
    error: null,
  }));
  assertEquals(await baixarRecebidoPeloBoleto(db, []), { baixadas: 1, transacoes: ["t1"] });
  const log = db.rpcs.find((x) => x[0] === "log_app_error")!;
  assertEquals([log[1].p_context, log[1].p_action, log[1].p_level], ["finance-review", "baixa-recebido-pelo-boleto", "error"]);
  assertEquals(log[1].p_message, "1 recebimento(s) com boleto não foram baixados: P0001: O período 2026-10 está fechado");
});

Deno.test("baixarRecebidoPeloBoleto: chave desligada ou outra rodada em curso (pulado) não é erro e não baixa nada", async () => {
  const db = bancoFalso(() => ({ data: { pulado: true }, error: null }));
  assertEquals(await baixarRecebidoPeloBoleto(db, []), { baixadas: 0, transacoes: [] });
  assertEquals(db.rpcs.length, 1);
});

Deno.test("as duas baixas na mesma rodada: cada uma chama a sua RPC e o erro de uma não cala nem contamina a outra", async () => {
  const db = bancoFalso((nome) => nome === RPC_BAIXA
    ? { data: null, error: { code: "57014", message: "tempo esgotado" } }
    : { data: { baixadas: 1, barradas: 0, erros: [], itens: [{ transacao: "credito" }] }, error: null });
  const reservadas = ["r1"];
  assertEquals(await baixarPeloBoleto(db, reservadas), { baixadas: 0, transacoes: [] });
  assertEquals(await baixarRecebidoPeloBoleto(db, reservadas), { baixadas: 1, transacoes: ["credito"] });
  assertEquals(db.rpcs.filter((x) => x[0] !== "log_app_error"), [
    [RPC_BAIXA, { p_exceto: ["r1"] }],
    [RPC_BAIXA_RECEBIDO, { p_exceto: ["r1"] }],
  ]);
  assertEquals(db.rpcs.filter((x) => x[0] === "log_app_error").map((x) => x[1].p_action), ["baixa-pelo-boleto"]);
});

Deno.test("as frases de erro das contas a pagar continuam as de antes (24/11/2026: o código passou a ser dividido)", async () => {
  const barrada = bancoFalso(() => ({ data: { baixadas: 0, barradas: 2, erros: ["a", "b"], itens: [] }, error: null }));
  await baixarPeloBoleto(barrada, []);
  assertEquals(barrada.rpcs.find((x) => x[0] === "log_app_error")![1].p_message, "2 conta(s) com boleto não foram baixadas: a | b");

  const comErro = bancoFalso(() => ({ data: null, error: { code: "42501", message: "sem permissão" } }));
  await baixarPeloBoleto(comErro, []);
  assertEquals(comErro.rpcs.find((x) => x[0] === "log_app_error")![1].p_message, "baixa pelo boleto não rodou: 42501: sem permissão");
});

Deno.test("mensagemDoRecebimento: só fala quando houve baixa, e a palavra é 'recebimento' (conta baixada = conta a pagar)", () => {
  assertEquals(mensagemDoRecebimento(0), "");
  assertEquals(mensagemDoRecebimento(1), '1 recebimento baixado pelo boleto — veja em "Lançados sozinhos"');
  assertEquals(mensagemDoRecebimento(3), '3 recebimentos baixados pelo boleto — veja em "Lançados sozinhos"');
});
