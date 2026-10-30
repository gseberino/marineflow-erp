// O montador do aviso do gestor ao dono (Agenda de Produção, correção de 29/10, P4).
//
// O que estes testes protegem:
//  1. a ordem do texto: o cabeçalho, uma linha "• " por mudança, o que ficou de fora, o rodapé, a linha em branco e as
//     perguntas — os textos do banco como vieram (nenhuma data ou nome muda aqui); conta todas as ações e as perguntas;
//  2. o caso de hoje (29/10, a bancada da migration: a publicação de 03 a 06/11 com a reserva do Lenine, os 10 de fora e a
//     rodada de aprontar) cabe inteiro no teto padrão;
//  3. o corte pelo teto, nesta ordem: o que ficou de fora; as perguntas (que então não contam como mostradas); as últimas
//     mudanças ("e mais N", que contam); a única que sobrou, na palavra, com "…". Nunca passa do teto;
//  4. a leitura do que o banco devolve: não avisar (com o motivo e o que espera a janela); formato estranho = null; mudança
//     sem texto ou sem ação válida fica de fora; id que não é uuid não entra; ids repetidos uma vez só.
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { lerPecasDoAviso, montarAvisoDoGestor, type PecasDoAviso } from "./aviso-do-gestor.ts";

const A1 = "e513491a-ed1b-4636-9185-44294948343f";
const A2 = "0b1c6a35-7d0e-4c55-9a51-6f2b8c1d2e30";
const A3 = "6a7b8c9d-0e1f-4a2b-8c3d-4e5f6a7b8c9d";
const Q1 = "6037294c-834c-48b0-9943-6d41d85453ec";
const Q2 = "e452fa40-581c-41af-a037-2adc6297b971";

// Os textos de hoje como a bancada os devolve (supabase/tests/agenda_correcao_2910_p4.sql, H).
const PUBLICACAO = "Publiquei a semana de 03 a 06/11 (seg 02 é Finados) — 1 reservado, nada marcado firme: Reserva Lenine " +
  "(OS-00074): qui 05 a ter 10/11, João os 3 dias, Roberto os 3 dias — se você disser até qua 04/11 se tem peça a comprar. " +
  "*desfaz semana* volta como estava.";
const FORA = "Ficaram de fora 10: Giancarlo (sem lugar na equipe); Rodrigo OS-00096 (só com você); Vanderlei, Flávio e Nelson " +
  "(material); Kalmar OS-00032, Kalmar OS-00033 e Rodrigo OS-00076 (esperando o cliente); Robson (orçamento que não virou " +
  "OS); MP (esperando o sinal).";
const APRONTAR = [
  "Para montar a semana, uma resposta por OS (entre parênteses, o meu chute pelo valor):",
  "• Vanderlei (OS-00069): o material (4 itens) — compra quando e onde? Quantos dias e com quem? (2 a 3,5 dias, 2 pessoas)",
  "• Lenine (OS-00074): tem peça a comprar? Quantos dias e com quem? (1,5 a 3 dias, 2 pessoas)",
  "• Você: semana que vem fica em campo quais dias?",
  "Pode ser um áudio só, citando o nome do cliente. (Robson ORÇ-00083 e Rodrigo OS-00096 ficam para depois.)",
].join("\n");
const CABECALHO = "Agenda — o que eu mudei sozinho:";
const RODAPE = "*agenda plano* mostra tudo.";

function pecas(extra: Partial<PecasDoAviso> = {}): PecasDoAviso {
  return {
    rodada: "2026-10-29T19:45:00+00:00", dia: "2026-10-29", limite: 2400, cabecalho: CABECALHO,
    mudancas: [{ texto: PUBLICACAO, acaoIds: [A1] }], fora: FORA, rodape: RODAPE,
    perguntas: { texto: APRONTAR, perguntaIds: [Q1, Q2] },
    ...extra,
  };
}

Deno.test("a ordem: cabeçalho, uma linha por mudança, o de fora, o rodapé, a linha em branco e as perguntas", () => {
  const m = montarAvisoDoGestor(pecas())!;
  assertEquals(m.texto, [CABECALHO, `• ${PUBLICACAO}`, FORA, RODAPE, "", APRONTAR].join("\n"));
  assertEquals(m.acaoIds, [A1]);
  assertEquals(m.perguntaIds, [Q1, Q2]);
  assertEquals(m.comPerguntas, true);
  assertEquals(m.cortes, []);
});

Deno.test("o caso de hoje cabe inteiro no teto padrão (2400) e cada mudança tem a sua linha", () => {
  const m = montarAvisoDoGestor(pecas({
    mudancas: [{ texto: PUBLICACAO, acaoIds: [A1] }, { texto: "Lenine (OS-00074): soltei a reserva.", acaoIds: [A2, A3] }],
  }))!;
  assert(m.texto.length <= 2400, String(m.texto.length));
  assertEquals(m.texto.split("\n").slice(0, 3), [CABECALHO, `• ${PUBLICACAO}`, "• Lenine (OS-00074): soltei a reserva."]);
  assertEquals(m.acaoIds, [A1, A2, A3]);
  assertEquals(m.cortes, []);
});

Deno.test("sem o de fora, sem perguntas e sem rodapé: só o cabeçalho e as mudanças (nenhuma pergunta conta)", () => {
  const m = montarAvisoDoGestor(pecas({ fora: null, perguntas: null, rodape: null }))!;
  assertEquals(m.texto, `${CABECALHO}\n• ${PUBLICACAO}`);
  assertEquals(m.perguntaIds, []);
  assertEquals(m.comPerguntas, false);
});

Deno.test("passou do teto: sai primeiro o que ficou de fora (as perguntas ficam e contam)", () => {
  const cheio = montarAvisoDoGestor(pecas())!.texto.length;
  const m = montarAvisoDoGestor(pecas({ limite: cheio - 1 }))!;
  assertEquals(m.texto, [CABECALHO, `• ${PUBLICACAO}`, RODAPE, "", APRONTAR].join("\n"));
  assertEquals(m.cortes, ["fora"]);
  assertEquals(m.perguntaIds, [Q1, Q2]);
});

Deno.test("passou do teto de novo: saem as perguntas, e então elas não contam como mostradas", () => {
  const semFora = [CABECALHO, `• ${PUBLICACAO}`, RODAPE, "", APRONTAR].join("\n").length;
  const m = montarAvisoDoGestor(pecas({ limite: semFora - 1 }))!;
  assertEquals(m.texto, [CABECALHO, `• ${PUBLICACAO}`, RODAPE].join("\n"));
  assertEquals(m.cortes, ["fora", "perguntas"]);
  assertEquals(m.perguntaIds, []);
  assertEquals(m.comPerguntas, false);
  assertEquals(m.acaoIds, [A1]);
});

Deno.test("muitas mudanças: as últimas viram \"e mais N\" e TODAS as ações contam (o dono sabe que existem)", () => {
  const mudancas = [A1, A2, A3].map((id, i) => ({ texto: `Mudança ${i + 1}: ${"x".repeat(200)}.`, acaoIds: [id] }));
  const m = montarAvisoDoGestor(pecas({ mudancas, fora: null, perguntas: null, limite: 600 }))!;
  assertEquals(m.texto.split("\n"), [CABECALHO, `• ${mudancas[0].texto}`, `• ${mudancas[1].texto}`,
    "• e mais 1 mudança: *o que mudou* mostra todas.", RODAPE]);
  assertEquals(m.acaoIds, [A1, A2, A3]);
  assertEquals(m.cortes, ["mudancas"]);
  const dois = montarAvisoDoGestor(pecas({ mudancas, fora: null, perguntas: null, limite: 400 }))!;
  assert(dois.texto.includes("• e mais 2 mudanças: *o que mudou* mostra todas."), dois.texto);
  assertEquals(dois.acaoIds, [A1, A2, A3]);
});

Deno.test("uma mudança só, maior que o teto: cortada na palavra, com \"…\"; o rodapé fica; nunca passa do teto", () => {
  const longa = `Publiquei a semana: ${Array.from({ length: 200 }, (_, i) => `palavra${i}`).join(" ")}.`;
  const m = montarAvisoDoGestor(pecas({ mudancas: [{ texto: longa, acaoIds: [A1] }], limite: 600 }))!;
  assert(m.texto.length <= 600, String(m.texto.length));
  assert(m.texto.startsWith(`${CABECALHO}\n• Publiquei a semana: palavra0 palavra1`), m.texto);
  assert(/palavra\d+…\n/.test(m.texto), m.texto);
  assert(m.texto.endsWith(`\n${RODAPE}`), m.texto);
  assertEquals(m.cortes, ["fora", "perguntas", "linha"]);
  assertEquals(m.acaoIds, [A1]);
});

Deno.test("nunca passa do teto, em qualquer teto (de 600 a 2400)", () => {
  const mudancas = [A1, A2, A3].map((id, i) => ({ texto: `${PUBLICACAO} (${i})`, acaoIds: [id] }));
  for (let limite = 600; limite <= 2400; limite += 37) {
    const m = montarAvisoDoGestor(pecas({ mudancas, limite }))!;
    assert(m.texto.length <= limite, `${limite}: ${m.texto.length}`);
    assert(m.texto.startsWith(`${CABECALHO}\n• `), String(limite));
    assertEquals(m.acaoIds, [A1, A2, A3]);
    assertEquals(m.comPerguntas, m.texto.includes(APRONTAR));
  }
});

Deno.test("sem mudança nenhuma: nada a mandar", () => {
  assertEquals(montarAvisoDoGestor(pecas({ mudancas: [] })), null);
});

Deno.test("leitura: o banco diz que não avisa (o motivo e o que espera a janela abrir)", () => {
  assertEquals(lerPecasDoAviso({ avisar: false, motivo: "fora_da_janela", janela: "janela", pendentes: 2 }),
    { avisar: false, motivo: "fora_da_janela", pendentes: 2 });
  assertEquals(lerPecasDoAviso({ avisar: false, motivo: "nada_mudou" }), { avisar: false, motivo: "nada_mudou", pendentes: null });
  assertEquals(lerPecasDoAviso({ avisar: false }), null);
});

Deno.test("leitura: as peças de verdade; a mudança sem texto ou sem ação válida fica de fora; id estranho não entra", () => {
  const r = lerPecasDoAviso({
    avisar: true, rodada: "2026-10-29T19:45:00+00:00", dia: "2026-10-29", limite: 2400, cabecalho: ` ${CABECALHO} `,
    mudancas: [
      { texto: PUBLICACAO, acao_ids: [A1, A1, "nao-e-uuid"] },
      { texto: "  ", acao_ids: [A2] },
      { texto: "Sem ação.", acao_ids: [] },
      null,
    ],
    fora: FORA, rodape: RODAPE, perguntas: { texto: APRONTAR, pergunta_ids: [Q1, 7, Q2] },
  });
  assertEquals(r, { avisar: true, pecas: pecas() });
  // sem perguntas (o banco manda null: já foram hoje)
  const s = lerPecasDoAviso({ avisar: true, rodada: "r", dia: "d", limite: 2400, cabecalho: CABECALHO,
    mudancas: [{ texto: PUBLICACAO, acao_ids: [A1] }], fora: null, rodape: RODAPE, perguntas: null });
  assertEquals(s?.avisar === true ? s.pecas.perguntas : "?", null);
});

Deno.test("leitura: a rodada de aprontar que falhou no banco vem em perguntasErro (o resto do aviso igual)", () => {
  const r = lerPecasDoAviso({ avisar: true, rodada: "r", dia: "d", limite: 2400, cabecalho: CABECALHO,
    mudancas: [{ texto: PUBLICACAO, acao_ids: [A1] }], fora: null, rodape: RODAPE, perguntas: null,
    perguntas_erro: "XX000: falhou o painel" });
  assertEquals(r?.avisar === true ? [r.pecas.perguntas, r.pecas.perguntasErro] : "?", [null, "XX000: falhou o painel"]);
});

Deno.test("leitura: formato que não é o combinado = null (quem chama registra o erro e não manda nada)", () => {
  for (const v of [null, undefined, "x", [], 7, {}, { avisar: "sim" },
                   { avisar: true, limite: 2400, cabecalho: CABECALHO, rodada: "r", dia: "d", mudancas: [] },
                   { avisar: true, limite: 0, cabecalho: CABECALHO, rodada: "r", dia: "d", mudancas: [{ texto: "x", acao_ids: [A1] }] },
                   { avisar: true, limite: 2400, rodada: "r", dia: "d", mudancas: [{ texto: "x", acao_ids: [A1] }] },
                   { avisar: true, limite: 2400, cabecalho: CABECALHO, rodada: "r", dia: "d", mudancas: "x" }]) {
    assertEquals(lerPecasDoAviso(v), null, JSON.stringify(v));
  }
});
