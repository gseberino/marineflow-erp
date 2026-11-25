import { assert, assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { candidatosDoDia } from "./secretario-candidatos.ts";
import { selecionar } from "./secretario-selecao.ts";
import {
  type DadosDeHoje,
  linhaDeFolga,
  linhaDeHoje,
  linhaDeLogoAbaixo,
  META_DE_CARACTERES,
  textoDaManha,
  textoDoEscritorio,
} from "./secretario-texto.ts";
import { AGORA_1510, coleta1510, deHoje1510, HOJE_1510 } from "./secretario-fixture.ts";

const VAZIO: DadosDeHoje = { agenda: [], promessas: [], vencimentos: [], falhasDeEnvio: 0, errosDaNoite: 0 };

Deno.test("15/10 com os dados do banco: o texto inteiro, abaixo de 1.000 caracteres", () => {
  const selecao = selecionar(candidatosDoDia(coleta1510(), AGORA_1510, HOJE_1510), [], HOJE_1510);
  const t = textoDaManha({ hoje: HOJE_1510, tipoDoDia: "util", feriado: null, selecao, naRua: { total: 21026, n: 5 }, deHoje: deHoje1510() });
  // Decisão do dono (15/10): os rascunhos viram UM item; a cobrança grande é item da manhã (não só o "Na rua").
  // Ensaio (15/10): o Cesar pediu orçamento ontem e ninguém respondeu, e o Jorge escreveu ontem "amanhã" (= hoje):
  // os dois se perdem hoje e vêm primeiro (o mais antigo antes); o pacote dos não enviados fica logo abaixo.
  // O ORÇ-00116 já tinha sido mandado. Com 3 itens longos, a promessa sai sem a frase (cabe em 1.000).
  assertEquals(t, [
    "Bom dia! Quinta, 15/10. Hoje 3 coisas pedem você.",
    "Na rua: R$ 21.026,00 vencidos (5).",
    "",
    "*A.* *Cesar* (sem cadastro) escreveu ontem às 12:23 e está há 19 h sem resposta; a mensagem parece pedir preço ou orçamento. Recomendo responder ainda de manhã. *A* = preparo a resposta · *A espera* = lembro amanhã",
    "*B.* *Jorge Girardon* mandou áudio ontem às 14:53 e está há 17 h sem resposta. Parece ter pressa (escreveu ontem \"amanhã\", que é hoje). Recomendo responder ainda de manhã. *B* = resumo o áudio e preparo a resposta · *B espera* = lembro amanhã",
    "*C.* *Marcelo Marco Bertoldi* (Aria, OS-00038): R$ 16.890,00 venceu terça (13/10) e não entrou. Recomendo um lembrete educado hoje. *C* = te mostro o lembrete pronto · *C espera* = até segunda",
    "",
    "Hoje: nada na agenda. Promessa sua: Eng.⁰ Rafael Borges DOMETIC. Amanhã vence: R$ 5.237,99 a receber (APOLO INDUSTRIA…).",
    "Logo abaixo ficaram 2 orçamentos não enviados (R$ 141 mil) e ORÇ-00095 (MP MOTOR HOMES, R$ 14.461,00), mais 12 assuntos. *lista*",
  ].join("\n"));
  assert(t.length <= META_DE_CARACTERES, `${t.length} caracteres`);
  // nada de jargão nem de emoji de painel
  for (const proibido of ["conciliação", "pendência", "ferramenta", "☀️", "⚡", "💡"]) assert(!t.includes(proibido), proibido);
});

Deno.test("mais de 3 cobranças grandes: as 3 maiores na manhã; a de fora é nomeada no 'Na rua', com a letra", () => {
  const coleta = coleta1510();
  coleta.orcamentos = [];
  coleta.conversas = [];
  coleta.oss = [];
  coleta.cobrancas = [6000, 7000, 8000, 9000].map((saldo, i) => ({
    id: `g${i}`, client_id: `c-g${i}`, cliente: `Cliente ${i}`, descricao: null, vencimento: "2026-10-13", saldo, os_numero: null, barco: null,
  }));
  const selecao = selecionar(candidatosDoDia(coleta, AGORA_1510, HOJE_1510), [], HOJE_1510);
  const t = textoDaManha({ hoje: HOJE_1510, tipoDoDia: "util", feriado: null, selecao, naRua: { total: 30000, n: 4 }, deHoje: VAZIO });
  assertEquals(selecao.manha.map((g) => g.membros[0].c.valor), [9000, 8000, 7000]);
  assertStringIncludes(t, "Na rua: R$ 30.000,00 vencidos (4); mais uma grande: Cliente 0 (R$ 6.000,00, *D*).");
});

Deno.test("dia sem nada: 'Nada precisa de você hoje', sem 'Na rua' zerado e sem 'logo abaixo'", () => {
  const selecao = selecionar([], [], HOJE_1510);
  const t = textoDaManha({ hoje: HOJE_1510, tipoDoDia: "util", feriado: null, selecao, naRua: { total: 0, n: 0 }, deHoje: VAZIO });
  assertEquals(t, "Bom dia! Quinta, 15/10. Nada precisa de você hoje.\n\nHoje: nada na agenda.");
});

Deno.test("domingo e feriado: uma linha", () => {
  assertEquals(linhaDeFolga("domingo", null), "Bom dia! Domingo: nada precisa de você hoje. *lista* se quiser ver.");
  assertEquals(linhaDeFolga("feriado", "Finados"), "Bom dia! Feriado (Finados): nada precisa de você hoje. *lista* se quiser ver.");
  const selecao = selecionar(candidatosDoDia(coleta1510(), AGORA_1510, "2026-10-18"), [], "2026-10-18", 0);
  assertEquals(
    textoDaManha({ hoje: "2026-10-18", tipoDoDia: "domingo", feriado: null, selecao, naRua: { total: 21026, n: 5 }, deHoje: deHoje1510() }),
    "Bom dia! Domingo: nada precisa de você hoje. *lista* se quiser ver.",
  );
});

Deno.test("linha Hoje: agenda com hora, promessa, a receber e a pagar de hoje e amanhã, falha da noite", () => {
  const t = linhaDeHoje({
    agenda: [{ hora: "09:00", titulo: "OS-00104 (Itapoã)" }, { hora: null, titulo: "Ligar para o Rafael" }],
    promessas: [{ contato: "Eng. Rafael", promessa: "retorno sobre o NRX 80" }],
    vencimentos: [
      { lado: "pagar", quando: "hoje", valor: 785.07, nome: "TSD" },
      { lado: "receber", quando: "amanha", valor: 5237.99, nome: "APOLO" },
    ],
    falhasDeEnvio: 2,
    errosDaNoite: 1,
  });
  assertEquals(t, "Hoje: 09:00 OS-00104 (Itapoã); Ligar para o Rafael. Promessa sua: Eng. Rafael (retorno sobre o NRX 80). " +
    "Vence hoje: R$ 785,07 a pagar (TSD). Amanhã vence: R$ 5.237,99 a receber (APOLO). " +
    "Esta noite: 2 mensagens do sistema não saíram e 1 erro registrado.");
  assertEquals(linhaDeHoje(VAZIO), "Hoje: nada na agenda.");
  assertStringIncludes(linhaDeHoje({ ...VAZIO, agenda: [{ hora: "09:00", titulo: "x" }, { hora: "10:00", titulo: "y" }] }, true), "2 compromissos na agenda.");
});

// (pacote 1, V2, 24/11/2026) A rotina de IA que falhou calada (a triagem de e-mail ficou 12 dias assim) vira UMA frase no
// fim da linha "Hoje", na mensagem que o dono já recebe. O que se protege: o texto exato, a versão curta sem a contagem, e
// que sem falha (campo ausente, vazio ou zerado) a linha é a de antes, byte a byte.
Deno.test("linha Hoje: a rotina de IA que falhou desde ontem entra como uma frase no fim; sem falha, a linha de antes", () => {
  const umaRotina = { ...VAZIO, rotinasSemIA: [{ rotulo: "triagem de e-mail", vezes: 12 }] };
  assertEquals(linhaDeHoje(umaRotina), "Hoje: nada na agenda. IA que falhou desde ontem: triagem de e-mail (12 vezes).");
  assertEquals(linhaDeHoje(umaRotina, true), "Hoje: nada na agenda. IA falhou desde ontem: triagem de e-mail.");
  const duas = { ...VAZIO, rotinasSemIA: [{ rotulo: "triagem de e-mail", vezes: 12 }, { rotulo: "leitura do prazo do fornecedor", vezes: 1 }] };
  assertEquals(linhaDeHoje(duas),
    "Hoje: nada na agenda. IA que falhou desde ontem: triagem de e-mail (12 vezes) e leitura do prazo do fornecedor (1 vez).");
  assertEquals(linhaDeHoje(duas, true), "Hoje: nada na agenda. IA falhou desde ontem: triagem de e-mail e leitura do prazo do fornecedor.");
  const tres = { ...VAZIO, rotinasSemIA: [...duas.rotinasSemIA, { rotulo: "detector da agenda", vezes: 2 }] };
  assertEquals(linhaDeHoje(tres),
    "Hoje: nada na agenda. IA que falhou desde ontem: triagem de e-mail (12 vezes), leitura do prazo do fornecedor (1 vez) e detector da agenda (2 vezes).");
  // vem depois do "Esta noite", que continua igual
  assertEquals(linhaDeHoje({ ...umaRotina, falhasDeEnvio: 2, errosDaNoite: 1 }),
    "Hoje: nada na agenda. Esta noite: 2 mensagens do sistema não saíram e 1 erro registrado. IA que falhou desde ontem: triagem de e-mail (12 vezes).");
  // sem falha: nada muda
  for (const semFalha of [VAZIO, { ...VAZIO, rotinasSemIA: [] }, { ...VAZIO, rotinasSemIA: [{ rotulo: "triagem de e-mail", vezes: 0 }] }]) {
    assertEquals(linhaDeHoje(semFalha), "Hoje: nada na agenda.");
    assertEquals(linhaDeHoje(semFalha, true), "Hoje: nada na agenda.");
  }
});

Deno.test("manhã: a frase da IA que falhou sai na mesma mensagem, dentro da meta; em domingo e feriado a linha é a de sempre", () => {
  const selecao = selecionar(candidatosDoDia(coleta1510(), AGORA_1510, HOJE_1510), [], HOJE_1510);
  const deHoje = { ...deHoje1510(), rotinasSemIA: [{ rotulo: "triagem de e-mail", vezes: 12 }] };
  const base = { hoje: HOJE_1510, tipoDoDia: "util" as const, feriado: null, selecao, naRua: { total: 21026, n: 5 } };
  const sem = textoDaManha({ ...base, deHoje: deHoje1510() });
  const com = textoDaManha({ ...base, deHoje });
  assert(com.length <= META_DE_CARACTERES, `${com.length} caracteres`);
  // uma mensagem só, com as mesmas linhas: muda só a linha "Hoje", que ganha a frase no fim
  const [linhasSem, linhasCom] = [sem.split("\n"), com.split("\n")];
  assertEquals(linhasCom.length, linhasSem.length);
  const hoje = linhasCom.find((l) => l.startsWith("Hoje: "))!;
  assert(/IA (que )?falhou desde ontem: triagem de e-mail( \(12 vezes\))?\.$/.test(hoje), hoje);
  assertEquals(linhasCom.filter((l) => l.includes("desde ontem: triagem")).length, 1);
  // os itens da manhã (as letras) não mudam
  assertEquals(linhasCom.filter((l) => /^\*[A-C]\.\*/.test(l)), linhasSem.filter((l) => /^\*[A-C]\.\*/.test(l)));
  assertEquals(
    textoDaManha({ ...base, hoje: "2026-10-18", tipoDoDia: "domingo", deHoje }),
    "Bom dia! Domingo: nada precisa de você hoje. *lista* se quiser ver.",
  );
});

Deno.test("logo abaixo: sem guardados não há linha; sem nomes, só a contagem", () => {
  assertEquals(linhaDeLogoAbaixo(selecionar([], [], HOJE_1510)), null);
  const selecao = selecionar(candidatosDoDia(coleta1510(), AGORA_1510, HOJE_1510), [], HOJE_1510);
  assertEquals(linhaDeLogoAbaixo(selecao, false), "Guardei 14 assuntos. *lista*");
});

Deno.test("escritório: só o que tem; tudo zerado = em dia", () => {
  const t = textoDoEscritorio({
    propostas: { saidas: 46, entradas: 4, transferencias: 1, outras: 0 }, alertas: 15, regras: 103, debitosSemLoja: 6,
    entradas: { doMes: 2, sinais: 2, antigas: 6 },
  }, "07:30");
  assertEquals(t.split("\n"), [
    "Escritório (contado às 07:30):",
    "• Lançamentos do extrato para conferir: 46 saídas, 4 entradas e 1 transferência",
    "• 15 gastos fora do padrão",
    "• 103 regras que aprendi esperando você conferir",
    "• 6 compras no débito sem loja",
    "• Entradas do banco sem identificação: 2 do mês, 2 que parecem ser sinais já lançados, 6 antigas ou de centavos",
    'Fica tudo no Extrato. Me peça um grupo por vez (ex.: "débitos sem loja").',
  ]);
  assertEquals(textoDoEscritorio({ propostas: null, alertas: 0, regras: null, debitosSemLoja: 0, entradas: null }, "07:30"), "Escritório em dia (contado às 07:30).");
});

// (24/11/2026) entrada no Extrato esperando baixa: a linha "Na rua" diz quanto do vencido pode já estar pago.
Deno.test("'Na rua' com entradas esperando baixa: diz quanto do vencido pode já estar pago; sem elas, a linha de sempre", () => {
  const coleta = coleta1510();
  coleta.orcamentos = [];
  coleta.conversas = [];
  coleta.oss = [];
  coleta.cobrancas = [
    { id: "g-deve", client_id: "c-deve", cliente: "Quem Deve", descricao: null, vencimento: "2026-10-13", saldo: 16890, os_numero: null, barco: null },
    { id: "g-pagou", client_id: "c-pagou", cliente: "Quem Pagou", descricao: null, vencimento: "2026-10-08", saldo: 5238.02, os_numero: null, barco: null,
      esperando: { valor: 5238.02, data: "2026-10-08" } },
  ];
  const selecao = selecionar(candidatosDoDia(coleta, AGORA_1510, HOJE_1510), [], HOJE_1510);
  const manha = (naRua: { total: number; n: number; esperando?: { total: number; n: number } }) =>
    textoDaManha({ hoje: HOJE_1510, tipoDoDia: "util", feriado: null, selecao, naRua, deHoje: VAZIO });

  const t = manha({ total: 22128.02, n: 2, esperando: { total: 5238.02, n: 1 } });
  assertStringIncludes(t, "Na rua: R$ 22.128,02 vencidos (2). Desses, até R$ 5.238,02 podem já estar pagos: 1 conta tem entrada no Extrato esperando baixa.");
  // quem deve sobe com letra; quem tem entrada esperando não sobe nem é mandado ligar
  assertStringIncludes(t, "*A.* *Quem Deve*: R$ 16.890,00");
  assert(!t.includes("*Quem Pagou*"), "a conta com entrada esperando não ganha letra");
  assertEquals(selecao.manha.length, 1);

  assertStringIncludes(manha({ total: 5238.02, n: 1, esperando: { total: 5238.02, n: 1 } }),
    "Na rua: R$ 5.238,02 vencidos (1). Desses, até R$ 5.238,02 podem já estar pagos: 1 conta tem entrada no Extrato esperando baixa.");
  // o total é o que as entradas cobrem, não o saldo das contas (um Pix de R$ 5.000,00 para duas contas de R$ 8.574,60)
  assertStringIncludes(manha({ total: 8574.6, n: 2, esperando: { total: 5000, n: 2 } }),
    "Na rua: R$ 8.574,60 vencidos (2). Desses, até R$ 5.000,00 podem já estar pagos: 2 contas têm entrada no Extrato esperando baixa.");
  // sem entradas esperando (campo ausente ou zerado): a linha de antes
  assertStringIncludes(manha({ total: 22128.02, n: 2 }), "Na rua: R$ 22.128,02 vencidos (2).\n");
  assertStringIncludes(manha({ total: 22128.02, n: 2, esperando: { total: 0, n: 0 } }), "Na rua: R$ 22.128,02 vencidos (2).\n");
});

// (Conferência da leva A do pacote 1, 24/11/2026) O rebase juntou na mesma mensagem duas frases novas, cada uma com o
// teste dela e nenhum com as duas: a da cobrança ("Desses, até … podem já estar pagos", na linha "Na rua") e a da leva A
// ("IA que falhou desde ontem", no fim da linha "Hoje"). O que se protege: as duas saem juntas, cada uma na linha dela e
// uma vez só; e, num dia cheio, a soma das duas não tira item da manhã nem some com uma delas: o que encurta é o "Hoje"
// (a frase da IA fica sem a contagem) e o "logo abaixo". Em 24/11/2026, com os 3 itens longos de 15/10, as duas frases
// juntas dão 1.056 caracteres: passa da meta de 1.000, que é alvo e não corte (ninguém trunca o texto depois).
Deno.test("manhã com entrada esperando baixa E rotina de IA que falhou: as duas frases saem juntas, e a soma não tira item nem frase", () => {
  const naRua = { total: 8574.6, n: 2, esperando: { total: 5000, n: 2 } };
  const rotinasSemIA = [{ rotulo: "triagem de e-mail", vezes: 12 }, { rotulo: "leitura do prazo do fornecedor", vezes: 1 }];
  const fraseDaRua = " Desses, até R$ 5.000,00 podem já estar pagos: 2 contas têm entrada no Extrato esperando baixa.";
  const fraseDaIA = " IA que falhou desde ontem: triagem de e-mail (12 vezes) e leitura do prazo do fornecedor (1 vez).";

  // dia leve: cabe na meta, e as duas saem por extenso
  const leve = textoDaManha({
    hoje: HOJE_1510, tipoDoDia: "util", feriado: null, selecao: selecionar([], [], HOJE_1510), naRua, deHoje: { ...VAZIO, rotinasSemIA },
  });
  assertEquals(leve, [
    "Bom dia! Quinta, 15/10. Nada precisa de você hoje.",
    `Na rua: R$ 8.574,60 vencidos (2).${fraseDaRua}`,
    "",
    `Hoje: nada na agenda.${fraseDaIA}`,
  ].join("\n"));

  // dia cheio (os 3 itens de 15/10): as mesmas linhas da manhã sem as duas frases, com as duas frases a mais
  const selecao = selecionar(candidatosDoDia(coleta1510(), AGORA_1510, HOJE_1510), [], HOJE_1510);
  const base = { hoje: HOJE_1510, tipoDoDia: "util" as const, feriado: null, selecao };
  const sem = textoDaManha({ ...base, naRua: { total: 8574.6, n: 2 }, deHoje: deHoje1510() });
  const com = textoDaManha({ ...base, naRua, deHoje: { ...deHoje1510(), rotinasSemIA } });
  const [linhasSem, linhasCom] = [sem.split("\n"), com.split("\n")];
  assertEquals(linhasCom.length, linhasSem.length);
  assertEquals(linhasCom[1], `Na rua: R$ 8.574,60 vencidos (2).${fraseDaRua}`);
  assertEquals(linhasCom.filter((l) => l.includes("podem já estar pagos")).length, 1);
  const hoje = linhasCom.filter((l) => l.startsWith("Hoje: "));
  assertEquals(hoje.length, 1);
  // por extenso quando cabe; sem a contagem quando o "Hoje" encurta. Nos dois casos, no fim da linha e com as duas rotinas
  assert(/ IA (que )?falhou desde ontem: triagem de e-mail( \(12 vezes\))? e leitura do prazo do fornecedor( \(1 vez\))?\.$/.test(hoje[0]), hoje[0]);
  assertEquals(linhasCom.filter((l) => l.includes("desde ontem: triagem")).length, 1);
  // os itens da manhã (as letras) são os mesmos, na mesma ordem
  const itens = (linhas: string[]) => linhas.filter((l) => /^\*[A-C]\.\*/.test(l));
  assertEquals(itens(linhasCom), itens(linhasSem));
  assertEquals(itens(linhasCom).length, 3);
  // e a mensagem cresce, no máximo, o tamanho das duas frases (o resto só encurta)
  assert(com.length <= sem.length + fraseDaRua.length + fraseDaIA.length, `${com.length} caracteres (sem as frases: ${sem.length})`);
});
