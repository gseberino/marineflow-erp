// O texto da tarde (secretário, Passo 3): o formato aprovado, o "só se houver algo", a estimativa do escritório,
// a pergunta da sexta, o tamanho e as palavras proibidas.
import { assert, assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import type { LinhaComLetra } from "./secretario-tarde-regras.ts";
import {
  type DadosDaTarde,
  LIMITE_DA_TARDE,
  linhaDaSemana,
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
    "Amanhã (sexta, 16/10): nada marcado; 6 OS aprovadas sem data; a pagar: 1 conta, R$ 785,07.");
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
    // (23/10/2026) com a carteira de 23/10: 6 OS aprovadas sem data
    hoje: "2026-10-19", turno: "revisao_semana", amanha: { dia: "2026-10-20", itens: [], pagar: { n: 1, total: 785.07 }, carteira: { semData: 6 } },
    panorama: { mes: null, vigia: null, semana: { entra: 0, nEntra: 0, sai: 785.07, nSai: 1, ate: "2026-10-25" } },
  }));
  assertEquals(t.texto, [
    "Revisão da semana, segunda, 19/10. Nada parado.",
    "",
    "Amanhã (terça, 20/10): nada marcado; 6 OS aprovadas sem data; a pagar: 1 conta, R$ 785,07.",
    "Semana até domingo (25/10): a receber nada; a pagar R$ 785 (1 conta) — sai mais do que entra.",
  ].join("\n"));
  // sem a leitura do "Amanhã" (null), a revisão é a de antes
  const sem = textoDaTarde(dados({ hoje: "2026-10-19", turno: "revisao_semana", amanha: null, panorama: null }));
  assertEquals(sem.texto, "Revisão da semana, segunda, 19/10. Nada parado.");
});

// ─── (23/10/2026) D11b: "agenda livre" só com a carteira lida e sem OS sem data ─────────────────────
// Até 23/10 o "Amanhã" dizia "agenda livre" sempre que nada estava marcado — e havia 6 OS aprovadas sem data.
Deno.test("D11b: nada marcado amanhã — 'agenda livre' só com a carteira lida e vazia; com OS sem data, quantas", () => {
  const amanha = (carteira: { semData: number } | null | undefined) => linhaDeAmanha("2026-10-22", { dia: "2026-10-23", itens: [], carteira });
  assertEquals(amanha({ semData: 6 }), "Amanhã (sexta, 23/10): nada marcado; 6 OS aprovadas sem data.");
  assertEquals(amanha({ semData: 1 }), "Amanhã (sexta, 23/10): nada marcado; 1 OS aprovada sem data.");
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
  assertStringIncludes(t, "Amanhã (sexta, 16/10): nada marcado; 6 OS aprovadas sem data; a pagar: 2 contas, R$ 1.234,00.");
  assert(!t.includes("agenda livre"));
});
