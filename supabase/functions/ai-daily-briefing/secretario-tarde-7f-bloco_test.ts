// (Agenda de Produção, Fase 7f, P3 — migration 20261109100200, R8.4) O bloco da agenda nos 3 turnos da tarde: o ponto único, a régua dos 1.000, o "Amanhã", o temAlgo e a leitura. A forma do bloco e
// os textos saem do banco (supabase/tests/agenda_fase7f_bloco.sql): aqui ele chega pronto, com os níveis, como agenda_textos_do_fechamento manda.
import { assert, assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { agendaDoFechamento, blocoDaAgenda, lerAgendaDoFechamento } from "./secretario-tarde-coleta.ts";
import {
  type AgendaDoFechamento,
  type BlocoDaAgenda,
  blocoLigado,
  type DadosDaTarde,
  LIMITE_DA_TARDE,
  linhasDoBloco,
  type LinhaDoBloco,
  PARTES_DO_BLOCO,
  textoDaTarde,
  TIPOS_DE_LINHA_DA_AGENDA,
} from "./secretario-tarde-texto.ts";
import type { LinhaComLetra } from "./secretario-tarde-regras.ts";

const l = (parte: LinhaDoBloco["parte"], texto: string, entra: number, corte: number | null, extra: Partial<LinhaDoBloco> = {}): LinhaDoBloco => ({
  parte, texto, pergunta_id: null, acao_ids: [], nivel_entra: entra, nivel_de_corte: corte, ...extra,
});
const VEREDITO = "Agenda: mudei 2 coisas e preciso de 3 respostas suas. Amanhã (qua 11/11): Nelson com Roberto.";
const HOJE = "Hoje: 4 meios-dias marcados; falta dizer como foi (*dia feito* confirma).";
const DECISAO1 = "· Decisão 2: Giancarlo: Não cabe tudo até qui 12/11. Recomendo a opção 1: Giancarlo (OS-F5) atrasa: termina ter 24/11 em vez de qui 12/11.";
const DECISAO2 = "· Você: Para marcar Rodrigo (OS-00096), preciso saber em que dias você fica em campo. Por enquanto conto você só para abrir e fechar.";
const DECISAO3 = "· Lenine (OS-00074): marquei a partir de qui 05/11 contando que o motorhome está livre e no…";
const MUDOU = "Mudou: Marquei Lenine em seg 16/11 com Alex (3 dias, estimativa minha). *desfaz Lenine* volta como estava. Passei Vanderlei da tarde de hoje para qua 11/11 de manhã. *desfaz Vanderlei* volta como estava.";
/** O bloco como o banco manda: 3 decisões, as compras, a comissão, com a forma de cada nível (5 = só o veredito e a 1ª decisão). */
const LINHAS: LinhaDoBloco[] = [
  l("veredito", VEREDITO, 0, null),
  l("hoje", HOJE, 0, 5, { pergunta_id: "q-conf", pergunta_ids: ["q-conf"] }),
  l("mudou", MUDOU, 0, 2, { acao_ids: ["a1", "a2"] }),
  l("mudou", "Mudou: mudei 2 coisas (*o que mudou*).", 2, 5, { acao_ids: ["a1", "a2"] }),
  l("decisao", DECISAO1, 0, null, { pergunta_id: "q1", pergunta_ids: ["q1"], veto_ate: "2026-11-11T18:00:00-03:00" }),
  l("decisao", DECISAO2, 0, 4, { pergunta_id: "q2", pergunta_ids: ["q2"], veto_diria: "2026-11-11T18:00:00-03:00" }),
  l("decisao", DECISAO3, 0, 3, { pergunta_id: "q3", pergunta_ids: ["q3"] }),
  l("decisao", "(e mais 1 em *agenda pendências*)", 3, 4),
  l("decisao", "(e mais 2 em *agenda pendências*)", 4, 5),
  l("compras", "Compras: Kamell: Cerbo de Nelson — compre até qui 12/11.", 0, 1),
  l("compras", "+1 compra (*agenda compras*).", 1, 5),
  l("outras", "Comissão de outubro: R$ 100,00.", 0, 1),
];
const bloco = (extra: Partial<BlocoDaAgenda> = {}): BlocoDaAgenda => ({
  modo: "ligado", linhas: LINHAS, nivel: 0, nivel_min: 5, chars: 500, nada_mudou: false, incompleto: false, ...extra,
});
const VELHAS = [{ tipo: "pergunta" as const, texto: "Agenda: A LINHA VELHA DO PLANO.", perda: 76, pergunta_id: "q-velha", acao_ids: [], modo: "ligado" as const }];
const agenda = (b?: BlocoDaAgenda): AgendaDoFechamento => ({ modo: "ligado", cauda: "nada marcado; A CAUDA (*agenda*)", semana: ["Semana que vem (projeção): A SEMANA"], linhas: VELHAS, vagas_garantidas: 1, ...(b ? { bloco: b } : {}) });

function ficou(letra: string, texto: string): LinhaComLetra {
  return { letra, parte: "ficou", referencia: `ref:${letra}`, tipo: "cobranca_grande", texto, faco: "te mostro o lembrete pronto", alternativa: "até segunda", comandoAlternativo: "espera", valor: 100, desde: "2026-10-13" } as LinhaComLetra;
}
const ESCRITORIO = { propostas: { saidas: 107, entradas: 10, transferencias: 1, outras: 0 }, alertas: 33, regras: 0, debitosSemLoja: 8, entradas: null };
/** ter 10/11 (fechamento), seg 09/11 (revisão da semana), ter 03/11 (revisão do mês: seg 02/11 é Finados). */
const BASE = { ficaram: [], fornecedores: [], escritorio: null, parados: [], panorama: null, antigas: null, mesQueFechou: null, faturamento: null, pergunta: false };
function turno(t: "fechamento" | "revisao_semana" | "revisao_mes", ag?: AgendaDoFechamento | null, extra: Partial<DadosDaTarde> = {}): DadosDaTarde {
  const hoje = t === "fechamento" ? "2026-11-10" : t === "revisao_semana" ? "2026-11-09" : "2026-11-03";
  return { ...BASE, hoje, turno: t, amanha: { dia: "2026-11-11", itens: [], carteira: { semData: 2 }, ...(ag ? { agenda: ag } : {}) }, ...extra } as unknown as DadosDaTarde;
}
const TURNOS = ["fechamento", "revisao_semana", "revisao_mes"] as const;
/** Um Secretário cheio: 3 que ficaram, fornecedores, o escritório e, nas revisões, o panorama: o de produção de 950 letras, feito por extenso. */
const CHEIO: Partial<DadosDaTarde> = {
  ficaram: [
    ficou("A", "OS-00112 Nelson (Santo Inácio 7.8): 4 itens a comprar até seg 26/10"),
    ficou("B", "Marcelo Marco Bertoldi (OS-00038): R$ 16.890,00, venceu 13/10 (16 dias); ainda não entrou"),
    ficou("C", "APOLO INDUSTRIA E COMERCIO DE…: R$ 5.237,99, venceu 16/10 (13 dias); ainda não entrou"),
  ],
  fornecedores: ["SR Contabilidade", "Kamell Distribuidora", "Dometic do Brasil"],
  escritorio: ESCRITORIO as unknown as DadosDaTarde["escritorio"],
  semResposta: [{ nome: "Giancarlo S.", desde: "10:31" }, { nome: "Miguel", desde: "09:02", acordei: "09:45" }] as unknown as DadosDaTarde["semResposta"],
  pergunta: true,
};

// ─── A sombra e o ponto único ────────────────────────────────────────────────────────────────────

Deno.test("sombra é byte a byte: com o bloco em sombra, os 3 textos são os de antes, com o Secretário vazio e cheio", () => {
  for (const t of TURNOS) {
    for (const extra of [{}, CHEIO]) {
      const antes = textoDaTarde(turno(t, agenda(), extra));
      const sombra = textoDaTarde(turno(t, agenda(bloco({ modo: "sombra" })), extra));
      assertEquals(sombra.texto, antes.texto, t);
      assertEquals(sombra.letras, antes.letras, t);
      assertEquals(sombra.agenda, antes.agenda, t);
    }
  }
  // o controle: o mesmo bloco ligado reprova
  assert(textoDaTarde(turno("fechamento", agenda(bloco()))).texto !== textoDaTarde(turno("fechamento", agenda())).texto);
});

Deno.test("o ponto único: com o bloco ligado, as linhas dele saem nos 3 turnos, no lugar das linhas do plano", () => {
  for (const t of TURNOS) {
    const r = textoDaTarde(turno(t, agenda(bloco())));
    assertStringIncludes(r.texto!, VEREDITO, t);
    assertStringIncludes(r.texto!, DECISAO1, t);
    assertStringIncludes(r.texto!, "Compras: Kamell", t);
    assert(!r.texto!.includes("A LINHA VELHA"), `${t}: a linha velha não sai junto: ${r.texto}`);
    assertEquals(r.agenda?.linhas?.map((x) => x.tipo), ["veredito", "hoje", "mudou", "decisao", "decisao", "decisao", "compras", "outras"], t);
  }
  // sem bloco, as velhas: o caminho de antes
  assertStringIncludes(textoDaTarde(turno("revisao_mes", agenda())).texto!, "A LINHA VELHA");
});

Deno.test("o ponto único: o bloco fica logo depois do 'Amanhã' no fechamento e na revisão da semana, e depois das cobranças na do mês", () => {
  const com = turno("fechamento", agenda(bloco()));
  com.amanha!.itens = [{ hora: "08:00", texto: "Reunião com a marina" }];
  const linhas = textoDaTarde(com).texto!.split("\n");
  assertEquals(linhas.indexOf(VEREDITO), linhas.findIndex((x) => x.startsWith("Amanhã (quarta")) + 1, linhas.join("\n"));
  const rs = turno("revisao_semana", agenda(bloco()));
  rs.amanha!.itens = [{ hora: "08:00", texto: "Reunião com a marina" }];
  const ls = textoDaTarde(rs).texto!.split("\n");
  assertEquals(ls.indexOf(VEREDITO), ls.findIndex((x) => x.startsWith("Quarta (11/11)")) + 1, ls.join("\n"));
  const rm = textoDaTarde(turno("revisao_mes", agenda(bloco()))).texto!;
  assert(rm.indexOf("Nenhuma cobrança vencida") < rm.indexOf(VEREDITO), rm);
});

Deno.test("linhasDoBloco: cada nível é o que o banco disse: nível_entra <= n < nivel_de_corte, com a linha sem corte sempre", () => {
  const b = bloco();
  assertEquals(linhasDoBloco(b, 0).map((x) => x.texto), [VEREDITO, HOJE, MUDOU, DECISAO1, DECISAO2, DECISAO3, "Compras: Kamell: Cerbo de Nelson — compre até qui 12/11.", "Comissão de outubro: R$ 100,00."]);
  assertEquals(linhasDoBloco(b, 1).at(-1)?.texto, "+1 compra (*agenda compras*).");
  assertEquals(linhasDoBloco(b, 2).map((x) => x.tipo), ["veredito", "hoje", "mudou", "decisao", "decisao", "decisao", "compras"]);
  assertEquals(linhasDoBloco(b, 2)[2].texto, "Mudou: mudei 2 coisas (*o que mudou*).");
  assertEquals(linhasDoBloco(b, 3).filter((x) => x.tipo === "decisao").map((x) => x.texto), [DECISAO1, DECISAO2, "(e mais 1 em *agenda pendências*)"]);
  assertEquals(linhasDoBloco(b, 4).filter((x) => x.tipo === "decisao").map((x) => x.texto), [DECISAO1, "(e mais 2 em *agenda pendências*)"]);
  assertEquals(linhasDoBloco(b, 5).map((x) => x.texto), [VEREDITO, DECISAO1]);
  assertEquals(linhasDoBloco(b, 0)[3].veto_ate, "2026-11-11T18:00:00-03:00");
  assertEquals(linhasDoBloco(b, 0)[4].veto_diria, "2026-11-11T18:00:00-03:00");
});

// ─── O "Amanhã" ──────────────────────────────────────────────────────────────────────────────────

Deno.test("Amanhã com o bloco ligado: sai o que é do plano (o veredito diz), ficam a tarefa e o a pagar; em sombra, a linha de sempre", () => {
  const itens = [{ hora: "08:00", texto: "Lenine (OS-00074), dia 3 de 6: Alex", doPlano: true }, { hora: "14:00", texto: "Reunião com a marina" }, { hora: null, texto: "comprar 4 itens da OS-00112", doPlano: true }];
  const d = (b: BlocoDaAgenda | undefined, a: Partial<NonNullable<DadosDaTarde["amanha"]>>) => turno("fechamento", agenda(b), { amanha: { dia: "2026-11-11", itens: [], agenda: agenda(b), ...a } });
  const lig = textoDaTarde(d(bloco(), { itens })).texto!;
  assertStringIncludes(lig, "Amanhã (quarta, 11/11): 14:00 Reunião com a marina.");
  assert(!lig.includes("Lenine (OS-00074), dia 3") && !lig.includes("comprar 4 itens"), lig);
  // em sombra, igual a antes
  assertStringIncludes(textoDaTarde(d(bloco({ modo: "sombra" }), { itens })).texto!, "Amanhã (quarta, 11/11): 08:00 Lenine (OS-00074), dia 3 de 6: Alex; 14:00 Reunião com a marina; comprar 4 itens da OS-00112.");
  // só o que é do plano: a linha some, e a cauda também
  const so = textoDaTarde(d(bloco(), { itens: [itens[0]] })).texto!;
  assert(!so.includes("Amanhã (quarta") && !so.includes("A CAUDA"), so);
  // só o a pagar: a linha fica com ele, sem "nada marcado": o veredito é quem fala do dia
  const pag = textoDaTarde(d(bloco(), { itens: [itens[0]], pagar: { n: 2, total: 350 } })).texto!;
  assertStringIncludes(pag, "Amanhã (quarta, 11/11): a pagar: 2 contas, R$ 350,00.");
  // sem o a pagar, sem nada: nada de "nada marcado" nem de carteira
  const nada = textoDaTarde(d(bloco(), { carteira: { semData: 6 } })).texto!;
  assert(!nada.includes("nada marcado"), nada);
});

Deno.test("a semana que vem (projeção) não sai com o bloco: ele fica no lugar dela, e a cauda não é dita como mostrada", () => {
  const t = textoDaTarde(turno("fechamento", agenda(bloco()), { hoje: "2026-11-12" }));
  assert(!t.texto!.includes("A SEMANA"), t.texto!);
  assertEquals(t.agenda?.semana, 0);
  assertEquals(t.agenda?.cauda, false);
});

// ─── temAlgo ─────────────────────────────────────────────────────────────────────────────────────

Deno.test("temAlgo não muda: bloco só com 'nada mudou' não faz o fechamento sair em dia calado; com algo, ele sai", () => {
  const so = bloco({ linhas: [l("veredito", "Agenda: nada mudou. Amanhã (qua 11/11): Nelson com Roberto.", 0, null)], nada_mudou: true, nivel_min: 3 });
  const calado = textoDaTarde(turno("fechamento", agenda(so), {}));
  assertEquals(calado.texto, null);
  assertEquals(calado.agenda?.linhas, []);
  // o controle: sem o veredito sozinho contar, as linhas velhas contavam: com elas, sai
  assert(textoDaTarde(turno("fechamento", agenda())).texto !== null);
  // o veredito com o Secretário falando: ele vai junto, e o registro é o do que saiu
  const comFornecedor = textoDaTarde(turno("fechamento", agenda(so), { fornecedores: ["Kamell"] }));
  assertStringIncludes(comFornecedor.texto!, "Agenda: nada mudou. Amanhã (qua 11/11): Nelson com Roberto.");
  // o dia com plano continua saindo: a linha Hoje é o que a linha dia era
  const comHoje = bloco({ linhas: [so.linhas[0], l("hoje", HOJE, 0, 3, { pergunta_id: "q-conf" })], nada_mudou: true, nivel_min: 3 });
  assertStringIncludes(textoDaTarde(turno("fechamento", agenda(comHoje))).texto!, HOJE);
  // o item do plano continua contando em temAlgo, mesmo fora do "Amanhã"
  const doPlano = turno("fechamento", agenda(so));
  doPlano.amanha!.itens = [{ hora: "08:00", texto: "Lenine (OS-00074)", doPlano: true }];
  assertStringIncludes(textoDaTarde(doPlano).texto!, "Agenda: nada mudou.");
  // a revisão sai sempre, com o veredito
  assertStringIncludes(textoDaTarde(turno("revisao_semana", agenda(so))).texto!, "Agenda: nada mudou.");
});

// ─── A régua dos 1.000 ───────────────────────────────────────────────────────────────────────────

Deno.test("os 1.000: o bloco cede por dentro, nível a nível, antes de o Secretário perder qualquer coisa", () => {
  // o Secretário cabe: ~620 letras com o bloco de ~520 não cabem, mas o nível acima cabe
  const extra: Partial<DadosDaTarde> = { ...CHEIO, ficaram: CHEIO.ficaram!.slice(0, 1), semResposta: [] };
  const d = turno("fechamento", agenda(bloco()), extra);
  const t = textoDaTarde(d);
  assert(t.texto!.length <= LIMITE_DA_TARDE, String(t.texto!.length));
  assertStringIncludes(t.texto!, VEREDITO);
  assertStringIncludes(t.texto!, DECISAO1);
  assertStringIncludes(t.texto!, "Fornecedores esperando");
  assertStringIncludes(t.texto!, "Escritório:");
  assert(!t.texto!.includes("Comissão de outubro"), `outras cede primeiro: ${t.texto}`);
});

Deno.test("os 1.000: a linha cedida é a do nível: o que saiu do texto não vai ao registro, e o que ficou vai", () => {
  const t = textoDaTarde(turno("fechamento", agenda(bloco()), { ...CHEIO, semResposta: [] }));
  const ids = (t.agenda?.linhas ?? []).map((x) => x.pergunta_id).filter(Boolean);
  for (const id of ids) {
    const texto = LINHAS.find((x) => x.pergunta_id === id)!.texto;
    assertStringIncludes(t.texto!, texto);
  }
  for (const x of LINHAS.filter((y) => y.pergunta_id && !ids.includes(y.pergunta_id))) assert(!t.texto!.includes(x.texto), x.texto);
});

Deno.test("os 1.000: Secretário de ~950 letras: veredito e 1ª decisão ficam nos 3 turnos, com o texto dentro do limite", () => {
  const cheios: Array<[typeof TURNOS[number], Partial<DadosDaTarde>]> = [
    ["fechamento", CHEIO],
    ["revisao_semana", {
      parados: CHEIO.ficaram, semResposta: CHEIO.semResposta,
      panorama: { mes: { mes: "2026-11", receita: 120000, saidas: 80000, pendentes: { n: 12, soma: 8000 } }, vigia: "A margem de outubro caiu para 18%, a menor em 6 meses, puxada pelo custo de material.", semana: { entra: 30000, nEntra: 5, sai: 45000, nSai: 9, ate: "2026-11-15" } },
    }],
    ["revisao_mes", {
      semResposta: CHEIO.semResposta, mesQueFechou: { mes: "2026-10", receita: 120000, saidas: 80000, pendentes: { n: 12, soma: 8000 } }, faturamento: "Quem mais faturou: Lenine R$ 30.000, Nelson R$ 25.000, Vanderlei R$ 20.000.",
      antigas: {
        n: 5, total: 18000, fora: { n: 0, total: 0 },
        linhas: ["A", "B", "C", "D", "E"].map((x) => ficou(x, `${x}: Marcelo Marco Bertoldi e mais 2 orçamentos da mesma embarcação (OS-00038, OS-00041, OS-00052): R$ 16.890,00, venceu 13/10, há 21 dias; sem resposta`)),
      },
    }],
  ];
  for (const [nome, extra] of cheios) {
    const sem = textoDaTarde(turno(nome, null, extra)).texto!;
    assert(sem.length > 900, `${nome}: o Secretário sozinho tem de estar cheio: ${sem.length}`);
    const t = textoDaTarde(turno(nome, agenda(bloco()), extra));
    assertStringIncludes(t.texto!, VEREDITO, nome);
    assertStringIncludes(t.texto!, DECISAO1, nome);
    // a revisão do mês com 5 cobranças e 950 letras não tem o que ceder: as 5 linhas com letra e a frase de como responder são o assunto dela. O bloco fica, e o texto passa um pouco: é o caso do "nem assim"
    assert(t.texto!.length <= (nome === "revisao_mes" ? LIMITE_DA_TARDE + 100 : LIMITE_DA_TARDE), `${nome}: ${t.texto!.length}\n${t.texto}`);
    assert(!t.texto!.endsWith("…"), `${nome}: sem o corte duro`);
    assert((t.agenda?.linhas ?? []).some((x) => x.pergunta_id === "q1"), `${nome}: a 1ª decisão conta como vista`);
    // as letras do que ficou continuam
    for (const x of t.letras) assertStringIncludes(t.texto!, `*${x.letra}.*`, nome);
  }
});

Deno.test("os 1.000: com o espaço aberto pelos extras, o bloco volta ao nível mais cheio que couber, em vez de ficar no mínimo", () => {
  const t = textoDaTarde(turno("fechamento", agenda(bloco()), { ...CHEIO, pergunta: false }));
  assert(!t.texto!.includes("Fornecedores esperando"), "os extras saíram");
  assert((t.agenda?.linhas ?? []).length > 2, `sobra lugar para mais que o mínimo: ${t.texto}`);
});

Deno.test("os 1.000: nunca o corte duro: sem caber nem no mínimo, sai inteiro, acima do limite, com as letras e a decisão de pé", () => {
  // 3 linhas com letra muito longas, sem nenhum extra para tirar: nada mais cede
  const longas = ["A", "B", "C"].map((x) => ({
    ...ficou(x, `${x} ${"cobrança longa ".repeat(30)}`), faco: "te mostro o lembrete pronto de novo com a lista inteira", alternativa: "até a semana que vem, sem falta nenhuma",
  }));
  const guardado = { linhas: [`Não te interrompi com: ${"um assunto muito longo ".repeat(10)}`], escritorio: [], mostrados: [], doEscritorio: [], resolvidos: [], restantes: 0 };
  const d = turno("fechamento", agenda(bloco()), { ficaram: longas, guardado: guardado as unknown as DadosDaTarde["guardado"] });
  const t = textoDaTarde(d);
  assertStringIncludes(t.texto!, VEREDITO);
  assertStringIncludes(t.texto!, DECISAO1);
  assert(!t.texto!.endsWith("…"), t.texto!);
  for (const x of ["A", "B", "C"]) assertStringIncludes(t.texto!, `*${x}.*`);
  assertEquals(linhasDoBloco(bloco(), 5).map((x) => x.texto), (t.agenda?.linhas ?? []).map((x) => x.texto), "o mínimo");
});

Deno.test("os 1.000: a régua conta o que estiver em semOsExtras, sem saber o nome: um extra de teste que só a função tira", () => {
  // As 3 linhas com letra não são extra de verdade: aqui elas fazem o papel do que vier depois (o resumo do retorno está em session/retorno-f2). Sem tirá-las, o texto passa do limite; tirando, cabe, com o mesmo bloco
  const longas = ["A", "B", "C"].map((x) => ({ ...ficou(x, `${x} cobrança`), faco: "te mostro o lembrete pronto ".repeat(9) }));
  const d = turno("fechamento", agenda(bloco()), { ficaram: longas, fornecedores: ["Kamell"] });
  const sem = textoDaTarde(d);
  assert(sem.texto!.length > LIMITE_DA_TARDE, `a função de sempre não sabe desse extra: ${sem.texto!.length}`);
  const tiraOExtra = (x: DadosDaTarde): DadosDaTarde => ({ ...x, ficaram: [] });
  const com = textoDaTarde(d, tiraOExtra);
  assert(com.texto!.length <= LIMITE_DA_TARDE, `${com.texto!.length}`);
  assert(!com.texto!.includes("*A.*"), com.texto!);
  assertStringIncludes(com.texto!, VEREDITO);
  assertStringIncludes(com.texto!, DECISAO1);
  // e ela usa a sobra: o bloco inteiro, no nível 0
  assertStringIncludes(com.texto!, "Comissão de outubro");
});

Deno.test("o nível do banco é o piso: o que não coube em bloco_max_chars não volta porque o Secretário está vazio", () => {
  const t = textoDaTarde(turno("fechamento", agenda(bloco({ nivel: 4 }))));
  assertEquals((t.agenda?.linhas ?? []).filter((x) => x.tipo === "decisao").map((x) => x.texto), [DECISAO1, "(e mais 2 em *agenda pendências*)"]);
});

Deno.test("os 1.000: antes de o bloco ceder mais um nível, o Secretário encurta as linhas dele", () => {
  const longas = ["A", "B"].map((x) => ficou(x, `${x} Marcelo Marco Bertoldi e mais 2 orçamentos da mesma embarcação (OS-00038, OS-00041, OS-00052): R$ 16.890,00, venceu 13/10`));
  const t = textoDaTarde(turno("fechamento", agenda(bloco({ nivel: 3 })), { ficaram: longas }));
  assert(t.texto!.length <= LIMITE_DA_TARDE, String(t.texto!.length));
  assertStringIncludes(t.texto!, DECISAO2, "o nível que coube com o Secretário curto");
  assert(t.texto!.includes("OS-0004…") || t.texto!.includes("…."), `as linhas com letra encurtaram: ${t.texto}`);
});

Deno.test("o registro das linhas do bloco não depende de haver linhas de antes: a agenda sem linhas ainda registra o que o bloco mostrou, nos 3 turnos", () => {
  const { linhas: _l, ...semLinhas } = agenda(bloco());
  for (const t of TURNOS) {
    const r = textoDaTarde(turno(t, semLinhas as AgendaDoFechamento));
    assert((r.agenda?.linhas ?? []).some((x) => x.pergunta_id === "q1"), `${t}: ${JSON.stringify(r.agenda)}`);
  }
});

// ─── A leitura ───────────────────────────────────────────────────────────────────────────────────

const CRU = {
  modo: "ligado", nivel: 1, nivel_min: 3, chars: 400, nada_mudou: false, incompleto: false,
  linhas: [
    { parte: "veredito", texto: "Agenda: nada mudou.", pergunta_id: null, pergunta_ids: [], acao_ids: [], veto_ate: null, nivel_entra: 0, nivel_de_corte: null },
    { parte: "decisao", texto: "·  Decisão 1:\n isto", pergunta_id: "q", pergunta_ids: ["q", 7], acao_ids: ["a", null], veto_ate: "2026-11-11T18:00:00-03:00", veto_diria: "2026-11-12T18:00:00-03:00", nivel_entra: 0, nivel_de_corte: 3 },
  ],
};

Deno.test("a coleta: o bloco conferido; a linha fora da forma tira o bloco inteiro, nunca pela metade", () => {
  const b = blocoDaAgenda(CRU)!;
  assertEquals(b.nivel, 1);
  assertEquals(b.linhas[1], {
    parte: "decisao", texto: "· Decisão 1: isto", pergunta_id: "q", pergunta_ids: ["q"], acao_ids: ["a"], veto_ate: "2026-11-11T18:00:00-03:00", veto_diria: "2026-11-12T18:00:00-03:00",
    nivel_entra: 0, nivel_de_corte: 3,
  });
  assertEquals(b.linhas[0].pergunta_ids, undefined);
  assertEquals(b.linhas[0].veto_ate, undefined);
  for (const v of [
    undefined, null, {}, { modo: "desligado" }, { ...CRU, modo: "outro" }, { ...CRU, linhas: "x" }, { ...CRU, nivel: 4 }, { ...CRU, nivel: -1 }, { ...CRU, nivel: "1" === "1" ? 1.5 : 0 }, { ...CRU, nivel_min: null },
    { ...CRU, linhas: [] }, { ...CRU, linhas: [CRU.linhas[1]] },
    { ...CRU, linhas: [CRU.linhas[0], { ...CRU.linhas[1], parte: "nova" }] },
    { ...CRU, linhas: [CRU.linhas[0], { ...CRU.linhas[1], texto: "" }] },
    { ...CRU, linhas: [CRU.linhas[0], { ...CRU.linhas[1], texto: "x".repeat(801) }] },
    { ...CRU, linhas: [CRU.linhas[0], { ...CRU.linhas[1], nivel_entra: "0" }] },
    { ...CRU, linhas: [CRU.linhas[0], { ...CRU.linhas[1], nivel_de_corte: undefined }] },
  ]) assertEquals(blocoDaAgenda(v), null, JSON.stringify(v)?.slice(0, 80));
});

Deno.test("a coleta: agendaDoFechamento repassa o bloco só quando ele veio; sem a chave, a saída de antes", () => {
  const base = { modo: "ligado", cauda_amanha: null, semana_que_vem: [], linhas: [] };
  assertEquals(agendaDoFechamento(base), { modo: "ligado", cauda: null, semana: [] });
  assertEquals(agendaDoFechamento({ ...base, bloco: { modo: "desligado" } }), { modo: "ligado", cauda: null, semana: [] });
  assertEquals(agendaDoFechamento({ ...base, bloco: CRU })?.bloco?.nivel, 1);
  assertEquals(blocoLigado(agendaDoFechamento({ ...base, bloco: { ...CRU, modo: "sombra" } })), null);
  assert(blocoLigado(agendaDoFechamento({ ...base, bloco: CRU })) !== null);
});

function adminComBloco(bloco: unknown) {
  const logs: Array<Record<string, unknown>> = [];
  const admin = {
    rpc: (nome: string, args: Record<string, unknown>) => {
      if (nome === "agenda_textos_do_fechamento") return Promise.resolve({ data: { modo: "ligado", cauda_amanha: null, semana_que_vem: [], linhas: [], ...(bloco ? { bloco } : {}) }, error: null });
      logs.push({ nome, ...args });
      return Promise.resolve({ data: null, error: null });
    },
    from: () => ({ insert: (l: Record<string, unknown>) => (logs.push(l), Promise.resolve({ data: null, error: null })) }),
  };
  return { admin, logs };
}

Deno.test("a coleta: bloco incompleto ou fora da forma fica registrado, e o fechamento segue; bloco inteiro, desligado ou em sombra sem erro não registra nada", async () => {
  const inc = adminComBloco({ ...CRU, incompleto: true });
  const r = await lerAgendaDoFechamento(inc.admin, "2026-11-10", "2026-11-11");
  assertEquals(r?.bloco?.incompleto, true);
  assert(JSON.stringify(inc.logs).includes("tarde:bloco"), JSON.stringify(inc.logs));
  const fora = adminComBloco({ ...CRU, linhas: [{ parte: "nova" }] });
  assertEquals((await lerAgendaDoFechamento(fora.admin, "2026-11-10", "2026-11-11"))?.bloco, undefined);
  assert(JSON.stringify(fora.logs).includes("fora da forma"), JSON.stringify(fora.logs));
  for (const b of [CRU, { ...CRU, modo: "sombra" }, { modo: "desligado" }, null]) {
    const ok = adminComBloco(b);
    await lerAgendaDoFechamento(ok.admin, "2026-11-10", "2026-11-11");
    assertEquals(ok.logs, [], JSON.stringify(b));
  }
});

Deno.test("a frase de falha do banco passa como veredito: 'nada mudou' nunca sai de uma leitura incompleta aqui", () => {
  const FALHA = "Agenda: não consegui ler a agenda inteira agora; *agenda* mostra o que está marcado.";
  const t = textoDaTarde(turno("fechamento", agenda(bloco({ incompleto: true, linhas: [l("veredito", FALHA, 0, null), LINHAS[4]], nivel_min: 3 }))));
  assertStringIncludes(t.texto!, FALHA);
  assert(!t.texto!.includes("nada mudou"), t.texto!);
});

// ─── As listas fechadas ──────────────────────────────────────────────────────────────────────────

Deno.test("as listas fechadas: tipo novo em TIPOS_DE_LINHA_DA_AGENDA precisa de destino em _agenda_bloco_destino (L4d de agenda_fase7f_bloco.sql); as partes não se misturam com os tipos", () => {
  assertEquals([...TIPOS_DE_LINHA_DA_AGENDA].sort(), ["cliente", "comissao", "compras", "conclusao", "decisao", "dia", "diaria", "gestor", "mudancas", "pergunta", "ppc", "semana"]);
  assertEquals([...PARTES_DO_BLOCO], ["veredito", "hoje", "mudou", "semana", "decisao", "compras", "outras"]);
});
