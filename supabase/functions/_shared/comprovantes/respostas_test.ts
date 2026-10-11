// O parser da conversa dos comprovantes: a tabela 3.4 da spec inteira, respostas reais do dono
// (digitadas e transcritas do áudio pelo Whisper, com "🎤", maiúscula e ponto final) e os comandos.
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  classeDoComando,
  type Interpretacao,
  interpretarResposta,
  lerComando,
  lerData,
  lerOs,
  lerValor,
  MENU_COBRAR,
  MENU_COMO_PAGOU,
  MENU_CORRIGIR,
  MENU_MESMA_COMPRA,
  MENU_QUEM_PAGOU,
  opcoesDoPasso,
  pareceDica,
  respostaNaoEntendida,
} from "./respostas.ts";
import { normalizarResposta, type Opcao } from "../whatsapp/pergunta-ativa.ts";

// 11/10/2026 12:00 em São Paulo (domingo)
const AGORA = new Date("2026-10-11T15:00:00Z");

const MENU_PARA_QUE: Opcao[] = [
  { n: 1, rotulo: "OS-00112 · Brisa", valor: "os:1" },
  { n: 2, rotulo: "OS-00118 · Dona V", valor: "os:2" },
  { n: 3, rotulo: "OS-00101 · Madu I (concluída)", valor: "os:3" },
  { n: 4, rotulo: "Estoque", valor: "estoque" },
  { n: 5, rotulo: "Insumo", valor: "insumo" },
  { n: 6, rotulo: "Empresa (sem OS)", valor: "empresa" },
  { n: 7, rotulo: "Pessoal", valor: "pessoal" },
];

const i = (passo: string, texto: string, opcoes: Opcao[] = []) => interpretarResposta(passo, opcoes, texto, AGORA);

function tabela(passo: string, opcoes: Opcao[], casos: Array<[string, Interpretacao | null]>) {
  for (const [texto, esperado] of casos) assertEquals(i(passo, texto, opcoes), esperado, `${passo}: ${JSON.stringify(texto)}`);
}

// ─── valor ────────────────────────────────────────────────────────────────────────────────

Deno.test("lerValor: a tabela 3.4", () => {
  const casos: Array<[string, string | null]> = [
    ["62", "62.00"], ["62,5", "62.50"], ["62,50", "62.50"], ["r$ 62,50", "62.50"], ["1.234,56", "1234.56"], ["1.234", "1234.00"],
    ["62.50", "62.50"], ["62 reais", "62.00"], ["62 reais e 50 centavos", "62.50"],
    ["1,234.56", null], ["0", null], ["0,00", null], ["1.000.000,00", null],
    // mais respostas reais
    ["R$62", "62.00"], ["r$ 1.234,5", "1234.50"], ["999.999,99", "999999.99"], ["187,40", "187.40"], ["foi 45", "45.00"],
    ["62.5", "62.50"], ["1234,56", "1234.56"], ["0,01", "0.01"], ["62,505", null], ["1,234", null], ["sessenta e dois", null],
    ["62 e 50", null], ["-62", null], ["1 real", "1.00"], ["50 contos", "50.00"],
  ];
  for (const [t, v] of casos) assertEquals(lerValor(normalizarResposta(t)), v, t);
});

Deno.test("passo valor: número, sim (= mantém o lido), não/ok passam ao banco; texto livre não é resposta", () => {
  tabela("valor", [], [
    ["62,50", { tipo: "valor", valor: "62.50" }],
    ["🎤 62 reais e 50 centavos.", { tipo: "valor", valor: "62.50" }],
    ["🎤 R$ 1.234,56.", { tipo: "valor", valor: "1234.56" }],
    ["sim", { tipo: "sim" }],
    ["Isso mesmo.", { tipo: "sim" }],
    ["não", { tipo: "nao" }],
    ["ok", { tipo: "ok" }],
    ["um", null],
    ["quanto deu o posto?", null],
    ["0", null],
  ]);
});

// ─── data ─────────────────────────────────────────────────────────────────────────────────

Deno.test("lerData: a tabela 3.4 (sem ano no futuro → ano anterior; com ano no futuro → não é data)", () => {
  const casos: Array<[string, string | null]> = [
    ["10/10", "2026-10-10"], ["10-10", "2026-10-10"], ["10/10/26", "2026-10-10"], ["10/10/2026", "2026-10-10"],
    ["hoje", "2026-10-11"], ["ontem", "2026-10-10"], ["anteontem", "2026-10-09"],
    ["12/10", "2025-10-12"], ["25/12", "2025-12-25"], ["12/10/2026", null], ["12/10/26", null],
    ["dia 10", "2026-10-10"], ["dia 15", "2026-09-15"], ["10 de outubro", "2026-10-10"], ["3 de marco", "2026-03-03"],
    ["foi ontem", "2026-10-10"], ["31/02", null], ["32/01", null], ["10/13", null], ["amanha", null], ["semana passada", null],
    ["1/9", "2026-09-01"], ["01/09/2025", "2025-09-01"],
  ];
  for (const [t, d] of casos) assertEquals(lerData(normalizarResposta(t), AGORA), d, t);
});

Deno.test("lerData: a virada do dia é a de São Paulo", () => {
  // 01:30 UTC de 12/10 ainda é 11/10 em São Paulo
  assertEquals(lerData("hoje", new Date("2026-10-12T01:30:00Z")), "2026-10-11");
});

Deno.test("passo data: data e sim/não/ok; o número de menu não vale", () => {
  tabela("data", [], [
    ["10/10", { tipo: "data", data: "2026-10-10" }],
    ["🎤 Ontem.", { tipo: "data", data: "2026-10-10" }],
    ["🎤 Dia 10 de outubro.", { tipo: "data", data: "2026-10-10" }],
    ["ok", { tipo: "ok" }],
    ["1", null],
  ]);
});

// ─── OS ───────────────────────────────────────────────────────────────────────────────────

Deno.test("lerOs: os 112, os-112, os112, OS-00112, da os 112", () => {
  for (const t of ["os 112", "os-112", "os112", "OS-00112", "da os 112", "🎤 OS 112.", "é da OS 112", "ordem 112"]) {
    assertEquals(lerOs(normalizarResposta(t)), 112, t);
  }
  for (const t of ["os", "os 0", "112", "lanca na os 112"]) assertEquals(lerOs(normalizarResposta(t)), null, t);
});

// ─── para quê ─────────────────────────────────────────────────────────────────────────────

Deno.test("passo para_que: opção, os N, número fora do menu, palavra, rótulo, nome do barco", () => {
  tabela("para_que", MENU_PARA_QUE, [
    ["1", { tipo: "opcao", n: 1 }],
    ["01", { tipo: "opcao", n: 1 }],
    ["um", { tipo: "opcao", n: 1 }],
    ["primeira", { tipo: "opcao", n: 1 }],
    ["opção 2", { tipo: "opcao", n: 2 }],
    ["opção dois", { tipo: "opcao", n: 2 }],
    ["número 3", { tipo: "opcao", n: 3 }],
    ["a 2", { tipo: "opcao", n: 2 }],
    ["o terceiro", { tipo: "opcao", n: 3 }],
    ["dois mesmo", { tipo: "opcao", n: 2 }],
    ["🎤 Um.", { tipo: "opcao", n: 1 }],
    ["🎤 Opção dois.", { tipo: "opcao", n: 2 }],
    ["🎤 A quarta.", { tipo: "opcao", n: 4 }],
    ["os 112", { tipo: "os", numero: 112 }],
    ["OS-00112", { tipo: "os", numero: 112 }],
    ["os112", { tipo: "os", numero: 112 }],
    ["112", { tipo: "os", numero: 112 }],
    ["8", { tipo: "os", numero: 8 }],
    ["estoque", { tipo: "palavra", valor: "estoque" }],
    ["Insumo", { tipo: "palavra", valor: "insumo" }],
    ["empresa", { tipo: "palavra", valor: "empresa" }],
    ["🎤 Pessoal.", { tipo: "palavra", valor: "pessoal" }],
    ["empresa (sem OS)", { tipo: "opcao", n: 6 }],
    ["Brisa", { tipo: "nome", texto: "brisa" }],
    ["🎤 Dona V.", { tipo: "nome", texto: "dona v" }],
    ["madu i", { tipo: "nome", texto: "madu i" }],
    ["sim", { tipo: "sim" }],
    ["ok", { tipo: "ok" }],
    // texto livre (vai ao assistente com a pergunta aberta)
    ["manda o orçamento do Brisa", null],
    ["quanto ficou a OS 123?", null],
    ["bom dia", null],
    ["lança isso na OS do Brisa e manda o PDF pro cliente agora", null],
    ["sim, mas é da OS 12", null],
    ["oi", null],
    ["12 de outubro", null],
  ]);
});

Deno.test("passo qual_os: os N, número puro, nome; com opções filtradas, o número do menu", () => {
  tabela("qual_os", [], [
    ["os 112", { tipo: "os", numero: 112 }],
    ["112", { tipo: "os", numero: 112 }],
    ["1", { tipo: "os", numero: 1 }],
    ["brisa", { tipo: "nome", texto: "brisa" }],
  ]);
  const filtradas = MENU_PARA_QUE.slice(0, 2);
  tabela("qual_os", filtradas, [["2", { tipo: "opcao", n: 2 }], ["🎤 A segunda.", { tipo: "opcao", n: 2 }], ["118", { tipo: "os", numero: 118 }]]);
});

// ─── como pagou / quem pagou / cobrar ─────────────────────────────────────────────────────

Deno.test("passo como_pagou: opção do menu fixo e as palavras de forma", () => {
  tabela("como_pagou", [], [
    ["1", { tipo: "opcao", n: 1 }],
    ["6", { tipo: "opcao", n: 6 }],
    ["7", null],
    ["pix", { tipo: "palavra", valor: "pix" }],
    ["Débito", { tipo: "palavra", valor: "debito" }],
    ["crédito", { tipo: "palavra", valor: "credito" }],
    ["dinheiro", { tipo: "palavra", valor: "dinheiro" }],
    ["espécie", { tipo: "palavra", valor: "dinheiro" }],
    ["boleto", { tipo: "palavra", valor: "boleto" }],
    ["transferência", { tipo: "palavra", valor: "transferencia" }],
    ["TED", { tipo: "palavra", valor: "transferencia" }],
    ["🎤 Foi no Pix.", { tipo: "palavra", valor: "pix" }],
    ["🎤 Cartão de crédito.", { tipo: "palavra", valor: "credito" }],
    ["cartão", null],
    ["estoque", null],
  ]);
});

Deno.test("passo quem_pagou: eu / do meu bolso = sócio; técnico; cliente; empresa", () => {
  tabela("quem_pagou", [], [
    ["1", { tipo: "opcao", n: 1 }],
    ["2", { tipo: "opcao", n: 2 }],
    ["eu", { tipo: "palavra", valor: "socio" }],
    ["do meu bolso", { tipo: "palavra", valor: "socio" }],
    ["🎤 Fui eu.", { tipo: "palavra", valor: "socio" }],
    ["sócio", { tipo: "palavra", valor: "socio" }],
    ["técnico", { tipo: "palavra", valor: "tecnico" }],
    ["o cliente pagou direto", { tipo: "palavra", valor: "cliente" }],
    ["cliente", { tipo: "palavra", valor: "cliente" }],
    ["a empresa", { tipo: "palavra", valor: "empresa" }],
    ["Roberto", null],
  ]);
  // com as opções do banco (sem o "cliente", destino ≠ os): o 4 não existe
  tabela("quem_pagou", [
    { n: 1, rotulo: "A empresa (dinheiro do Caixa)", valor: "empresa" },
    { n: 2, rotulo: "Eu, do meu bolso", valor: "socio" },
    { n: 3, rotulo: "Um técnico", valor: "tecnico" },
  ], [["4", null], ["3", { tipo: "opcao", n: 3 }]]);
});

Deno.test("passo cobrar: opção, sim/não, cobrar/custo e sinônimos", () => {
  tabela("cobrar", [], [
    ["1", { tipo: "opcao", n: 1 }],
    ["2", { tipo: "opcao", n: 2 }],
    ["3", null],
    ["sim", { tipo: "sim" }],
    ["não", { tipo: "nao" }],
    ["cobrar", { tipo: "palavra", valor: "cobrar" }],
    ["cobra", { tipo: "palavra", valor: "cobrar" }],
    ["cliente paga", { tipo: "palavra", valor: "cobrar" }],
    ["custo", { tipo: "palavra", valor: "custo" }],
    ["HBR", { tipo: "palavra", valor: "custo" }],
    ["por nossa conta", { tipo: "palavra", valor: "custo" }],
    ["da casa", { tipo: "palavra", valor: "custo" }],
    ["não cobrar", { tipo: "palavra", valor: "custo" }],
    ["🎤 Custo da HBR.", { tipo: "palavra", valor: "custo" }],
    ["🎤 Cobra do cliente.", { tipo: "palavra", valor: "cobrar" }],
  ]);
});

// ─── técnico / categoria / corrigir ───────────────────────────────────────────────────────

Deno.test("passo qual_tecnico e categoria: opção, rótulo exato, nome", () => {
  const tecnicos: Opcao[] = [{ n: 1, rotulo: "Roberto", valor: "payee:1" }, { n: 2, rotulo: "Felipe", valor: "payee:2" }];
  tabela("qual_tecnico", tecnicos, [["2", { tipo: "opcao", n: 2 }], ["Felipe", { tipo: "opcao", n: 2 }], ["alex", { tipo: "nome", texto: "alex" }]]);
  tabela("categoria", [], [
    ["1", { tipo: "opcao", n: 1 }],
    ["8", { tipo: "opcao", n: 8 }],
    ["Outras despesas", { tipo: "opcao", n: 8 }],
    ["🎤 Alimentação de campo.", { tipo: "opcao", n: 2 }],
    ["material de limpeza", { tipo: "nome", texto: "material de limpeza" }],
  ]);
});

Deno.test("passo corrigir: 1-9 e as palavras do menu (Categoria entrou na revisão de 11/10/2026)", () => {
  assertEquals(opcoesDoPasso("corrigir", []), MENU_CORRIGIR);
  assertEquals(MENU_CORRIGIR.length, 9);
  tabela("corrigir", [], [
    ["1", { tipo: "opcao", n: 1 }],
    ["9", { tipo: "opcao", n: 9 }],
    ["valor", { tipo: "opcao", n: 1 }],
    ["a data", { tipo: "opcao", n: 2 }],
    ["quem pagou", { tipo: "opcao", n: 5 }],
    ["categoria", { tipo: "opcao", n: 7 }],
    ["cancelar", { tipo: "opcao", n: 8 }],
    ["depois", { tipo: "opcao", n: 9 }],
    ["🎤 Deixa pra depois.", { tipo: "opcao", n: 9 }],
    ["10", null],
  ]);
});

// ─── confirmar ────────────────────────────────────────────────────────────────────────────

Deno.test("passo confirmar: só sim/não; ok, número e mensagem curta viram 'ok' (nunca aprovam, nunca escapam ao assistente)", () => {
  tabela("confirmar", [], [
    ["sim", { tipo: "sim" }],
    ["Sim, pode gravar.", { tipo: "sim" }],
    ["🎤 Sim.", { tipo: "sim" }],
    // revisão de 11/10/2026: as confirmações faladas de verdade
    ["🎤 Isso mesmo, pode gravar.", { tipo: "sim" }],
    ["pode", { tipo: "sim" }],
    ["simm", { tipo: "sim" }],
    ["correto", { tipo: "sim" }],
    ["grava", { tipo: "sim" }],
    ["não", { tipo: "nao" }],
    ["🎤 Não, tá errado.", { tipo: "nao" }],
    ["ok", { tipo: "ok" }],
    ["👍", { tipo: "ok" }],
    ["beleza", { tipo: "ok" }],
    ["1", { tipo: "ok" }],
    ["um", { tipo: "ok" }],
    // sim + texto a mais e mensagem curta: pede o sim de novo (com a dica do corrigir), nunca aprova
    ["sim, mas é da OS 12", { tipo: "ok" }],
    ["62,50", { tipo: "ok" }],
    // pergunta ou frase longa: é conversa, vai ao assistente
    ["o que é isso?", null],
    ["quanto custou a peça do brisa ontem no total geral", null],
  ]);
});

// ─── comandos ─────────────────────────────────────────────────────────────────────────────

Deno.test("lerComando: os da 3.4 e a classe de cada um", () => {
  const casos: Array<[string, unknown, string | null]> = [
    ["pendentes", { comando: "pendentes" }, "pendentes"],
    ["Pendências", { comando: "pendentes" }, "pendentes"],
    ["🎤 Pendentes.", { comando: "pendentes" }, "pendentes"],
    ["cmp 124", { comando: "cmp", numero: 124 }, "comprovante"],
    ["CMP-00124", { comando: "cmp", numero: 124 }, "comprovante"],
    ["cmp124", { comando: "cmp", numero: 124 }, "comprovante"],
    ["cancelar cmp 124 comprei em dobro", { comando: "cancelar", numero: 124, motivo: "comprei em dobro" }, "comprovante"],
    ["Cancelar CMP-00124: Comprei em DOBRO.", { comando: "cancelar", numero: 124, motivo: "Comprei em DOBRO" }, "comprovante"],
    ["🎤 Cancela o CMP 124, foi lançado errado.", { comando: "cancelar", numero: 124, motivo: "foi lançado errado" }, "comprovante"],
    ["cancelar cmp 124", { comando: "cancelar", numero: 124, motivo: null }, "comprovante"],
    ["feito cmp 119", { comando: "feito", numero: 119 }, "comprovante"],
    ["lote antigo", { comando: "lote_antigo" }, "comprovante"],
    ["pular", { comando: "pular" }, "contexto"],
    ["sair", { comando: "sair" }, "contexto"],
    ["Parar.", { comando: "sair" }, "contexto"],
    ["corrigir valor 62,50", { comando: "corrigir", campo: "valor", valor: "62.50" }, "contexto"],
    ["corrigir valor para R$ 1.234,56", { comando: "corrigir", campo: "valor", valor: "1234.56" }, "contexto"],
    ["corrigir data 10/10", { comando: "corrigir", campo: "data", data: "2026-10-10" }, "contexto"],
    ["corrigir data ontem", { comando: "corrigir", campo: "data", data: "2026-10-10" }, "contexto"],
    ["corrigir forma pix", { comando: "corrigir", campo: "forma", forma: "pix" }, "contexto"],
    ["corrigir forma débito", { comando: "corrigir", campo: "forma", forma: "debito" }, "contexto"],
    ["corrigir forma transferência", { comando: "corrigir", campo: "forma", forma: "transferencia" }, "contexto"],
    ["corrigir os 112", { comando: "corrigir", campo: "os", numero: 112 }, "contexto"],
    ["corrigir OS-00112", { comando: "corrigir", campo: "os", numero: 112 }, "contexto"],
    ["corrigir quem", { comando: "corrigir", campo: "quem" }, "contexto"],
    ["corrigir quem pagou", { comando: "corrigir", campo: "quem" }, "contexto"],
    ["corrigir para", { comando: "corrigir", campo: "para" }, "contexto"],
    ["🎤 Corrigir valor 62 reais.", { comando: "corrigir", campo: "valor", valor: "62.00" }, "contexto"],
    ["corrigir valor", { comando: "corrigir_incompleto", campo: "valor" }, "contexto"],
    ["corrigir forma cartão", { comando: "corrigir_incompleto", campo: "forma" }, "contexto"],
    ["corrigir os", { comando: "corrigir_incompleto", campo: "os" }, "contexto"],
  ];
  for (const [t, c, classe] of casos) {
    const lido = lerComando(t, AGORA);
    assertEquals(lido, c, t);
    assertEquals(classeDoComando(lido), classe, t);
  }
});

Deno.test("lerComando: o que NÃO é comando", () => {
  for (const t of [
    "sim, mas é da OS 12", "sim", "1", "quais são as pendências do financeiro?", "cmp", "o cmp 124 é do Brisa", "cancelar o pedido",
    "corrigir o orçamento do Brisa", "pula essa e manda o próximo", "para", "feito", "pendentes do financeiro",
  ]) {
    assertEquals(lerComando(t, AGORA), null, t);
  }
  // "corrigir" sozinho (revisão de 11/10/2026) abre o menu do corrigir em vez de ir ao assistente
  assertEquals(lerComando("corrigir", AGORA), { comando: "corrigir_menu" });
  assertEquals(classeDoComando(lerComando("corrigir", AGORA)), "contexto");
});

// ─── revisão de 11/10/2026: as respostas reais que davam null (e caíam no assistente) ────────

Deno.test("eco do menu, ordinais e frases faladas valem no passo (uma palavra-chave só)", () => {
  tabela("como_pagou", MENU_COMO_PAGOU, [
    ["1 pix", { tipo: "opcao", n: 1 }],
    ["4 - dinheiro", { tipo: "opcao", n: 4 }],
    ["2) débito", { tipo: "opcao", n: 2 }],
    ["1 dinheiro", null], // número e rótulo que não batem: não é resposta
    ["segunda opção", { tipo: "opcao", n: 2 }],
    ["primeira opção", { tipo: "opcao", n: 1 }],
    ["foi no cartão de débito", { tipo: "palavra", valor: "debito" }],
    ["paguei no débito", { tipo: "palavra", valor: "debito" }],
    ["foi no pix e no débito", null], // duas palavras-chave: não adivinha
  ]);
  tabela("para_que", MENU_PARA_QUE, [
    ["É o Brisa", { tipo: "nome", texto: "brisa" }],
    ["é pro estoque", { tipo: "palavra", valor: "estoque" }],
    ["4 - estoque", { tipo: "opcao", n: 4 }],
  ]);
  tabela("cobrar", MENU_COBRAR, [
    ["pode cobrar", { tipo: "palavra", valor: "cobrar" }],
    ["cobra sim", { tipo: "palavra", valor: "cobrar" }],
    ["é custo nosso", { tipo: "palavra", valor: "custo" }],
    ["por conta da casa", { tipo: "palavra", valor: "custo" }],
    ["não cobra", { tipo: "palavra", valor: "custo" }],
  ]);
  tabela("quem_pagou", MENU_QUEM_PAGOU, [
    ["eu paguei do meu bolso", { tipo: "palavra", valor: "socio" }],
    ["foi o técnico", { tipo: "palavra", valor: "tecnico" }],
    ["o cliente pagou", { tipo: "palavra", valor: "cliente" }],
  ]);
});

Deno.test("passo mesma_compra: número, sim/não e as palavras 'mesma'/'outra'", () => {
  tabela("mesma_compra", MENU_MESMA_COMPRA, [
    ["1", { tipo: "opcao", n: 1 }],
    ["2", { tipo: "opcao", n: 2 }],
    ["é a mesma", { tipo: "opcao", n: 1 }],
    ["outra", { tipo: "opcao", n: 2 }],
    ["sim", { tipo: "sim" }],
    ["não", { tipo: "nao" }],
  ]);
});

Deno.test("passo valor: 'certo'/'correto' confirmam o valor lido", () => {
  tabela("valor", [], [
    ["certo", { tipo: "sim" }],
    ["correto", { tipo: "sim" }],
    ["62,50", { tipo: "valor", valor: "62.50" }],
  ]);
});

Deno.test("lerComando: correções faladas, cmp por extenso e adiamento", () => {
  const casos: Array<[string, unknown]> = [
    ["corrige o valor pra 62,50", { comando: "corrigir", campo: "valor", valor: "62.50" }],
    ["corrigir valor: 62,50", { comando: "corrigir", campo: "valor", valor: "62.50" }],
    ["corrigir para estoque", { comando: "corrigir", campo: "para", destino: "estoque" }],
    ["corrigir pix", { comando: "corrigir", campo: "forma", forma: "pix" }],
    ["corrigir categoria", { comando: "corrigir", campo: "categoria" }],
    ["corrigir cmp 124 valor 62,50", { comando: "corrigir", campo: "valor", valor: "62.50", cmp: 124 }],
    ["c.m.p. 124", { comando: "cmp", numero: 124 }],
    ["comprovante 124", { comando: "cmp", numero: 124 }],
    ["pula esse", { comando: "pular" }],
    ["mais tarde", { comando: "pular" }],
    ["depois", { comando: "pular" }],
    ["cancela esse comprei em dobro", { comando: "cancelar_contexto", motivo: "comprei em dobro" }],
  ];
  for (const [t, c] of casos) assertEquals(lerComando(t, AGORA), c, t);
  assertEquals(classeDoComando(lerComando("cancela esse", AGORA)), "contexto");
});

// ─── F3: a pergunta do extrato (spec-f3.md, 4.2) ─────────────────────────────────────────

const VERDE: Opcao[] = [{ n: 1, rotulo: "C6 - Conta PJ HBR · 08/10 · DEBITO DE CARTAO · R$ 50,98", valor: "tx:t-1" }];
const AZUL: Opcao[] = [
  { n: 1, rotulo: "C6 - Conta PJ HBR · 08/10 · DEBITO DE CARTAO · R$ 50,98", valor: "tx:t-1" },
  { n: 2, rotulo: "C6 - Conta PJ HBR · 09/10 · DEBITO DE CARTAO · R$ 50,98", valor: "tx:t-2" },
  { n: 3, rotulo: "C6 - Conta PJ HBR · 10/10 · DEBITO DE CARTAO · R$ 50,98", valor: "tx:t-3" },
  { n: 0, rotulo: "Nenhuma destas", valor: "nenhum" },
];
const doExtrato = (opcoes: Opcao[], t: string) => interpretarResposta("banco", opcoes, t, AGORA);

Deno.test("F3 parser, verde: sim liga, não/'não é essa'/0 recusa, número e ok nunca ligam (viram ok)", () => {
  for (const t of ["sim", "Sim!", "🎤 Sim.", "isso mesmo", "pode"]) assertEquals(doExtrato(VERDE, t), { tipo: "sim" }, t);
  for (const t of ["não", "nao", "Não é essa.", "nao e esse", "0", "zero", "nenhuma", "Nenhuma destas."]) {
    assertEquals(doExtrato(VERDE, t), { tipo: "nao" }, t);
  }
  // número nunca liga no verde: volta "ok" (o banco pede o sim de novo)
  for (const t of ["1", "um", "opção 1", "2", "ok", "beleza", "👍"]) assertEquals(doExtrato(VERDE, t), { tipo: "ok" }, t);
  for (const t of ["quanto deu o extrato do C6?", "manda o orçamento do Brisa", "sim, mas é da OS 12"]) assertEquals(doExtrato(VERDE, t), null, t);
});

Deno.test("F3 parser, azul: o número da linha, 0 e 'nenhuma destas' = não; sim/ok e número fora da lista viram pedido do número", () => {
  for (const [t, n] of [["2", 2], ["🎤 Dois.", 2], ["opção 3", 3], ["a 1", 1], ["primeira", 1], ["é a 2", 2]] as Array<[string, number]>) {
    assertEquals(doExtrato(AZUL, t), { tipo: "opcao", n }, t);
  }
  const nenhuma = ["0", "0.", "zero", "nenhum", "nenhuma", "nenhum desses", "Nenhuma dessas.", "nenhuma destas", "nenhum destes",
    "não é nenhum", "não é nenhuma", "não é essa", "não é esse", "não", "🎤 Nenhuma destas."];
  for (const t of nenhuma) assertEquals(doExtrato(AZUL, t), { tipo: "nao" }, t);
  assertEquals(doExtrato(AZUL, "sim"), { tipo: "sim" });
  assertEquals(doExtrato(AZUL, "ok"), { tipo: "ok" });
  // fora da lista (só há 1 a 3): não escapa ao assistente, o banco pede o número de novo
  assertEquals(doExtrato(AZUL, "4"), { tipo: "ok" });
  assertEquals(doExtrato(AZUL, "quanto deu o extrato?"), null);
  // sem opções fixas: valem só as que a pergunta trouxe
  assertEquals(opcoesDoPasso("banco", []), []);
  assertEquals(opcoesDoPasso("banco", AZUL), AZUL);
});

Deno.test("pareceDica e respostaNaoEntendida: o texto solto depois da foto e a mensagem curta sem sentido", () => {
  for (const t of ["essa é da OS do Brisa", "gasolina do Brisa", "material da OS 112"]) assertEquals(pareceDica(t), true, t);
  for (const t of ["bom dia", "quanto ficou a OS 123?", "obrigado"]) assertEquals(pareceDica(t), false, t);
  for (const t of ["hmm", "asdf"]) assertEquals(respostaNaoEntendida(t), true, t);
  for (const t of ["quanto ficou a OS 123?", "manda o orçamento do Brisa pro cliente amanhã cedo", "bom dia", "?"]) {
    assertEquals(respostaNaoEntendida(t), false, t);
  }
});
