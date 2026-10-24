// O texto da tarde (secretário, Passo 3): o formato aprovado, o "só se houver algo", a estimativa do escritório,
// a pergunta da sexta, o tamanho e as palavras proibidas.
import { assert, assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import type { LinhaComLetra } from "./secretario-tarde-regras.ts";
import { REGRAS } from "./secretario-candidatos.ts";
import {
  type AgendaDoFechamento,
  amanhaComAAgenda,
  type DadosDaTarde,
  LIMITE_DA_TARDE,
  semanaCabe,
  linhaDaSemana,
  linhasDaAgendaQueCabem,
  linhaDeAmanha,
  linhaSemResposta,
  linhaDoEscritorio,
  linhaDoMesAteAqui,
  linhaDoMesQueFechou,
  linhaDoVigia,
  minutosDoEscritorio,
  PERGUNTA_DA_SEMANA,
  proximaRevisaoDaSemana,
  textoDaTarde,
} from "./secretario-tarde-texto.ts";

const ESCRITORIO = { propostas: { saidas: 46, entradas: 4, transferencias: 0, outras: 0 }, alertas: 15, regras: 103, debitosSemLoja: 6, entradas: { doMes: 4, sinais: 2, antigas: 6 } };

function linha(letra: string, texto: string, extra: Partial<LinhaComLetra> = {}): LinhaComLetra {
  return {
    letra, parte: "ficou", referencia: `ref:${letra}`, tipo: "cobranca_grande", texto, faco: "te mostro o lembrete pronto",
    alternativa: "até segunda", comandoAlternativo: "espera", valor: 100, desde: "2026-10-13", ...extra,
  };
}

function dados(extra: Partial<DadosDaTarde> = {}): DadosDaTarde {
  return {
    hoje: "2026-10-15", turno: "fechamento", ficaram: [], amanha: { dia: "2026-10-16", itens: [] }, fornecedores: [], escritorio: ESCRITORIO,
    parados: [], panorama: null, antigas: null, mesQueFechou: null, faturamento: null, pergunta: false, ...extra,
  };
}

const PROIBIDAS = /concilia|pend[eê]ncia|ferramenta/i;
const EMOJI = /\p{Extended_Pictographic}/u;

Deno.test("fechamento: abertura, itens com a letra da manhã e a resposta, amanhã, fornecedores e escritório", () => {
  const t = textoDaTarde(dados({
    ficaram: [
      linha("B", "2 orçamentos montados, não enviados (R$ 141 mil): ORÇ-00117, ORÇ-00118", { tipo: "orcamento_nao_enviado", faco: "te mostro a lista" }),
      linha("C", "Marcelo B. (OS-00038): R$ 16.890,00, venceu 13/10 (2 dias); ainda não entrou"),
    ],
    fornecedores: ["SR Contabilidade"],
  })).texto!;
  assertEquals(t.split("\n"), [
    "Fechamento de quinta, 15/10. Ficaram 2 de hoje; sem resposta, vão para a revisão de segunda.",
    "",
    "*B.* 2 orçamentos montados, não enviados (R$ 141 mil): ORÇ-00117, ORÇ-00118. *B* = te mostro a lista · *B espera* = até segunda",
    "*C.* Marcelo B. (OS-00038): R$ 16.890,00, venceu 13/10 (2 dias); ainda não entrou. *C* = te mostro o lembrete pronto · *C espera* = até segunda",
    "",
    // (23/10/2026) o dados() padrão não traz a carteira: sem ela lida, não se afirma "livre"
    "Amanhã (sexta, 16/10): nada marcado.",
    "Fornecedores esperando há mais de 1 dia: SR Contabilidade.",
    "Escritório: 46 despesas e 4 entradas para conferir, 15 alertas, 6 débitos sem loja; uns 30 min. *escritório*",
  ]);
  assert(t.length <= 900, `${t.length}`);
  assert(!PROIBIDAS.test(t) && !EMOJI.test(t));
});

Deno.test("fechamento: só se houver algo — o escritório sozinho não manda mensagem; a pergunta da sexta manda", () => {
  assertEquals(textoDaTarde(dados()).texto, null);
  // a carteira lida e sem OS sem data: aí sim "agenda livre"
  const sexta = textoDaTarde(dados({ hoje: "2026-10-16", amanha: { dia: "2026-10-17", itens: [], carteira: { semData: 0 } }, pergunta: true })).texto!;
  assertStringIncludes(sexta, "Fechamento de sexta, 16/10: nada ficou de hoje.");
  assertStringIncludes(sexta, "Amanhã (sábado, 17/10): agenda livre.");
  assert(sexta.endsWith(PERGUNTA_DA_SEMANA));
  // amanhã com compromisso já é "algo"
  const comAgenda = textoDaTarde(dados({ amanha: { dia: "2026-10-16", itens: [{ hora: "08:00", texto: "OS-00112 (Santo Inácio 7.8)" }, { hora: null, texto: "comprar 4 itens da OS-00112 (marcada para 16/10)" }] } })).texto!;
  assertStringIncludes(comAgenda, "Amanhã (sexta, 16/10): 08:00 OS-00112 (Santo Inácio 7.8); comprar 4 itens da OS-00112 (marcada para 16/10).");
});

Deno.test("fechamento: a revisão seguinte pelo calendário (feriado na segunda empurra o nome)", () => {
  assertEquals(proximaRevisaoDaSemana("2026-10-15"), "segunda");
  assertEquals(proximaRevisaoDaSemana("2026-10-30"), "quarta (04/11)"); // 02/11 Finados, 03/11 revisão do mês
  assertEquals(proximaRevisaoDaSemana("2026-10-08"), "terça (13/10)"); // 12/10 feriado
  const t = textoDaTarde(dados({ hoje: "2026-10-08", amanha: { dia: "2026-10-09", itens: [] }, ficaram: [linha("A", "x")] })).texto!;
  assertStringIncludes(t, "Ficou 1 de hoje; sem resposta, vai para a revisão de terça (13/10).");
});

Deno.test("escritório: 20 s por lançamento ou alerta, 1 min por débito sem loja, de 5 em 5 (o exemplo aprovado dá 25)", () => {
  assertEquals(minutosDoEscritorio({ ...ESCRITORIO, propostas: { saidas: 46, entradas: 0, transferencias: 0, outras: 0 } }), 25);
  assertEquals(minutosDoEscritorio({ propostas: null, alertas: null, regras: 103, debitosSemLoja: null, entradas: null }), 0);
  assertEquals(minutosDoEscritorio({ propostas: { saidas: 1, entradas: 0, transferencias: 0, outras: 0 }, alertas: 0, regras: 0, debitosSemLoja: 0, entradas: null }), 5);
  assertEquals(linhaDoEscritorio({ propostas: null, alertas: 0, regras: 103, debitosSemLoja: 0, entradas: null }), null);
  assertEquals(linhaDoEscritorio(null), null);
});

Deno.test("revisão da semana: parados com a letra do dia, como responder de uma vez e o panorama", () => {
  const ps = [
    linha("C", "Marcelo B. (OS-00038): R$ 16.890,00, venceu 13/10 (6 dias)", { parte: "parado" }),
    linha("G", "ORÇ-00095 MP MOTOR HOMES (Industrailer Scania), R$ 14.461,00: aprovado, sinal não veio desde 06/10", { parte: "parado" }),
    linha("Q", "OS-00069 Vanderlei A. (Santo Inácio 6.9): parada desde 03/10", { parte: "parado" }),
  ];
  const t = textoDaTarde(dados({
    hoje: "2026-10-19", turno: "revisao_semana", parados: ps, amanha: null, escritorio: null,
    panorama: {
      mes: { mes: "2026-10", receita: 38729, saidas: 2284, pendentes: { n: 27, soma: 16094.84 } },
      vigia: "⚠️ *set/26* faturou R$ 21.000,00, abaixo dos R$ 30.000,00 que a HBR precisa por mês.",
      semana: { entra: 5237.99, nEntra: 1, sai: 785.07, nSai: 1, ate: "2026-10-25" },
    },
  })).texto!;
  const l = t.split("\n");
  assertEquals(l[0], "Revisão da semana, segunda, 19/10. 3 assuntos parados.");
  assertEquals(l.slice(2, 5), ps.map((p) => `*${p.letra}.* ${p.texto}`));
  assertStringIncludes(t, "Responda tudo numa mensagem, ex.: *C semana, G tira, Q 15 dias* (semana = faço esta semana; 15 dias = lembro depois). As letras valem até meia-noite.");
  assertStringIncludes(t, "Mês até aqui: receita R$ 38.729; custos e despesas R$ 18.379, com R$ 16.095 ainda para conferir; resultado perto de R$ 20.350.");
  assertStringIncludes(t, "Vigia: set/26 faturou R$ 21.000,00, abaixo dos R$ 30.000,00 que a HBR precisa por mês.");
  assertStringIncludes(t, "Semana até domingo (25/10): a receber R$ 5.238 (1 cobrança); a pagar R$ 785 (1 conta).");
  assert(t.length <= LIMITE_DA_TARDE && !EMOJI.test(t) && !PROIBIDAS.test(t), t);
});

Deno.test("revisão do mês: o mês que fechou, quem mais faturou e as cobranças de 30+ dias, uma por vez", () => {
  const t = textoDaTarde(dados({
    hoje: "2026-11-03", turno: "revisao_mes", amanha: null, escritorio: null,
    mesQueFechou: { mes: "2026-10", receita: 52000, saidas: 9000, pendentes: { n: 3, soma: 1200 } },
    faturamento: "Quem mais faturou: Marcelo 44% · Nelson 27% · Giancarlo 15%",
    antigas: {
      n: 3, total: 2426, fora: { n: 0, total: 0 },
      linhas: [
        linha("G", "MP MOTOR HOMES: R$ 1.670,00 em 2 cobranças; a mais antiga venceu 22/07 (104 dias)", { parte: "antiga" }),
        linha("F", "Lírio (OS-00047): R$ 756,00, venceu 22/07 (104 dias)", { parte: "antiga" }),
      ],
    },
  })).texto!;
  const l = t.split("\n");
  assertEquals(l[0], "Revisão do mês, terça, 03/11. Outubro fechou: receita R$ 52.000; custos e despesas R$ 10.200 (3 despesas de outubro ainda para conferir, R$ 1.200); resultado perto de R$ 41.800.");
  assertEquals(l[1], "Quem mais faturou: Marcelo 44% · Nelson 27% · Giancarlo 15%");
  assertStringIncludes(t, "3 cobranças vencidas há 30 dias ou mais, R$ 2.426,00. Cobrar, negociar ou dar baixa?");
  assertStringIncludes(t, "*G.* MP MOTOR HOMES: R$ 1.670,00 em 2 cobranças");
  assertStringIncludes(t, "Responda uma por vez: *G cobrar*, *G negociar* ou *G baixa*");
  const sem = textoDaTarde(dados({ hoje: "2026-11-03", turno: "revisao_mes", antigas: { n: 0, total: 0, fora: { n: 0, total: 0 }, linhas: [] } })).texto!;
  assertStringIncludes(sem, "Nenhuma cobrança vencida há 30 dias ou mais.");
});

Deno.test("linhas do panorama: sem fila, sem 'perto de'; prejuízo; semana sem entrada; vigia sem nada some", () => {
  assertEquals(linhaDoMesAteAqui({ mes: "2026-10", receita: 1000, saidas: 400, pendentes: { n: 0, soma: 0 } }),
    "Mês até aqui: receita R$ 1.000; custos e despesas R$ 400; resultado R$ 600.");
  assertEquals(linhaDoMesQueFechou({ mes: "2026-09", receita: 1000, saidas: 400, pendentes: { n: 0, soma: 0 } }),
    "Setembro fechou: receita R$ 1.000; custos e despesas R$ 400; resultado R$ 600.");
  // o setembro real de 01/10/2026 (ensaio): negativo vira "prejuízo", sem sinal de menos
  assertEquals(linhaDoMesQueFechou({ mes: "2026-09", receita: 6239, saidas: 9150.68, pendentes: { n: 2, soma: 235.8 } }),
    "Setembro fechou: receita R$ 6.239; custos e despesas R$ 9.386 (2 despesas de setembro ainda para conferir, R$ 236); prejuízo perto de R$ 3.147.");
  assertEquals(linhaDoMesAteAqui({ mes: "2026-10", receita: 100, saidas: 400, pendentes: { n: 0, soma: 0 } }),
    "Mês até aqui: receita R$ 100; custos e despesas R$ 400; prejuízo de R$ 300.");
  assertEquals(linhaDaSemana({ entra: 0, nEntra: 0, sai: 785.07, nSai: 1, ate: "2026-10-25" }),
    "Semana até domingo (25/10): a receber nada; a pagar R$ 785 (1 conta) — sai mais do que entra.");
  assertEquals(linhaDoVigia(null), null);
  assertEquals(linhaDoVigia("✅ "), null);
});

Deno.test("revisão da semana: mostra até 5 e conta o resto (o que vale 0 não some sem aviso)", () => {
  const ps = ["C", "D", "F", "G", "H", "J", "K"].map((l, i) => linha(l, `assunto ${l}`, { parte: "parado", valor: 100 - i }));
  const t = textoDaTarde(dados({ hoje: "2026-10-19", turno: "revisao_semana", parados: ps, amanha: null, escritorio: null })).texto!;
  assertStringIncludes(t, "Revisão da semana, segunda, 19/10. 7 assuntos parados.");
  assertStringIncludes(t, "*H.* assunto H\n…e mais 2 na *lista*.");
  assert(!t.includes("*J.*") && !t.includes("*K.*"));
  assertEquals(textoDaTarde(dados({ hoje: "2026-10-19", turno: "revisao_semana", parados: ps, amanha: null, escritorio: null })).letras.length, 5);
});

Deno.test("o corte duro de 1.000 caracteres: as linhas encurtam primeiro", () => {
  const longo = "x".repeat(300);
  const t = textoDaTarde(dados({
    hoje: "2026-10-19", turno: "revisao_semana", amanha: null, escritorio: null,
    parados: ["C", "D", "F", "G", "H"].map((l) => linha(l, `${l} ${longo}`, { parte: "parado" })),
    panorama: { mes: { mes: "2026-10", receita: 1, saidas: 1, pendentes: { n: 0, soma: 0 } }, vigia: longo, semana: null },
  })).texto!;
  assert(t.length <= LIMITE_DA_TARDE, `${t.length}`);
  assertStringIncludes(t, "As letras valem até meia-noite.");
});

// ─── (16/10/2026) F1, F3, o guardado e o escritório do portão ───────────────────────────────────
Deno.test("F3: o 'Amanhã' traz a conta a pagar (quantas e o total) e ela sozinha já é 'algo'", () => {
  assertEquals(linhaDeAmanha("2026-10-15", { dia: "2026-10-16", itens: [], pagar: { n: 1, total: 785.07 }, carteira: { semData: 0 } }),
    "Amanhã (sexta, 16/10): agenda livre; a pagar: 1 conta, R$ 785,07.");
  assertEquals(linhaDeAmanha("2026-10-15", { dia: "2026-10-16", itens: [], pagar: { n: 1, total: 785.07 }, carteira: { semData: 6 } }),
    "Amanhã (sexta, 16/10): nada marcado; 6 OS ativas sem data (ou com a data vencida); a pagar: 1 conta, R$ 785,07.");
  assertEquals(linhaDeAmanha("2026-10-15", { dia: "2026-10-16", itens: [{ hora: "08:00", texto: "OS-00112 (Santo Inácio 7.8)" }], pagar: { n: 2, total: 1234 } }),
    "Amanhã (sexta, 16/10): 08:00 OS-00112 (Santo Inácio 7.8); a pagar: 2 contas, R$ 1.234,00.");
  assertEquals(linhaDeAmanha("2026-10-15", { dia: "2026-10-16", itens: [], pagar: { n: 0, total: 0 }, carteira: { semData: 0 } }), "Amanhã (sexta, 16/10): agenda livre.");
  // (23/10/2026) sem a carteira lida não se afirma "livre"
  assertEquals(linhaDeAmanha("2026-10-15", { dia: "2026-10-16", itens: [] }), "Amanhã (sexta, 16/10): nada marcado.", "sem ler a carteira = nada marcado");
  const t = textoDaTarde(dados({ amanha: { dia: "2026-10-16", itens: [], pagar: { n: 1, total: 785.07 } } }));
  assert(t.texto, "a conta de amanhã tira o dia do calado");
  assertEquals(textoDaTarde(dados()).texto, null, "sem nada, calado como antes");
});

Deno.test("F1: 'Sem resposta desde hoje' com até N nomes, o acorde do portão e 'e mais N'; conta como algo", () => {
  const lista = [
    { phone: "1", nome: "Miguel", desde: "09:02", acordei: "09:45" },
    { phone: "2", nome: "Giancarlo S.", desde: "10:31", acordei: null },
    { phone: "3", nome: "Jorge G.", desde: "11:00", acordei: null },
  ];
  assertEquals(linhaSemResposta(lista), "Sem resposta desde hoje: Miguel (09:02, acordei às 09:45); Giancarlo S. (10:31) e mais 1.");
  assertEquals(linhaSemResposta(lista, 3), "Sem resposta desde hoje: Miguel (09:02, acordei às 09:45); Giancarlo S. (10:31); Jorge G. (11:00).");
  assertEquals(linhaSemResposta([]), null);
  const t = textoDaTarde(dados({ semResposta: [lista[1]] }))!;
  assertEquals(t.texto, [
    "Fechamento de quinta, 15/10: nada ficou de hoje.",
    "Sem resposta desde hoje: Giancarlo S. (10:31).",
    "",
    "Amanhã (sexta, 16/10): nada marcado.",
    "Escritório: 46 despesas e 4 entradas para conferir, 15 alertas, 6 débitos sem loja; uns 30 min. *escritório*",
  ].join("\n"));
  assert(!PROIBIDAS.test(t.texto!) && !EMOJI.test(t.texto!));
});

Deno.test("guardado: 'Não te interrompi com' no topo; o do escritório na linha dele (sem mudar os minutos)", () => {
  const plano = {
    linhas: ['promessa sua a Eng. Rafael B. (Dometic): "Claro, te passo agora!"'], escritorio: ["o saldo do banco C6 não bate com o sistema (R$ 12,30 de diferença)"],
    mostrados: ["a"], doEscritorio: ["b"], resolvidos: [], restantes: 0,
  };
  const t = textoDaTarde(dados({ guardado: plano }));
  assertEquals(t.texto, [
    "Fechamento de quinta, 15/10: nada ficou de hoje.",
    'Não te interrompi com: promessa sua a Eng. Rafael B. (Dometic): "Claro, te passo agora!".',
    "",
    "Amanhã (sexta, 16/10): nada marcado.",
    "Escritório: 46 despesas e 4 entradas para conferir, 15 alertas, 6 débitos sem loja, e o saldo do banco C6 não bate com o sistema (R$ 12,30 de diferença); uns 30 min. *escritório*",
  ].join("\n"));
  // só o escritório guardado: continua calado (a papelada sozinha não dispara a mensagem)
  assertEquals(textoDaTarde(dados({ guardado: { ...plano, linhas: [], mostrados: [] } })).texto, null);
  assertEquals(linhaDoEscritorio(null, ["o saldo do banco C6 não bate"]), "Escritório: o saldo do banco C6 não bate. *escritório*");
  assertEquals(linhaDoEscritorio(ESCRITORIO), "Escritório: 46 despesas e 4 entradas para conferir, 15 alertas, 6 débitos sem loja; uns 30 min. *escritório*", "sem guardado = como antes");
  // revisão da semana e do mês também levam o topo
  const rs = textoDaTarde(dados({ turno: "revisao_semana", guardado: plano, semResposta: [{ phone: "2", nome: "Giancarlo S.", desde: "10:31", acordei: null }] }));
  assert(rs.texto!.startsWith('Revisão da semana, quinta, 15/10. Nada parado.\nNão te interrompi com: promessa sua'), rs.texto!);
  assertStringIncludes(rs.texto!, "Sem resposta desde hoje: Giancarlo S. (10:31).");
});

// (16/10/2026, correção do coordenador) A revisão de segunda também traz o "Amanhã" (com o a pagar do F3).
Deno.test("revisão da semana: a linha 'Amanhã' (a terça) com o a pagar, antes do panorama", () => {
  const t = textoDaTarde(dados({
    // (23/10/2026) com a carteira de 23/10: 6 OS ativas sem data (ou com a data vencida)
    hoje: "2026-10-19", turno: "revisao_semana", amanha: { dia: "2026-10-20", itens: [], pagar: { n: 1, total: 785.07 }, carteira: { semData: 6 } },
    panorama: { mes: null, vigia: null, semana: { entra: 0, nEntra: 0, sai: 785.07, nSai: 1, ate: "2026-10-25" } },
  }));
  assertEquals(t.texto, [
    "Revisão da semana, segunda, 19/10. Nada parado.",
    "",
    "Amanhã (terça, 20/10): nada marcado; 6 OS ativas sem data (ou com a data vencida); a pagar: 1 conta, R$ 785,07.",
    "Semana até domingo (25/10): a receber nada; a pagar R$ 785 (1 conta) — sai mais do que entra.",
  ].join("\n"));
  // sem a leitura do "Amanhã" (null), a revisão é a de antes
  const sem = textoDaTarde(dados({ hoje: "2026-10-19", turno: "revisao_semana", amanha: null, panorama: null }));
  assertEquals(sem.texto, "Revisão da semana, segunda, 19/10. Nada parado.");
});

// ─── (23/10/2026) D11b: "agenda livre" só com a carteira lida e sem OS sem data ─────────────────────
// Até 23/10 o "Amanhã" dizia "agenda livre" sempre que nada estava marcado — e havia 6 OS ativas sem data (ou com a data vencida).
Deno.test("D11b: nada marcado amanhã — 'agenda livre' só com a carteira lida e vazia; com OS sem data, quantas", () => {
  const amanha = (carteira: { semData: number } | null | undefined) => linhaDeAmanha("2026-10-22", { dia: "2026-10-23", itens: [], carteira });
  assertEquals(amanha({ semData: 6 }), "Amanhã (sexta, 23/10): nada marcado; 6 OS ativas sem data (ou com a data vencida).");
  assertEquals(amanha({ semData: 1 }), "Amanhã (sexta, 23/10): nada marcado; 1 OS ativa sem data (ou com a data vencida).");
  // (revisão de 23/10/2026) osSemData conta OS ativa de qualquer status, com data vencida inclusive: "aprovada" não é
  // o que ela conta (a OS-00104 aguarda peças e tem data; as OS-00069/74/100 estão abertas).
  assert(!amanha({ semData: 6 }).includes("aprovad"), amanha({ semData: 6 }));
  assertEquals(amanha({ semData: 0 }), "Amanhã (sexta, 23/10): agenda livre.");
  assertEquals(amanha(null), "Amanhã (sexta, 23/10): nada marcado.");
  assertEquals(amanha(undefined), "Amanhã (sexta, 23/10): nada marcado.");
  // com algo marcado, a carteira não entra na linha
  assertEquals(linhaDeAmanha("2026-10-22", { dia: "2026-10-23", itens: [{ hora: null, texto: "OS-00112 (Santo Inácio 7.8), em curso desde 13/10" }], carteira: { semData: 6 } }),
    "Amanhã (sexta, 23/10): OS-00112 (Santo Inácio 7.8), em curso desde 13/10.");
});

Deno.test("D11b: a carteira sem data sozinha não tira o fechamento do calado; na mensagem longa, cabe no corte de 1.000", () => {
  assertEquals(textoDaTarde(dados({ amanha: { dia: "2026-10-16", itens: [], carteira: { semData: 6 } } })).texto, null);
  const longo = "y".repeat(300);
  const t = textoDaTarde(dados({
    ficaram: ["B", "C", "D"].map((l) => linha(l, `${l} ${longo}`)),
    amanha: { dia: "2026-10-16", itens: [], pagar: { n: 2, total: 1234 }, carteira: { semData: 6 } },
    fornecedores: ["SR Contabilidade", "Kamell", "Dometic"],
    pergunta: true,
  })).texto!;
  assert(t.length <= LIMITE_DA_TARDE, `${t.length}`);
  assertStringIncludes(t, "Amanhã (sexta, 16/10): nada marcado; 6 OS ativas sem data (ou com a data vencida); a pagar: 2 contas, R$ 1.234,00.");
  assert(!t.includes("agenda livre"));
});

// ─── (24/10/2026) Agenda de Produção, Fase 1 (P6): a agenda no fechamento ──────────────────────────────────────────
// O que se protege: sem a agenda, ou com ela em sombra (como nasce), o texto é o de antes BYTE A BYTE; ligada, a cauda
// do "Amanhã" vem dela e, na quinta, até 3 linhas da semana que vem logo depois, só com vaga (menos de REGRAS.maxManha
// que ficaram) — ela é a primeira a ceder no corte de 1.000; a cauda sozinha não tira o dia do calado, a semana sim.
// Os textos são os do banco de verdade (supabase/tests/agenda_fase1_leituras.sql, A8/A8b, fechamento de qui 22/10).
const CAUDA = "nada marcado; nenhum serviço pronto, 7 esperando você (*agenda*)";
const SEMANA = [
  "Semana que vem (projeção): nada marcado; 7 serviços na fila, uns 17 a 32 dias de equipe (~5,4 por semana, sem contar você).",
  "Nenhum pronto para começar; o que falta de você está em *agenda*.",
  "Livre de verdade: no melhor caso a partir de ter 17/11; no realista, só a partir de ter 08/12.",
];
const agenda = (modo: "sombra" | "ligado", extra: Partial<AgendaDoFechamento> = {}): AgendaDoFechamento => ({ modo, cauda: CAUDA, semana: SEMANA, ...extra });
/** O fechamento de qui 22/10 (dia do plano), com a carteira de 23/10 e um fornecedor esperando (a tarde tem o que dizer). */
function quinta(extra: Partial<DadosDaTarde> = {}, ag?: AgendaDoFechamento | null): DadosDaTarde {
  const d = dados({ hoje: "2026-10-22", fornecedores: ["SR Contabilidade"], amanha: { dia: "2026-10-23", itens: [], carteira: { semData: 6 } }, ...extra });
  if (ag !== undefined && d.amanha) d.amanha = { ...d.amanha, agenda: ag };
  return d;
}

Deno.test("agenda: sem ela ou em sombra, o fechamento é o de antes byte a byte (com e sem letra, na quinta e fora dela)", () => {
  const cenarios: Array<Partial<DadosDaTarde>> = [
    {},
    { ficaram: [linha("B", "2 orçamentos montados, não enviados (R$ 141 mil)")] },
    { ficaram: ["B", "C", "D"].map((l) => linha(l, `${l} cobrança`)) },
    { hoje: "2026-10-23", amanha: { dia: "2026-10-24", itens: [], carteira: { semData: 6 } } },
    { fornecedores: [] }, // calado
    { pergunta: true, amanha: { dia: "2026-10-23", itens: [], pagar: { n: 1, total: 312.4 }, carteira: { semData: 6 } } },
  ];
  for (const c of cenarios) {
    const antes = textoDaTarde(quinta(c));
    for (const ag of [null, agenda("sombra"), agenda("sombra", { cauda: null }), agenda("sombra", { semana: [] })]) {
      const t = textoDaTarde(quinta(c, ag));
      assertEquals(t.texto, antes.texto, JSON.stringify(c));
      assertEquals(t.letras, antes.letras);
      if (ag) assertEquals(t.agenda, { cauda: false, semana: 0 }, "na sombra nada da agenda é publicado");
    }
  }
  // a revisão da semana (segunda) e a do mês também, byte a byte
  const rs = (ag: AgendaDoFechamento | null) =>
    textoDaTarde(dados({ hoje: "2026-10-19", turno: "revisao_semana", amanha: { dia: "2026-10-20", itens: [], carteira: { semData: 6 }, agenda: ag } })).texto;
  assertEquals(rs(agenda("sombra")), rs(null));
  assertEquals(textoDaTarde(dados({ hoje: "2026-11-03", turno: "revisao_mes", amanha: null })).agenda, undefined);
});

Deno.test("agenda ligada: a cauda substitui o 'nada marcado; N OS…' do Amanhã; com compromisso no dia ou cauda null, o de antes", () => {
  assertEquals(linhaDeAmanha("2026-10-22", { dia: "2026-10-23", itens: [], carteira: { semData: 6 }, agenda: agenda("ligado") }),
    `Amanhã (sexta, 23/10): ${CAUDA}.`);
  assertEquals(linhaDeAmanha("2026-10-22", { dia: "2026-10-23", itens: [], pagar: { n: 1, total: 312.4 }, carteira: { semData: 6 }, agenda: agenda("ligado") }),
    `Amanhã (sexta, 23/10): ${CAUDA}; a pagar: 1 conta, R$ 312,40.`);
  // a agenda vê algo marcado (cauda null): a frase de antes
  assertEquals(linhaDeAmanha("2026-10-22", { dia: "2026-10-23", itens: [], carteira: { semData: 6 }, agenda: agenda("ligado", { cauda: null }) }),
    "Amanhã (sexta, 23/10): nada marcado; 6 OS ativas sem data (ou com a data vencida).");
  // o Secretário tem compromisso no dia: a linha dos compromissos, a agenda não entra
  assertEquals(linhaDeAmanha("2026-10-22", { dia: "2026-10-23", itens: [{ hora: "08:00", texto: "OS-00074 (Marco Polo)" }], agenda: agenda("ligado") }),
    "Amanhã (sexta, 23/10): 08:00 OS-00074 (Marco Polo).");
  // o que a ligada mandaria (o detalhe da sombra)
  assertEquals(amanhaComAAgenda("2026-10-22", { dia: "2026-10-23", itens: [], carteira: { semData: 6 }, agenda: agenda("sombra") }), `Amanhã (sexta, 23/10): ${CAUDA}.`);
  assertEquals(amanhaComAAgenda("2026-10-22", { dia: "2026-10-23", itens: [{ hora: null, texto: "x" }], agenda: agenda("sombra") }), null);
  assertEquals(amanhaComAAgenda("2026-10-22", { dia: "2026-10-23", itens: [], agenda: agenda("sombra", { cauda: null }) }), null);
  assertEquals(amanhaComAAgenda("2026-10-22", null), null);
});

Deno.test("agenda ligada na quinta: as 3 linhas da semana logo depois do Amanhã; a cauda sozinha não tira o dia do calado, a semana sim", () => {
  const t = textoDaTarde(quinta({}, agenda("ligado")));
  assertEquals(t.texto!.split("\n"), [
    "Fechamento de quinta, 22/10: nada ficou de hoje.",
    "",
    `Amanhã (sexta, 23/10): ${CAUDA}.`,
    ...SEMANA,
    "Fornecedores esperando há mais de 1 dia: SR Contabilidade.",
    "Escritório: 46 despesas e 4 entradas para conferir, 15 alertas, 6 débitos sem loja; uns 30 min. *escritório*",
  ]);
  assertEquals(t.agenda, { cauda: true, semana: 3 });
  assert(t.texto!.length <= LIMITE_DA_TARDE && !PROIBIDAS.test(t.texto!) && !EMOJI.test(t.texto!), t.texto!);
  // nada mais a dizer: a semana sozinha é "algo" (é o plano da quinta)…
  const so = textoDaTarde(quinta({ fornecedores: [] }, agenda("ligado")));
  assert(so.texto?.includes(SEMANA[0]), String(so.texto));
  // …a cauda sozinha não (existe todo dia, como a carteira sem data), nem a semana na sombra
  assertEquals(textoDaTarde(quinta({ fornecedores: [] }, agenda("ligado", { semana: [] }))).texto, null);
  assertEquals(textoDaTarde(quinta({ fornecedores: [] }, agenda("sombra"))).texto, null);
});

Deno.test("agenda ligada: a semana conta como 1 das REGRAS.maxManha — com 3 que ficaram de hoje não há vaga (a cauda continua)", () => {
  assertEquals(REGRAS.maxManha, 3);
  const dois = textoDaTarde(quinta({ ficaram: ["B", "C"].map((l) => linha(l, `${l} cobrança`)) }, agenda("ligado")));
  assertEquals(dois.agenda, { cauda: true, semana: 3 });
  const tres = textoDaTarde(quinta({ ficaram: ["B", "C", "D"].map((l) => linha(l, `${l} cobrança`)) }, agenda("ligado")));
  assertEquals(tres.agenda, { cauda: true, semana: 0 });
  assert(!tres.texto!.includes("Semana que vem"), tres.texto!);
  assertStringIncludes(tres.texto!, `Amanhã (sexta, 23/10): ${CAUDA}.`);
  assertEquals(semanaCabe(2, agenda("ligado")), true);
  assertEquals(semanaCabe(3, agenda("ligado")), false);
  assertEquals(semanaCabe(0, agenda("ligado", { semana: [] })), false);
  assertEquals(semanaCabe(0, null), false);
  // fora do fechamento (a revisão da semana de segunda) a semana nunca entra; a cauda sim
  const rs = textoDaTarde(dados({ hoje: "2026-10-19", turno: "revisao_semana", amanha: { dia: "2026-10-20", itens: [], carteira: { semData: 6 }, agenda: agenda("ligado") } }));
  assertEquals(rs.texto, ["Revisão da semana, segunda, 19/10. Nada parado.", "", `Amanhã (terça, 20/10): ${CAUDA}.`].join("\n"));
  assertEquals(rs.agenda, { cauda: true, semana: 0 });
});

Deno.test("agenda ligada no corte de 1.000: a semana cede primeiro (3 → 1 → nenhuma) e o resto fica como sem a agenda", () => {
  const longo = "y".repeat(230);
  const base = {
    ficaram: ["B", "C"].map((l) => linha(l, `${l} ${longo}`)),
    fornecedores: ["SR Contabilidade", "Kamell", "Dometic"],
    pergunta: true,
  };
  const semAgenda = textoDaTarde(quinta(base)).texto!;
  const t = textoDaTarde(quinta(base, agenda("ligado")));
  assert(t.texto!.length <= LIMITE_DA_TARDE, `${t.texto!.length}`);
  assert(t.agenda!.semana < 3, `a semana tinha de ceder: ${t.agenda!.semana}`);
  // o que não é da agenda é o mesmo texto de quem não tem a agenda (só a cauda trocou e a semana entrou no que coube)
  const semAAgenda = t.texto!.split("\n").filter((l) => !SEMANA.includes(l)).join("\n")
    .replace(CAUDA, "nada marcado; 6 OS ativas sem data (ou com a data vencida)");
  assertEquals(semAAgenda, semAgenda);
  // texto que já não cabia sem a agenda: nenhuma linha da semana, e o corte de sempre
  const enorme = { ...base, ficaram: ["B", "C"].map((l) => linha(l, `${l} ${"z".repeat(400)}`)) };
  const e = textoDaTarde(quinta(enorme, agenda("ligado")));
  assert(e.texto!.length <= LIMITE_DA_TARDE, `${e.texto!.length}`);
  assertEquals(e.agenda!.semana, 0);
  assert(!e.texto!.includes("Semana que vem"));
});

// ─── (24/10/2026) Agenda de Produção, Fase 2 (P5): as linhas do plano no fechamento ──────────────────────────────
// Os textos são os do banco de verdade (supabase/tests/agenda_fase2_leituras.sql, F1/F10/F12, a carteira de 29/10
// publicada pela vigia e o cenário do motor). O que se protege: só as ligadas entram, nas vagas que sobram de
// REGRAS.maxManha, da maior perda para a menor, logo depois do "Amanhã"; na sombra o texto é o de antes byte a byte; o
// corte de 1.000 tira linha inteira.
const SEMANA_F2 = "Agenda: publiquei a semana de 03 a 06/11 (seg 02 é Finados): Vanderlei (ter 03 a qui 05/11), Rodrigo OS-00096 " +
  "(ter 03/11), Lenine (qua 04 a seg 09/11) e reserva para Flávio (qua 04 e sex 06/11). Fora: Nelson (preciso de você) e Giancarlo " +
  "(começa qui 26/11). Depois desta semana, só tem 6,5 dias de serviço pronto na fila. *agenda plano* mostra tudo; *desfaz semana* volta.";
const DECISAO_F2 = "Agenda, preciso de você. Não cabe tudo até qui 05/11. Qual aceita atrasar? 1) Nelson (OS-00112) atrasa: termina ter " +
  "17/11 em vez de qui 05/11; 2) Deixo o Nelson fora do plano por enquanto. Recomendo a 1: é o menor atraso (8 dias úteis). Me responda aqui.";
const DIA_F2 = "Agenda de hoje: Antônio (OS-00201) — você abre, Roberto o dia todo, João à tarde. Foi isso? Responda *dia feito* ou conte o que mudou.";
const PERGUNTA_F2 = "Agenda: O cabo do Caio tinha previsão para ter 03/11. Chegou? (e mais 1 em *agenda pendências*)";

type Linha2 = NonNullable<AgendaDoFechamento["linhas"]>[number];
const l2 = (tipo: Linha2["tipo"], texto: string, perda: number, modo: "ligado" | "sombra" = "ligado", extra: Partial<Linha2> = {}): Linha2 => ({
  tipo, texto, perda, pergunta_id: tipo === "decisao" || tipo === "dia" || tipo === "pergunta" ? `q-${tipo}` : null, acao_ids: [], modo, ...extra,
});
const comLinhas = (linhas: Linha2[], modo: "sombra" | "ligado" = "ligado"): AgendaDoFechamento => ({ modo, cauda: null, semana: [], linhas });
const QUATRO = [
  l2("pergunta", PERGUNTA_F2, 30), l2("semana", SEMANA_F2, 60, "ligado", { acao_ids: ["a1", "a2"] }), l2("decisao", DECISAO_F2, 50),
  l2("dia", DIA_F2, 70),
];
const emSombra = (ls: Linha2[]) => ls.map((l) => ({ ...l, modo: "sombra" as const }));

Deno.test("Fase 2: vagas = REGRAS.maxManha − as que ficaram (0, 1, 2, 3), da maior perda para a menor", () => {
  assertEquals(REGRAS.maxManha, 3);
  const tipos = (ficaram: number) => linhasDaAgendaQueCabem(ficaram, comLinhas(QUATRO)).map((l) => l.tipo);
  assertEquals(tipos(0), ["dia", "semana", "decisao"]);
  assertEquals(tipos(1), ["dia", "semana"]);
  assertEquals(tipos(2), ["dia"]);
  assertEquals(tipos(3), []);
  assertEquals(tipos(5), [], "nunca negativo");
  // a decisão que perde amanhã (100) passa na frente de tudo
  const urgente = l2("decisao", "Agenda, preciso de você. Outra. Me responda aqui.", 100);
  assertEquals(linhasDaAgendaQueCabem(2, comLinhas([...QUATRO, urgente])).map((l) => l.perda), [100]);
  // as da sombra nunca entram
  assertEquals(linhasDaAgendaQueCabem(0, comLinhas(emSombra(QUATRO))), []);
  assertEquals(linhasDaAgendaQueCabem(0, null), []);
});

Deno.test("Fase 2: as linhas saem logo depois do 'Amanhã', inteiras, e o que saiu vai em agenda.linhas", () => {
  const t = textoDaTarde(quinta({ fornecedores: [], escritorio: null }, comLinhas(QUATRO)));
  const linhas = t.texto!.split("\n");
  const i = linhas.findIndex((l) => l.startsWith("Amanhã (sexta, 23/10)"));
  assertEquals(linhas.slice(i + 1), [DIA_F2, SEMANA_F2, DECISAO_F2]);
  assertEquals(t.agenda?.linhas?.map((l) => l.tipo), ["dia", "semana", "decisao"]);
  assert(t.texto!.length <= LIMITE_DA_TARDE, `${t.texto!.length}`);
  assert(!PROIBIDAS.test(t.texto!.replace("agenda pendências", "")), "sem jargão no que a agenda manda");
  // com o fornecedor (e o escritório) junto, a quinta passaria de 1.000: sai a de menor perda das três (a decisão), inteira
  const cheio = textoDaTarde(quinta({ fornecedores: ["SR Contabilidade"] }, comLinhas(QUATRO)));
  assert(cheio.texto!.length <= LIMITE_DA_TARDE, `${cheio.texto!.length}`);
  assertEquals(cheio.agenda?.linhas?.map((l) => l.tipo), ["dia", "semana"]);
  const lc = cheio.texto!.split("\n");
  const j = lc.findIndex((l) => l.startsWith("Amanhã (sexta, 23/10)"));
  assertEquals(lc.slice(j + 1, j + 4), [DIA_F2, SEMANA_F2, "Fornecedores esperando há mais de 1 dia: SR Contabilidade."]);
});

Deno.test("Fase 2: com 2 que ficaram de hoje, só 1 linha do plano (a de maior perda); as letras do Secretário vêm antes", () => {
  const t = textoDaTarde(quinta({ ficaram: ["B", "C"].map((l) => linha(l, `${l} cobrança`)) }, comLinhas(QUATRO)));
  assertEquals(t.agenda?.linhas?.map((l) => l.tipo), ["dia"]);
  assertStringIncludes(t.texto!, DIA_F2);
  assert(!t.texto!.includes(SEMANA_F2) && !t.texto!.includes(DECISAO_F2));
});

Deno.test("Fase 2: a linha do plano conta como 'há algo' (sem ela, o dia calado; com ela, a mensagem)", () => {
  assertEquals(textoDaTarde(quinta({ fornecedores: [] }, comLinhas([]))).texto, null);
  const comDecisao = textoDaTarde(quinta({ fornecedores: [] }, comLinhas([l2("decisao", DECISAO_F2, 50)])));
  assertStringIncludes(comDecisao.texto!, DECISAO_F2);
  // só da sombra: continua calado
  assertEquals(textoDaTarde(quinta({ fornecedores: [] }, comLinhas([l2("decisao", DECISAO_F2, 50, "sombra")]))).texto, null);
});

Deno.test("Fase 2: na sombra (as linhas com modo 'sombra', ou a agenda em sombra) o fechamento é o de antes, byte a byte", () => {
  for (const extra of [{}, { ficaram: ["B"].map((l) => linha(l, `${l} cobrança`)) }, { fornecedores: [] as string[] }]) {
    const antes = textoDaTarde(quinta(extra)).texto;
    assertEquals(textoDaTarde(quinta(extra, comLinhas(emSombra(QUATRO)))).texto, antes, JSON.stringify(extra));
    assertEquals(textoDaTarde(quinta(extra, comLinhas(emSombra(QUATRO), "sombra"))).texto, antes, JSON.stringify(extra));
  }
  // a revisão da semana e a do mês não levam as linhas do plano
  const rs = (ag: AgendaDoFechamento | null) =>
    textoDaTarde(dados({ hoje: "2026-10-19", turno: "revisao_semana", amanha: { dia: "2026-10-20", itens: [], carteira: { semData: 6 }, agenda: ag } })).texto;
  assertEquals(rs(comLinhas(QUATRO)), rs(null));
});

Deno.test("Fase 2: no corte de 1.000 a linha do plano de menor perda sai inteira (nunca no meio); as outras encurtam antes", () => {
  const base = { fornecedores: ["SR Contabilidade", "Kamell", "Dometic"], pergunta: true };
  const t = textoDaTarde(quinta({ ...base, ficaram: [linha("B", `B ${"y".repeat(110)}`)] }, comLinhas(QUATRO)));
  assert(t.texto!.length <= LIMITE_DA_TARDE, `${t.texto!.length}`);
  for (const l of t.agenda!.linhas!) assertStringIncludes(t.texto!, l.texto);
  for (const l of QUATRO) {
    if (t.texto!.includes(l.texto.slice(0, 40))) assertStringIncludes(t.texto!, l.texto, `cortou no meio: ${l.tipo}`);
  }
  // muito longo: as linhas do plano saem (da menor perda para a maior) até caber
  const enorme = textoDaTarde(quinta({ ...base, ficaram: ["B", "C"].map((l) => linha(l, `${l} ${"z".repeat(400)}`)) }, comLinhas(QUATRO)));
  assert(enorme.texto!.length <= LIMITE_DA_TARDE, `${enorme.texto!.length}`);
  assert((enorme.agenda!.linhas ?? []).length <= 1);
  for (const l of QUATRO) {
    if (enorme.texto!.includes(l.texto.slice(0, 40))) assertStringIncludes(enorme.texto!, l.texto, `cortou no meio: ${l.tipo}`);
  }
});

Deno.test("Fase 2: com as linhas do plano a projeção da semana (Fase 1) só entra se ainda sobrar vaga", () => {
  const ag: AgendaDoFechamento = { modo: "ligado", cauda: CAUDA, semana: SEMANA, linhas: [l2("decisao", DECISAO_F2, 50), l2("dia", DIA_F2, 70)] };
  const t = textoDaTarde(quinta({ ficaram: [linha("B", "B cobrança")] }, ag));
  assertEquals(t.agenda?.linhas?.length, 2);
  assertEquals(t.agenda?.semana, 0, "1 que ficou + 2 linhas do plano = as 3 vagas");
  const so1 = textoDaTarde(quinta({}, { ...ag, linhas: [l2("dia", DIA_F2, 70)] }));
  assertEquals([so1.agenda?.linhas?.length, so1.agenda?.semana], [1, 3]);
});
