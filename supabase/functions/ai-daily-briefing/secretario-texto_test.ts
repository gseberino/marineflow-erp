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
