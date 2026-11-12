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
//     sem texto ou sem ação válida fica de fora; id que não é uuid não entra; ids repetidos uma vez só;
//  5. (Fase 7f, P4) a mensagem da quinta (semana): sem mudança com perguntas sai; no corte, as mudanças saem antes das perguntas;
//     o texto é o mesmo que o banco junta (o O4v de agenda_fase7f_lote.sql); o aviso de sempre não muda.
//  6. (Fase 7g, P6) o placar da quinta: antes das perguntas, o mesmo texto que o banco junta (o Q4p de agenda_fase7g_placar.sql);
//     no corte, cede primeiro (o texto, a linha, onde ver, nada) e os cortes de antes seguem iguais; sem a peça, o de antes.
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

// ── (Fase 7f, P4) A mensagem da quinta ────────────────────────────────────────────────────────────────────────────────
// O banco (_agenda_comunicar_quinta, migration 20261109100300) manda as peças com `semana`. Ela pode vir sem mudança, com
// perguntas; no corte, as mudanças viram "e mais N" antes de as perguntas saírem. O aviso de sempre não muda (os testes de cima).
// As peças de exemplo e o texto esperado são os MESMOS do O4v de supabase/tests/agenda_fase7f_lote.sql, que confere
// _agenda_lote_texto (o texto que a sombra guarda): os dois lados juntam igual.
const SEMANA_PERGUNTAS = [
  "Para a semana que vem preciso de:",
  "· Decisão 2: O serviço do Giancarlo (lancha, Troca do GPS) não cabe nas 2… Recomendo a opção 1: Passa para a semana seguinte, sem mudar o que já está marcado.",
  "· Você: Quais dias você fica em campo na semana de 16/11? Hoje eu conto você só para abrir e… Por enquanto conto você só para abrir e fechar.",
  "(e mais 3 em *agenda pendências*)",
  "Pode ser um áudio só, citando o nome do cliente.",
].join("\n");
const SEMANA_BANCO = {
  avisar: true, semana: true, rodada: "2026-11-12T20:00:00+00:00", dia: "2026-11-12", limite: 2400,
  cabecalho: "Agenda — o que eu mudei sozinho:",
  mudancas: [
    { texto: "Marquei Lenine em seg 16/11 com Alex (3 dias, estimativa minha). *desfaz Lenine* volta como estava.", acao_ids: [A1] },
    { texto: "Passei Vanderlei da tarde de hoje para qua 11/11 de manhã. *desfaz Vanderlei* volta como estava.", acao_ids: [A2] },
  ],
  fora: "Ficou de fora: MP (esperando o sinal).", rodape: "*agenda plano* mostra tudo.",
  perguntas: { texto: SEMANA_PERGUNTAS, pergunta_ids: [Q1, Q2] }, perguntas_erro: null,
};
const SEMANA_TEXTO = [
  "Agenda — o que eu mudei sozinho:",
  "• Marquei Lenine em seg 16/11 com Alex (3 dias, estimativa minha). *desfaz Lenine* volta como estava.",
  "• Passei Vanderlei da tarde de hoje para qua 11/11 de manhã. *desfaz Vanderlei* volta como estava.",
  "Ficou de fora: MP (esperando o sinal).",
  "*agenda plano* mostra tudo.",
  "",
  SEMANA_PERGUNTAS,
].join("\n");
const SEMANA_SEM_MUDANCA = { ...SEMANA_BANCO, cabecalho: "Agenda — a semana que vem:", mudancas: [], fora: null };
const SEMANA_SEM_MUDANCA_TEXTO = ["Agenda — a semana que vem:", "*agenda plano* mostra tudo.", "", SEMANA_PERGUNTAS].join("\n");

function lidaDaSemana(v: unknown): PecasDoAviso {
  const r = lerPecasDoAviso(v);
  if (!r || !r.avisar) throw new Error("as peças da semana não foram lidas");
  return r.pecas;
}

Deno.test("semana: o texto é o mesmo que o banco junta (O4v do teste SQL): cabeçalho, mudanças, o de fora, rodapé, linha em branco e as perguntas", () => {
  const p = lidaDaSemana(SEMANA_BANCO);
  assertEquals(p.semana, true);
  const m = montarAvisoDoGestor(p)!;
  assertEquals(m.texto, SEMANA_TEXTO);
  assertEquals([m.acaoIds, m.perguntaIds, m.comPerguntas, m.cortes], [[A1, A2], [Q1, Q2], true, []]);
});

Deno.test("semana: sem mudança, com perguntas, sai (a mensagem da semana sai mesmo sem mudança); nenhuma ação conta", () => {
  const p = lidaDaSemana(SEMANA_SEM_MUDANCA);
  const m = montarAvisoDoGestor(p)!;
  assertEquals(m.texto, SEMANA_SEM_MUDANCA_TEXTO);
  assertEquals([m.acaoIds, m.perguntaIds, m.comPerguntas], [[], [Q1, Q2], true]);
});

Deno.test("semana: sem mudança e sem pergunta (ou sem pergunta que conte) não é lida; o aviso de sempre sem mudança continua null", () => {
  assertEquals(lerPecasDoAviso({ ...SEMANA_SEM_MUDANCA, perguntas: null }), null);
  assertEquals(lerPecasDoAviso({ ...SEMANA_SEM_MUDANCA, perguntas: { texto: SEMANA_PERGUNTAS, pergunta_ids: ["nao-e-uuid"] } }), null);
  assertEquals(lerPecasDoAviso({ ...SEMANA_SEM_MUDANCA, semana: undefined }), null, "sem a marca da semana, é o aviso de sempre: sem mudança, nada");
  assertEquals(lerPecasDoAviso({ ...SEMANA_SEM_MUDANCA, semana: "sim" }), null, "só true marca a semana");
  assertEquals(montarAvisoDoGestor({ ...lidaDaSemana(SEMANA_SEM_MUDANCA), semana: undefined }), null, "o montador também: sem a marca, sem mudança = nada");
});

Deno.test("semana: o aviso de sempre não ganha a chave semana (as peças de antes, iguais)", () => {
  const r = lerPecasDoAviso({ ...SEMANA_BANCO, semana: false });
  assertEquals(r?.avisar === true ? "semana" in r.pecas : "?", false);
});

Deno.test("semana: passou do teto — sai o de fora; depois as últimas mudanças viram \"e mais N\" e as perguntas FICAM (e contam)", () => {
  const p = lidaDaSemana(SEMANA_BANCO);
  const semFora = SEMANA_TEXTO.replace("Ficou de fora: MP (esperando o sinal).\n", "");
  const a = montarAvisoDoGestor({ ...p, limite: semFora.length })!;
  assertEquals([a.texto, a.cortes, a.comPerguntas], [semFora, ["fora"], true]);
  const umaMudanca = semFora.replace(/• Passei Vanderlei[^\n]*\n/, "• e mais 1 mudança: *o que mudou* mostra todas.\n");
  const b = montarAvisoDoGestor({ ...p, limite: umaMudanca.length })!;
  assertEquals([b.texto, b.cortes, b.perguntaIds, b.acaoIds], [umaMudanca, ["fora", "mudancas"], [Q1, Q2], [A1, A2]]);
});

Deno.test("semana: nem com 1 mudança cabe com as perguntas — elas saem (e não contam); sem mudança e sem caber, nada a mandar", () => {
  const p = lidaDaSemana(SEMANA_BANCO);
  const m = montarAvisoDoGestor({ ...p, limite: 600 })!;
  assert(m.texto.length <= 600);
  assertEquals([m.comPerguntas, m.perguntaIds, m.cortes.includes("perguntas")], [false, [], true]);
  assertEquals(montarAvisoDoGestor({ ...lidaDaSemana(SEMANA_SEM_MUDANCA), limite: SEMANA_SEM_MUDANCA_TEXTO.length - 1 }), null);
});

Deno.test("semana: nunca passa do teto, em qualquer teto (de 600 a 2400)", () => {
  for (const base of [SEMANA_BANCO, SEMANA_SEM_MUDANCA]) {
    const p = lidaDaSemana(base);
    for (let limite = 600; limite <= 2400; limite += 37) {
      const m = montarAvisoDoGestor({ ...p, limite });
      if (m) assert(m.texto.length <= limite, `${limite}: ${m.texto.length}`);
    }
  }
});

// ── (Fase 7g, P6) O placar da semana na mensagem da quinta ────────────────────────────────────────────────────────────────
// A peça placar ({texto, linha}) vai depois do rodapé e antes das perguntas, com uma linha em branco dos dois lados. As peças e
// o texto esperado são os MESMOS do Q4p de supabase/tests/agenda_fase7g_placar.sql, que confere _agenda_lote_texto: os dois
// lados juntam igual. No corte, o placar cede primeiro, inteiro: o texto, a linha, "Placar da semana em *agenda placar*.",
// nada; só então os cortes de antes (o de fora, as mudanças, as perguntas), na ordem de antes.
const PLACAR_TEXTO = [
  "Placar da semana de 02 a 07/11 (números do sistema):",
  "• Serviços prontos com data firme: 1 de 5 (20%).",
  "• Compras: 4 de 7 feitas até o \"compre até\".",
  "• Perguntas abertas: 7 (a mais antiga com 5 dias úteis).",
  "Detalhe em *agenda placar*.",
].join("\n");
const PLACAR_LINHA = "Placar 02 a 07/11: 1 de 5 prontos com data; compras 4 de 7 no prazo. Detalhe em *agenda placar*.";
const SEMANA_COM_PLACAR = { ...SEMANA_BANCO, placar: { texto: PLACAR_TEXTO, linha: PLACAR_LINHA } };
const CORPO_DA_SEMANA = SEMANA_TEXTO.slice(0, SEMANA_TEXTO.indexOf("\n\nPara a semana que vem"));
const comPlacar = (placar: string) => `${CORPO_DA_SEMANA}\n\n${placar}\n\n${SEMANA_PERGUNTAS}`;

Deno.test("placar: o texto é o mesmo que o banco junta (Q4p do teste SQL): o corpo, a linha em branco, o placar, a linha em branco e as perguntas", () => {
  const p = lidaDaSemana(SEMANA_COM_PLACAR);
  assertEquals(p.placar, { texto: PLACAR_TEXTO, linha: PLACAR_LINHA });
  const m = montarAvisoDoGestor(p)!;
  assertEquals(m.texto, comPlacar(PLACAR_TEXTO));
  assertEquals([m.acaoIds, m.perguntaIds, m.comPerguntas, m.cortes], [[A1, A2], [Q1, Q2], true, []]);
  assert(m.texto.length <= 2400, "o caso de hoje cabe inteiro no teto padrão da quinta (2400)");
});

Deno.test("placar: sem a peça, ou sem texto nela, as peças e o texto de antes (a chave nem aparece); sem linha, linha nula", () => {
  for (const placar of [undefined, null, "texto", [], { texto: "  ", linha: PLACAR_LINHA }, { linha: PLACAR_LINHA }]) {
    const p = lidaDaSemana({ ...SEMANA_BANCO, placar });
    assertEquals("placar" in p, false, JSON.stringify(placar));
    assertEquals(montarAvisoDoGestor(p)!.texto, SEMANA_TEXTO);
  }
  assertEquals(lidaDaSemana({ ...SEMANA_BANCO, placar: { texto: PLACAR_TEXTO } }).placar, { texto: PLACAR_TEXTO, linha: null });
});

Deno.test("placar: sem mudança e sem pergunta a quinta não sai, nem com o placar (nenhuma mensagem só de placar)", () => {
  assertEquals(lerPecasDoAviso({ ...SEMANA_SEM_MUDANCA, perguntas: null, placar: { texto: PLACAR_TEXTO, linha: PLACAR_LINHA } }), null);
  const so = lidaDaSemana({ ...SEMANA_SEM_MUDANCA, placar: { texto: PLACAR_TEXTO, linha: PLACAR_LINHA } });
  assertEquals(montarAvisoDoGestor(so)!.texto, `Agenda — a semana que vem:\n*agenda plano* mostra tudo.\n\n${PLACAR_TEXTO}\n\n${SEMANA_PERGUNTAS}`);
});

Deno.test("placar: cede primeiro, antes de qualquer corte de antes — a linha, depois onde ver, depois nada; e só então o de fora", () => {
  const p = lidaDaSemana(SEMANA_COM_PLACAR);
  const a = montarAvisoDoGestor({ ...p, limite: comPlacar(PLACAR_LINHA).length })!;
  assertEquals([a.texto, a.cortes, a.comPerguntas], [comPlacar(PLACAR_LINHA), ["placar"], true]);
  const b = montarAvisoDoGestor({ ...p, limite: comPlacar("Placar da semana em *agenda placar*.").length })!;
  assertEquals([b.texto, b.cortes, b.comPerguntas], [comPlacar("Placar da semana em *agenda placar*."), ["placar"], true]);
  const c = montarAvisoDoGestor({ ...p, limite: SEMANA_TEXTO.length })!;
  assertEquals([c.texto, c.cortes, c.comPerguntas, c.perguntaIds], [SEMANA_TEXTO, ["placar"], true, [Q1, Q2]]);
  // sem o placar, os cortes de antes, iguais aos da mesma mensagem sem a peça
  // (os tetos abaixo do texto sem o placar: nem onde ver cabe)
  for (const limite of [SEMANA_TEXTO.length - 1, SEMANA_TEXTO.length - 100, 600]) {
    assert(limite < SEMANA_TEXTO.length);
    const com = montarAvisoDoGestor({ ...p, limite })!;
    const sem = montarAvisoDoGestor({ ...lidaDaSemana(SEMANA_BANCO), limite })!;
    assertEquals([com.texto, com.cortes, com.perguntaIds], [sem.texto, ["placar", ...sem.cortes], sem.perguntaIds], String(limite));
  }
});

Deno.test("placar: sem a linha, do texto direto para onde ver", () => {
  const p = lidaDaSemana({ ...SEMANA_BANCO, placar: { texto: PLACAR_TEXTO, linha: null } });
  const m = montarAvisoDoGestor({ ...p, limite: comPlacar(PLACAR_LINHA).length })!;
  assertEquals([m.texto, m.cortes], [comPlacar("Placar da semana em *agenda placar*."), ["placar"]]);
});

Deno.test("placar: nunca passa do teto, em qualquer teto (de 600 a 2400)", () => {
  for (const base of [SEMANA_COM_PLACAR, { ...SEMANA_SEM_MUDANCA, placar: { texto: PLACAR_TEXTO, linha: PLACAR_LINHA } }]) {
    const p = lidaDaSemana(base);
    for (let limite = 600; limite <= 2400; limite += 37) {
      const m = montarAvisoDoGestor({ ...p, limite });
      if (m) assert(m.texto.length <= limite, `${limite}: ${m.texto.length}`);
    }
  }
});
