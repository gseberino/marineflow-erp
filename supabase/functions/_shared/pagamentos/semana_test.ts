// Pagamentos da semana (24/11/2026): o texto da manhã, o calendário (bloco na 1ª manhã útil, vencidas nos outros dias) e
// os leitores — o da manhã nunca lança; o da ferramenta só se cala quando a função ainda não existe.
import { assertEquals, assertRejects, assertThrows } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  blocoDaSemana, comPagamentos, filaDePagamentos, lerPagamentosDaManha, linhaDasVencidas, type PagamentosDaSemana,
  pagamentosDaManha, pagamentosDaResposta, resumirPrioridade,
} from "./semana.ts";

/** A resposta da RPC como o banco devolve (medida de 23/11/2026, com a Unifique ainda sem grupo). */
const resposta = (extra: Record<string, unknown> = {}) => ({
  hoje: "2026-11-30",
  ate: "2026-12-06",
  saldo_no_banco: 1476.13,
  saldo_em: "2026-11-30T09:01:00.105545+00:00",
  contas: [
    { id: "c1", nome: "KAMELL COMERCIO GLOBAL LTDA", valor: 1433.6, vencimento: "2026-11-05", vencida: true, grupo: 3, a_definir: false, categoria: "Compras de mercadorias", boleto_linha: "23790000000000000000000000000000000000000000001" },
    { id: "c2", nome: "Unifique", valor: 117.18, vencimento: "2026-11-20", vencida: true, grupo: 3, a_definir: true, categoria: null, boleto_linha: "00190000000000000000000000000000000000000000002" },
    { id: "c3", nome: "TSD LOGISTICA E DISTRIBUIDORA LTDA - CURITIBA", valor: 784.82, vencimento: "2026-12-01", vencida: false, grupo: 3, a_definir: false, categoria: "Peças e materiais", boleto_linha: null },
  ],
  soma: 2335.6,
  vencido: { n: 2, total: 1550.78 },
  reembolsos: { n: 4, total: 1300 },
  ...extra,
});

const lida = (extra: Record<string, unknown> = {}): PagamentosDaSemana => pagamentosDaResposta(resposta(extra));

Deno.test("pagamentosDaResposta: lê a forma do banco; forma errada lança", () => {
  const p = lida();
  assertEquals([p.hoje, p.ate, p.saldoNoBanco, p.saldoEm, p.soma], ["2026-11-30", "2026-12-06", 1476.13, "2026-11-30", 2335.6]);
  assertEquals(p.contas.map((c) => [c.id, c.grupo, c.aDefinir, c.vencida, !!c.boletoLinha]), [
    ["c1", 3, false, true, true], ["c2", 3, true, true, true], ["c3", 3, false, false, false],
  ]);
  assertEquals(p.reembolsos, { n: 4, total: 1300 });
  assertThrows(() => pagamentosDaResposta(null));
  assertThrows(() => pagamentosDaResposta({ hoje: "2026-11-30", ate: "2026-12-06" }));
  assertThrows(() => pagamentosDaResposta(resposta({ contas: [{ id: "x", nome: "X", valor: 1, vencimento: "2026-12-01", grupo: 9 }] })));
  assertThrows(() => pagamentosDaResposta(resposta({ contas: [{ nome: "sem id", valor: 1, vencimento: "2026-12-01", grupo: 1 }] })));
});

Deno.test("saldo informado às 22h de Brasília é do dia de lá, não do UTC", () => {
  assertEquals(lida({ saldo_em: "2026-11-30T01:30:00+00:00" }).saldoEm, "2026-11-29");
});

Deno.test("blocoDaSemana: a fila na ordem recebida, a soma contra o saldo, o reembolso à parte e a pergunta do grupo", () => {
  assertEquals(blocoDaSemana(lida()), [
    "*Pagamentos da semana* — no banco: R$ 1.476,13",
    "Na ordem em que eu pagaria:",
    "• KAMELL COMERCIO GLOBAL LTDA — R$ 1.433,60 (venceu 05/11)",
    "• Unifique — R$ 117,18 (venceu 20/11)",
    "• TSD LOGISTICA E DISTRIBUIDO… — R$ 784,82 (vence 01/12)",
    "Soma R$ 2.335,60: faltam R$ 859,47 no banco.",
    "Fora da fila: a empresa te deve R$ 1.300,00 (4 reembolsos).",
    "Ainda não sei a prioridade de Unifique: é imposto ou pessoa, serviço que corta, ou fornecedor comum?",
    "Pagou alguma? Me diga qual (*paguei KAMELL*). Para o código do boleto: *boleto KAMELL*.",
  ].join("\n"));
});

Deno.test("blocoDaSemana: saldo que cobre, saldo velho com a data, sem saldo, vence hoje e 'e mais N'", () => {
  const cobre = blocoDaSemana(lida({ saldo_no_banco: 5000, reembolsos: { n: 0, total: 0 } }))!;
  assertEquals(cobre.includes("Soma R$ 2.335,60: o saldo cobre."), true);
  assertEquals(cobre.includes("Fora da fila"), false);

  const velho = blocoDaSemana(lida({ saldo_em: "2026-11-26T15:00:00+00:00" }))!;
  assertEquals(velho.split("\n")[0], "*Pagamentos da semana* — no banco: R$ 1.476,13 (saldo de 26/11)");

  const semSaldo = blocoDaSemana(lida({ saldo_no_banco: null, saldo_em: null }))!;
  assertEquals(semSaldo.split("\n")[0], "*Pagamentos da semana*");
  assertEquals(semSaldo.includes("Soma R$ 2.335,60."), true);

  const hoje = blocoDaSemana(lida({ contas: [{ id: "h", nome: "Celesc", valor: 10, vencimento: "2026-11-30", vencida: false, grupo: 2, a_definir: false }], soma: 10 }))!;
  assertEquals(hoje.includes("• Celesc — R$ 10,00 (vence hoje)"), true);
  assertEquals(hoje.includes("Ainda não sei"), false);
  assertEquals(hoje.endsWith("Pagou alguma? Me diga qual (*paguei Celesc*)."), true);

  const muitas = Array.from({ length: 9 }, (_, i) => ({ id: `m${i}`, nome: `Fornecedor ${i}`, valor: 100, vencimento: "2026-12-02", vencida: false, grupo: 4, a_definir: false }));
  const longo = blocoDaSemana(lida({ contas: muitas, soma: 900 }))!;
  assertEquals(longo.split("\n").filter((l) => l.startsWith("• ")).length, 7);
  assertEquals(longo.includes("• e mais 3 (R$ 300,00)"), true);
});

Deno.test("blocoDaSemana e linhaDasVencidas: sem conta na fila não há bloco (nem só pelo reembolso)", () => {
  const vazio = lida({ contas: [], soma: 0, vencido: { n: 0, total: 0 } });
  assertEquals(blocoDaSemana(vazio), null);
  assertEquals(linhaDasVencidas(vazio), null);
});

Deno.test("linhaDasVencidas: uma conta por extenso; várias com o total e o primeiro da fila; a vencer não conta", () => {
  assertEquals(linhaDasVencidas(lida()),
    "A pagar vencido: R$ 1.550,78 (2 contas). Primeiro da fila: KAMELL COMERCIO GLOBAL LTDA, R$ 1.433,60. Peça *pagamentos da semana* para ver tudo.");
  const uma = lida({ contas: resposta().contas.slice(1) });
  assertEquals(linhaDasVencidas(uma), "A pagar vencido: Unifique, R$ 117,18 (venceu 20/11).");
  assertEquals(linhaDasVencidas(lida({ contas: resposta().contas.slice(2) })), null);
});

Deno.test("pagamentosDaManha: bloco na 1ª manhã útil da semana, vencidas nos outros dias úteis, nada no sábado, domingo e feriado", () => {
  const p = lida();
  assertEquals(pagamentosDaManha(p, "2026-11-30")!.startsWith("*Pagamentos da semana*"), true); // segunda
  assertEquals(pagamentosDaManha(p, "2026-12-01")!.startsWith("A pagar vencido:"), true); // terça
  assertEquals(pagamentosDaManha(p, "2026-12-05"), null); // sábado
  assertEquals(pagamentosDaManha(p, "2026-12-06"), null); // domingo
  // segunda feriado (07/09/2026): o bloco vai na terça, e a segunda fica sem nada
  assertEquals(pagamentosDaManha(p, "2026-09-07"), null);
  assertEquals(pagamentosDaManha(p, "2026-09-08")!.startsWith("*Pagamentos da semana*"), true);
  assertEquals(pagamentosDaManha(null, "2026-11-30"), null);
});

Deno.test("comPagamentos: sem bloco o texto é o de antes, byte a byte", () => {
  assertEquals(comPagamentos("Bom dia!", null), "Bom dia!");
  assertEquals(comPagamentos("Bom dia!", "A pagar vencido: X."), "Bom dia!\n\nA pagar vencido: X.");
});

// ─── leitores ──────────────────────────────────────────────────────────────────────────────────

function adminFalso(o: { chave?: string | null; rpc?: () => { data: unknown; error: unknown }; conta?: unknown }) {
  const chamadas: Array<{ fn: string; args: unknown }> = [];
  return {
    chamadas,
    from: (tabela: string) => ({
      select: () => ({
        eq: () => ({
          maybeSingle: () => Promise.resolve(tabela === "app_settings"
            ? { data: o.chave === undefined || o.chave === null ? null : { value: o.chave }, error: null }
            : { data: o.conta ?? null, error: null }),
        }),
      }),
    }),
    rpc: (fn: string, args: unknown) => {
      chamadas.push({ fn, args });
      return Promise.resolve(o.rpc ? o.rpc() : { data: resposta(), error: null });
    },
  };
}

Deno.test("lerPagamentosDaManha: lê pela RPC com o dia; chave desligada nem chama; erro e função ausente = null, sem lançar", async () => {
  const ok = adminFalso({});
  assertEquals((await lerPagamentosDaManha(ok, "2026-11-30"))?.contas.length, 3);
  assertEquals(ok.chamadas, [{ fn: "pagamentos_da_semana", args: { p_hoje: "2026-11-30" } }]);

  const desligado = adminFalso({ chave: " Desligado " });
  assertEquals(await lerPagamentosDaManha(desligado, "2026-11-30"), null);
  assertEquals(desligado.chamadas.length, 0);

  assertEquals(await lerPagamentosDaManha(adminFalso({ rpc: () => ({ data: null, error: { code: "PGRST202", message: "não existe" } }) }), "2026-11-30"), null);
  assertEquals(await lerPagamentosDaManha(adminFalso({ rpc: () => ({ data: null, error: { code: "57014", message: "timeout" } }) }), "2026-11-30"), null);
  assertEquals(await lerPagamentosDaManha(adminFalso({ rpc: () => ({ data: { torto: true }, error: null }) }), "2026-11-30"), null);
});

Deno.test("filaDePagamentos: função ainda não publicada = null; qualquer outro erro LANÇA (não vira 'não há conta')", async () => {
  const ok = adminFalso({});
  assertEquals((await filaDePagamentos(ok, "2026-12-07"))?.soma, 2335.6);
  assertEquals(ok.chamadas, [{ fn: "pagamentos_da_semana", args: { p_ate: "2026-12-07" } }]);
  assertEquals(await filaDePagamentos(adminFalso({ rpc: () => ({ data: null, error: { code: "PGRST202" } }) }), "2026-12-07"), null);
  assertEquals(await filaDePagamentos({ from: () => ({}) }, "2026-12-07"), null);
  await assertRejects(
    () => filaDePagamentos(adminFalso({ rpc: () => ({ data: null, error: { code: "57014", message: "canceling statement" } }) }), "2026-12-07"),
    Error, "Não consegui ler a ordem de pagamento",
  );
});

Deno.test("resumirPrioridade: o dono lê o fornecedor pelo nome e o grupo por extenso; conta que não existe vira recusa", async () => {
  assertEquals(
    await resumirPrioridade(adminFalso({ conta: { supplier_name: "Unifique", suppliers: null } }), { payable_id: "c2", grupo: 2 }),
    "Prioridade de pagamento de *Unifique*: grupo 2 — serviço que corta.\nVale para as contas dele de agora e as próximas. Não paga nem altera conta.",
  );
  assertEquals(
    (await resumirPrioridade(adminFalso({ conta: { supplier_name: "nome livre", suppliers: { name: "KAMELL LTDA" } } }), { payable_id: "c1", grupo: 1 }))!.split("\n")[0],
    "Prioridade de pagamento de *KAMELL LTDA*: grupo 1 — pessoas e impostos.",
  );
  assertEquals(await resumirPrioridade(adminFalso({ conta: null }), { payable_id: "x", grupo: 2 }), "⚠️ Não achei essa conta a pagar.");
  assertEquals((await resumirPrioridade(adminFalso({ conta: { supplier_name: " ", suppliers: null } }), { payable_id: "x", grupo: 2 }))!.startsWith("⚠️"), true);
  assertEquals((await resumirPrioridade(adminFalso({}), { payable_id: "x", grupo: 7 }))!.startsWith("⚠️"), true);
});
