// (19/11/2026, agenda, Opção A) O pedido de aprovação da mensagem ao cliente no resumo da manhã, com o prazo: o bloco vem
// pronto do banco (agenda_aprovacoes_da_manha), entra no fim do texto (antes da sugestão de imprimir), só em dia útil, e as
// perguntas que ele mostrou são guardadas com o id da fila do dono (agenda_fechamento_guardar, via 'manha'). Sem bloco, o
// texto de antes, byte a byte.
import { assertEquals, assertThrows } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  aprovacoesDaResposta, comAprovacoesAoCliente, guardarAprovacoesDaManha, lerAprovacoesDaManha, montarDosDados,
} from "./secretario.ts";
import { AGORA_1510, coleta1510, deHoje1510, HOJE_1510 } from "./secretario-fixture.ts";

const BLOCO = "📨 Mensagens ao cliente esperando o seu sim:\n" +
  "• Rodrigo: a véspera com a pergunta do acesso (qua 25/11). Mando? (vence 19h)\n" +
  "• Ana: que o serviço ficou pronto. Mando? (vence sáb 21/11 13h)\n" +
  "Para mandar: *manda cliente Rodrigo* (ou *manda cliente*: as 2). Para não mandar: *segura cliente Rodrigo*. O texto: *agenda clientes*.";
const RESPOSTA = {
  total: 2,
  texto: BLOCO,
  linhas: [
    { pergunta_id: "q-1", mensagem_id: "m-1", nome: "Rodrigo", texto: "…", vence_em: "2026-11-24T22:00:00+00:00" },
    { pergunta_id: "q-2", mensagem_id: "m-2", nome: "Ana", texto: "…", vence_em: "2026-11-21T16:00:00+00:00" },
  ],
};

// deno-lint-ignore no-explicit-any
function falsoAdmin(resposta: { data?: unknown; error?: unknown }): { admin: any; chamadas: Array<{ nome: string; args: any }> } {
  // deno-lint-ignore no-explicit-any
  const chamadas: Array<{ nome: string; args: any }> = [];
  return {
    chamadas,
    admin: {
      // deno-lint-ignore no-explicit-any
      rpc: (nome: string, args: any) => {
        chamadas.push({ nome, args });
        return Promise.resolve({ data: resposta.data ?? null, error: resposta.error ?? null });
      },
    },
  };
}

const BASE = {
  hoje: HOJE_1510, agora: AGORA_1510, coleta: coleta1510(), historico: [],
  naRua: { total: 21026, n: 5 }, deHoje: deHoje1510(),
  escritorio: { propostas: null, alertas: null, regras: null, debitosSemLoja: null, entradas: null },
};

Deno.test("aprovacoesDaResposta: o bloco e as perguntas escritas; nada esperando = null; forma errada lança", () => {
  assertEquals(aprovacoesDaResposta(RESPOSTA), { texto: BLOCO, perguntaIds: ["q-1", "q-2"] });
  assertEquals(aprovacoesDaResposta({ total: 0, linhas: [], texto: null }), null);
  assertEquals(aprovacoesDaResposta({ total: 1, linhas: [], texto: "  " }), null);
  assertThrows(() => aprovacoesDaResposta(null));
  assertThrows(() => aprovacoesDaResposta([RESPOSTA]));
  assertThrows(() => aprovacoesDaResposta({ texto: BLOCO }));
  assertThrows(() => aprovacoesDaResposta({ texto: BLOCO, linhas: [{ nome: "Ana" }] }));
});

Deno.test("comAprovacoesAoCliente: dia útil ganha o bloco depois de uma linha em branco; domingo, feriado ou sem bloco = igual", () => {
  const a = { texto: BLOCO, perguntaIds: ["q-1"] };
  assertEquals(comAprovacoesAoCliente("Bom dia!", "util", a), `Bom dia!\n\n${BLOCO}`);
  assertEquals(comAprovacoesAoCliente("Bom dia! Domingo", "domingo", a), "Bom dia! Domingo");
  assertEquals(comAprovacoesAoCliente("Bom dia! Feriado", "feriado", a), "Bom dia! Feriado");
  assertEquals(comAprovacoesAoCliente("Bom dia!", "util", null), "Bom dia!");
});

Deno.test("montarDosDados: sem aprovacoes o texto é o de antes (byte a byte); com, o bloco no fim e antes da sugestão de imprimir", () => {
  const antes = montarDosDados(BASE);
  assertEquals(antes.aprovacoes, null);
  assertEquals(montarDosDados({ ...BASE, aprovacoes: null }).texto, antes.texto);
  const a = { texto: BLOCO, perguntaIds: ["q-1", "q-2"] };
  const com = montarDosDados({ ...BASE, aprovacoes: a });
  assertEquals(com.texto, `${antes.texto}\n\n${BLOCO}`);
  assertEquals(com.aprovacoes, { perguntaIds: ["q-1", "q-2"] });
  // os itens com letra não mudam (o bloco não tem letra: a resposta é *manda cliente <nome>*)
  assertEquals(com.itens, antes.itens);
  const comVias = montarDosDados({ ...BASE, aprovacoes: a, viasParaImprimir: 2 }).texto;
  assertEquals(comVias, `${antes.texto}\n\n${BLOCO}\n🖨️ Quer as 2 vias de hoje no papel? Responda: *imprime as vias de hoje*`);
});

Deno.test("montarDosDados: domingo não leva o bloco nem guarda pergunta (a manhã de folga é uma linha)", () => {
  const domingo = { ...BASE, hoje: "2026-10-18", agora: new Date("2026-10-18T10:30:00Z") };
  const sem = montarDosDados(domingo);
  const com = montarDosDados({ ...domingo, aprovacoes: { texto: BLOCO, perguntaIds: ["q-1"] } });
  assertEquals(com.texto, sem.texto);
  assertEquals(com.aprovacoes, null);
});

Deno.test("lerAprovacoesDaManha: chama agenda_aprovacoes_da_manha com o dia e a hora; erro ou forma errada = null (nunca lança)", async () => {
  const f = falsoAdmin({ data: RESPOSTA });
  assertEquals(await lerAprovacoesDaManha(f.admin, HOJE_1510, AGORA_1510), { texto: BLOCO, perguntaIds: ["q-1", "q-2"] });
  assertEquals(f.chamadas, [{ nome: "agenda_aprovacoes_da_manha", args: { p_hoje: HOJE_1510, p_agora: AGORA_1510.toISOString() } }]);
  assertEquals(await lerAprovacoesDaManha(falsoAdmin({ error: { code: "42883" } }).admin, HOJE_1510, AGORA_1510), null);
  assertEquals(await lerAprovacoesDaManha(falsoAdmin({ data: { texto: 1 } }).admin, HOJE_1510, AGORA_1510), null);
  const lanca = { rpc: () => Promise.reject(new Error("rede")) };
  assertEquals(await lerAprovacoesDaManha(lanca, HOJE_1510, AGORA_1510), null);
});

Deno.test("guardarAprovacoesDaManha: a guarda do fechamento com via 'manha', só perguntas, com o id da fila do dono", async () => {
  const f = falsoAdmin({ data: { ok: true, estado: "esperando", id: "g1", perguntas: 0, acoes: 0 } });
  const r = await guardarAprovacoesDaManha(f.admin, { hoje: "2026-11-21", perguntaIds: ["q-1", "q-2"], filaId: "fila-1", agora: AGORA_1510 });
  assertEquals(r, { estado: "esperando", perguntas: 0 });
  assertEquals(f.chamadas, [{
    nome: "agenda_fechamento_guardar",
    args: {
      p_hoje: "2026-11-21",
      p_linhas: [{ pergunta_id: "q-1", acao_ids: [] }, { pergunta_id: "q-2", acao_ids: [] }],
      p_fila: "fila-1",
      p_via: "manha",
      p_agora: AGORA_1510.toISOString(),
    },
  }]);
  const ja = falsoAdmin({ data: { ok: true, estado: "registrada", perguntas: 2 } });
  assertEquals(await guardarAprovacoesDaManha(ja.admin, { hoje: "2026-11-21", perguntaIds: ["q-1"], filaId: "fila-1", agora: AGORA_1510 }),
    { estado: "registrada", perguntas: 2 });
});

Deno.test("guardarAprovacoesDaManha: sem perguntas não chama; sem a fila nada é guardado; erro do banco = 'erro' (nunca lança)", async () => {
  const f = falsoAdmin({ data: { ok: true } });
  assertEquals(await guardarAprovacoesDaManha(f.admin, { hoje: HOJE_1510, perguntaIds: [], filaId: "fila-1", agora: AGORA_1510 }), null);
  assertEquals(await guardarAprovacoesDaManha(f.admin, { hoje: HOJE_1510, perguntaIds: ["q-1"], filaId: null, agora: AGORA_1510 }), "sem_fila");
  assertEquals(f.chamadas.length, 0);
  assertEquals(await guardarAprovacoesDaManha(falsoAdmin({ data: { ok: false, motivo: "sem_fila" } }).admin,
    { hoje: HOJE_1510, perguntaIds: ["q-1"], filaId: "fila-x", agora: AGORA_1510 }), "sem_fila");
  assertEquals(await guardarAprovacoesDaManha(falsoAdmin({ error: { code: "22023" } }).admin,
    { hoje: HOJE_1510, perguntaIds: ["q-1"], filaId: "fila-1", agora: AGORA_1510 }), "erro");
});
