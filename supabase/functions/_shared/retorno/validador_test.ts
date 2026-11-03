// Testes do validador do retorno (P10, F1, 16/11/2026).
//
// Cada regra tem um teste NEGATIVO que prova o bloqueio com um texto que só viola aquela regra (o
// resultado é exatamente `[regra]`), e cada palavra proibida de B.4.3 tem o seu. Do outro lado, cada
// texto fixo T01–T28 e a linha de risco L01 (spec P3.1), montados com dados de exemplo e com o
// contexto que o retorno_pegar montaria (spec P6.2, passo 8), PASSA: o validador nunca barra o texto
// que o próprio banco escreve. Se alguém mudar um modelo no SQL, este teste é o lembrete de copiar a
// mudança para cá.
//
// Reverter: apagar este arquivo junto com validador.ts.

import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  type ContextoDoValidador,
  LIMITE_DE_CARACTERES,
  type RegraDoValidador,
  validarSaida,
} from "./validador.ts";

// ─── Os textos fixos (spec P3.1, literais) ───────────────────────────────────────────────────────

const MODELOS: Record<string, string> = {
  T01: "Oi, {nome} (mensagem automática da HBR). Recebi e passei ao Gustavo; ele te responde {quando} até as {hora}.",
  T02: "Oi, {nome}! Aqui é o assistente da HBR (mensagem automática). Recebi e passei ao Gustavo; ele te responde {quando} até as {hora}.",
  T03: "Oi! Aqui é o assistente da HBR (mensagem automática). Recebi sua mensagem e passei ao Gustavo; ele te responde {quando} até as {hora}.",
  T04: "Recebi, {nome} (mensagem automática da HBR). O Gustavo te responde {quando} até as {hora}. Se não puder esperar, escreva URGENTE que eu aviso o Gustavo.",
  T05: "Oi, {nome}! Aqui é o assistente da HBR (mensagem automática). Recebi sua mensagem; o Gustavo te responde {quando} até as {hora}. Se não puder esperar, escreva URGENTE que eu aviso o Gustavo.",
  T06: "Oi! Aqui é o assistente da HBR (mensagem automática). Recebi sua mensagem; o Gustavo te responde {quando} até as {hora}. Se não puder esperar, escreva URGENTE que eu aviso o Gustavo.",
  T07: "Bom dia, {nome} (mensagem automática da HBR). Recebi sua mensagem {de_quando}. O Gustavo te responde até as {hora}.",
  T08: "Bom dia, {nome} (mensagem automática da HBR). Recebi sua mensagem {de_quando}. O Gustavo te responde {quando} até as {hora}.",
  T09: "Bom dia! Aqui é o assistente da HBR (mensagem automática). Recebi sua mensagem {de_quando}. O Gustavo te responde {quando} até as {hora}.",
  T10: "Recebi, {nome} (mensagem automática da HBR). O Gustavo está fora até {quando}; ele te responde {quando} até as {hora}.",
  T11: "Oi! Aqui é o assistente da HBR (mensagem automática). Recebi sua mensagem. O Gustavo está fora até {quando}; ele te responde {quando} até as {hora}.",
  T12: "Oi, {nome} (mensagem automática da HBR). Sua mensagem de {dia_msg} às {hora_msg} só chegou para nós agora. Desculpe a demora. O Gustavo te responde {quando} até as {hora}.",
  T13: "Oi, {nome} (mensagem automática da HBR). Nosso WhatsApp ficou fora do ar, e sua mensagem de {dia_msg} às {hora_msg} só chegou agora. Desculpe a demora. O Gustavo te responde {quando} até as {hora}.",
  T14: "Oi! Aqui é o assistente da HBR (mensagem automática). Recebi sua mensagem e passei ao Gustavo; ele te responde {quando} até as {hora}.",
  T15: "{cumprimento}! Aqui é o assistente da HBR (mensagem automática). Recebi seu pedido e já passei ao Gustavo, que faz os orçamentos; ele te responde {quando} até as {hora}. Pra adiantar: me conta o que você precisa resolver ou instalar (pode ser por áudio).",
  T16: "{cumprimento}! Aqui é o assistente da HBR (mensagem automática). Recebi seu pedido e já passei ao Gustavo, que faz os orçamentos; ele te responde {quando} até as {hora}. Pra adiantar: qual o modelo e o ano {do_bem}?",
  T17: "{cumprimento}! Aqui é o assistente da HBR (mensagem automática). Recebi seu pedido e já passei ao Gustavo, que faz os orçamentos; ele te responde {quando} até as {hora}.",
  T18: "Obrigado! Já passei ao Gustavo. Como posso te chamar?",
  T19: "{cumprimento}! Aqui é o assistente da HBR (mensagem automática). Em que posso te ajudar? Pode ser por áudio.",
  T20: "{nome}, o Gustavo ainda não conseguiu te responder. Seu pedido está anotado, e a resposta sai até as {hora}. Se não puder esperar, escreva URGENTE que eu aviso o Gustavo.",
  T21: "O Gustavo ainda não conseguiu te responder. Seu pedido está anotado, e a resposta sai até as {hora}. Se não puder esperar, escreva URGENTE que eu aviso o Gustavo.",
  T22: "{nome}, o Gustavo não conseguiu te responder hoje, desculpe. Seu pedido abre a lista dele {quando_lista} cedo.",
  T23: "O Gustavo não conseguiu te responder hoje, desculpe. Seu pedido abre a lista dele {quando_lista} cedo.",
  T24: "Avisei o Gustavo agora, {nome}.",
  T25: "Anotado como urgente, {nome}. O Gustavo vê {quando_lista} cedo, antes de tudo.",
  T26: "Anotado como urgente. O Gustavo vê {quando_lista} cedo, antes de tudo.",
  T27: "Combinado, {nome}: não te mando mais mensagens automáticas. Se precisar, é só escrever.",
  T28: "Combinado: não te mando mais mensagens automáticas. Se precisar, é só escrever.",
};
const L01 = "Se houver fogo, fumaça ou água entrando, ligue 193 (Bombeiros).";

type Dados = Record<string, string>;
type Marcas = ContextoDoValidador["marcas"];

const SEM_MARCAS: Marcas = { tem_proposta: false, tem_topo: false, cliente_ouviu: false, conferida: false };

/** Troca cada {campo} pelo valor; campo sem valor é erro do teste (como o 22023 do banco). */
function compor(modelo: string, dados: Dados): string {
  return modelo.replace(/\{([a-z_]+)\}/g, (_, campo: string) => {
    const v = dados[campo];
    if (!v) throw new Error(`teste sem o campo ${campo}`);
    return v;
  });
}

/** O modelo sem os {campos}: o trechos_do_modelo do banco. */
function trechos(modelo: string): string[] {
  return modelo.split(/\{[a-z_]+\}/).filter((s) => s !== "");
}

/**
 * O contexto que o retorno_pegar monta (spec P6.2, passo 8): as datas que o banco pôs (quando,
 * quando_lista, dia_msg e a dd/mm de dentro delas), mais "hoje", "amanhã" e "ontem" quando estão no
 * modelo ou num valor que o banco escolheu (de_quando); as horas (hora, hora_msg); o nome; nenhuma OS.
 */
function contextoDoPegar(
  modelo: string,
  dados: Dados,
  extra: Partial<ContextoDoValidador> = {},
): ContextoDoValidador {
  const datas = new Set<string>();
  for (const campo of ["quando", "quando_lista", "dia_msg"]) {
    const v = dados[campo];
    if (!v) continue;
    datas.add(v);
    const ddmm = v.match(/\d{2}\/\d{2}/);
    if (ddmm) datas.add(ddmm[0]);
  }
  for (const palavra of ["hoje", "amanhã", "ontem"]) {
    if (modelo.includes(palavra) || Object.values(dados).some((v) => v.includes(palavra))) datas.add(palavra);
  }
  return {
    audiencia: "cliente",
    datas_permitidas: [...datas],
    horas_permitidas: ["hora", "hora_msg"].map((c) => dados[c]).filter((v): v is string => !!v),
    nome_permitido: dados.nome ?? null,
    nomes_de_outros: [],
    os_permitidas: [],
    textos_do_cliente: ["Bom dia, a bateria do motorhome não está segurando carga", "consegue ver essa semana?"],
    trechos_do_modelo: trechos(modelo),
    marcas: { ...SEM_MARCAS },
    ...extra,
  };
}

/** Todas as combinações dos valores de cada campo. */
function combinar(opcoes: Record<string, string[]>): Dados[] {
  let r: Dados[] = [{}];
  for (const [campo, valores] of Object.entries(opcoes)) {
    r = r.flatMap((d) => valores.map((v) => ({ ...d, [campo]: v })));
  }
  return r;
}

// Valores de exemplo, nas listas fechadas do _retorno_texto (spec P3.1).
const NOMES = ["Lenine", "Maximiliano Bartolomeu Albuquerque Rocha"]; // o maior nome: 40 caracteres
const QUANDO = ["hoje", "amanhã", "segunda (09/11)"];
const QUANDO_OUTRO_DIA = ["amanhã", "segunda (09/11)", "terça (10/11)", "sábado (14/11)"];
const HORA = ["19h", "10h", "14h", "10:30"];
const CUMPRIMENTO = ["Bom dia", "Boa tarde", "Boa noite"];
const DE_QUANDO = ["de ontem à noite", "desta madrugada"];
const DIA_MSG = ["sábado (31/10)", "domingo (01/11)", "quarta (04/11)"];
const HORA_MSG = ["21:40", "23h", "07:05"];
const DO_BEM = ["do motorhome", "da lancha", "do veículo", "do carro"];

interface Caso {
  id: string;
  opcoes: Record<string, string[]>;
  extra?: Partial<ContextoDoValidador>;
}

// O cliente que escreve as mesmas palavras que o banco preenche nos {campos} (cumprimento, quando,
// hora, nome, de_quando) não faz o texto do banco virar eco (R1-12).
const PEDRO = "Boa tarde, aqui é o Pedro, queria um orçamento";
const DE_ONTEM = "Bom dia, viu minha mensagem de ontem à noite?";

const CASOS: Caso[] = [
  { id: "T01", opcoes: { nome: NOMES, quando: QUANDO, hora: HORA }, extra: { textos_do_cliente: ["vc me responde hoje até as 19h?"] } },
  {
    id: "T02",
    opcoes: { nome: NOMES, quando: QUANDO, hora: HORA },
    extra: { textos_do_cliente: ["Boa tarde, sou o Maximiliano Bartolomeu Albuquerque Rocha"] },
  },
  { id: "T03", opcoes: { quando: QUANDO, hora: HORA } },
  { id: "T04", opcoes: { nome: NOMES, quando: QUANDO_OUTRO_DIA, hora: HORA } },
  { id: "T05", opcoes: { nome: NOMES, quando: QUANDO_OUTRO_DIA, hora: HORA } },
  { id: "T06", opcoes: { quando: QUANDO_OUTRO_DIA, hora: HORA } },
  { id: "T07", opcoes: { nome: NOMES, de_quando: DE_QUANDO, hora: HORA }, extra: { textos_do_cliente: [DE_ONTEM] } },
  {
    id: "T08",
    opcoes: { nome: NOMES, de_quando: DE_QUANDO, quando: QUANDO_OUTRO_DIA, hora: HORA },
    extra: { textos_do_cliente: [DE_ONTEM] },
  },
  {
    id: "T09",
    opcoes: { de_quando: DE_QUANDO, quando: QUANDO_OUTRO_DIA, hora: HORA },
    extra: { textos_do_cliente: [DE_ONTEM] },
  },
  { id: "T10", opcoes: { nome: NOMES, quando: QUANDO_OUTRO_DIA, hora: ["10h"] } },
  { id: "T11", opcoes: { quando: QUANDO_OUTRO_DIA, hora: ["10h"] } },
  {
    id: "T12",
    opcoes: { nome: NOMES, dia_msg: DIA_MSG, hora_msg: HORA_MSG, quando: QUANDO, hora: HORA },
    extra: { textos_do_cliente: ["Oi, o inversor parou de novo, consegue olhar?"] },
  },
  {
    id: "T13",
    opcoes: { nome: NOMES, dia_msg: DIA_MSG, hora_msg: HORA_MSG, quando: QUANDO, hora: HORA },
    extra: { textos_do_cliente: ["Oi, o inversor parou de novo, consegue olhar?"] },
  },
  {
    // Recibo ambíguo: sem nome, e os nomes curtos dos clientes do número como "de outros".
    id: "T14",
    opcoes: { quando: QUANDO, hora: HORA },
    extra: { nomes_de_outros: ["Lenine", "Marcos"], nome_permitido: null },
  },
  {
    id: "T15",
    opcoes: { cumprimento: CUMPRIMENTO, quando: QUANDO, hora: HORA },
    extra: { textos_do_cliente: ["Boa tarde, vocês fazem instalação de placa solar em motorhome?", PEDRO] },
  },
  {
    id: "T16",
    opcoes: { cumprimento: CUMPRIMENTO, quando: QUANDO, hora: HORA, do_bem: DO_BEM },
    extra: { textos_do_cliente: ["Quero instalar um inversor, quanto fica?", PEDRO] },
  },
  {
    id: "T17",
    opcoes: { cumprimento: CUMPRIMENTO, quando: QUANDO, hora: HORA },
    extra: { textos_do_cliente: ["Preciso trocar as baterias da lancha, Ducato 2019", PEDRO] },
  },
  { id: "T18", opcoes: {}, extra: { textos_do_cliente: ["Quero instalar um inversor na lancha"] } },
  {
    id: "T19",
    opcoes: { cumprimento: CUMPRIMENTO },
    extra: { textos_do_cliente: ["Bom dia, tudo bem?", PEDRO, "Bom dia, aqui é o João da lancha Netuno"] },
  },
  {
    // O cliente escreveu um pedaço igual ao modelo fixo: é do modelo, não é eco.
    id: "T20",
    opcoes: { nome: NOMES, hora: HORA },
    extra: { textos_do_cliente: ["Pelo jeito o Gustavo ainda não conseguiu te responder, né"] },
  },
  {
    id: "T21",
    opcoes: { hora: HORA },
    extra: { textos_do_cliente: ["o Gustavo ainda não conseguiu te responder?"] },
  },
  // fim_do_dia e urgente: o retorno_pegar grava topo_dia antes, e a marca vai junto (tem_topo).
  { id: "T22", opcoes: { nome: NOMES, quando_lista: QUANDO_OUTRO_DIA }, extra: { marcas: { ...SEM_MARCAS, tem_topo: true } } },
  { id: "T23", opcoes: { quando_lista: QUANDO_OUTRO_DIA }, extra: { marcas: { ...SEM_MARCAS, tem_topo: true } } },
  {
    id: "T24",
    opcoes: { nome: NOMES },
    extra: { marcas: { ...SEM_MARCAS, tem_topo: true }, textos_do_cliente: ["URGENTE"] },
  },
  {
    id: "T25",
    opcoes: { nome: NOMES, quando_lista: QUANDO_OUTRO_DIA },
    extra: { marcas: { ...SEM_MARCAS, tem_topo: true }, textos_do_cliente: ["URGENTE, o barco está sem bateria"] },
  },
  {
    id: "T26",
    opcoes: { quando_lista: QUANDO_OUTRO_DIA },
    extra: { marcas: { ...SEM_MARCAS, tem_topo: true }, textos_do_cliente: ["urgente"] },
  },
  { id: "T27", opcoes: { nome: NOMES }, extra: { textos_do_cliente: ["PARAR"] } },
  { id: "T28", opcoes: {}, extra: { textos_do_cliente: ["Pare"] } },
];

// ─── Positivos: todo texto fixo passa ────────────────────────────────────────────────────────────

Deno.test("a lista de casos cobre T01–T28, sem faltar nem sobrar", () => {
  assertEquals(CASOS.map((c) => c.id), Object.keys(MODELOS));
  assertEquals(Object.keys(MODELOS).length, 28);
});

for (const caso of CASOS) {
  Deno.test(`${caso.id} passa com os dados de exemplo e o contexto do retorno_pegar`, () => {
    const modelo = MODELOS[caso.id];
    const variantes = combinar(caso.opcoes);
    assert(variantes.length >= 1);
    for (const dados of variantes) {
      const texto = compor(modelo, dados);
      const r = validarSaida(texto, contextoDoPegar(modelo, dados, caso.extra));
      assertEquals(r, { ok: true }, `${caso.id}: ${texto}`);
    }
  });
}

Deno.test("L01 passa sozinha e no fim dos recibo_* (risco), com os maiores valores", () => {
  assertEquals(validarSaida(L01, contextoDoPegar(L01, {})), { ok: true });
  for (const id of ["T01", "T03", "T04", "T07", "T12", "T13", "T14", "T15", "T16", "T17"]) {
    // _retorno_texto acrescenta E'\n' + L01 nos recibo_* com risco.
    const modelo = MODELOS[id] + "\n" + L01;
    const dados: Dados = {
      nome: NOMES[1], quando: "segunda (09/11)", hora: "10:30", cumprimento: "Boa noite",
      de_quando: "de ontem à noite", dia_msg: "domingo (01/11)", hora_msg: "21:40", do_bem: "do motorhome",
    };
    const texto = compor(modelo, dados);
    assert(texto.length <= LIMITE_DE_CARACTERES, `${id} com L01 tem ${texto.length} caracteres`);
    const extra = id === "T14" ? { nomes_de_outros: ["Lenine", "Marcos"], nome_permitido: null } : {};
    assertEquals(validarSaida(texto, contextoDoPegar(modelo, dados, extra)), { ok: true }, texto);
  }
});

Deno.test("T22 sem a marca de topo não sai: 'abre a lista dele' exige o topo_dia gravado", () => {
  const dados = { nome: "Lenine", quando_lista: "amanhã" };
  const texto = compor(MODELOS.T22, dados);
  assertEquals(validarSaida(texto, contextoDoPegar(MODELOS.T22, dados)), {
    ok: false,
    regras: ["afirmacao_sem_dado"],
  });
});

// ─── Negativos: um texto que só viola a regra ────────────────────────────────────────────────────

const BASE = compor(MODELOS.T01, { nome: "Lenine", quando: "hoje", hora: "19h" });

function ctxBase(extra: Partial<ContextoDoValidador> = {}): ContextoDoValidador {
  return contextoDoPegar(MODELOS.T01, { nome: "Lenine", quando: "hoje", hora: "19h" }, extra);
}

/** O texto reprova, e só pela regra pedida. */
function so(regra: RegraDoValidador, texto: string, ctx: ContextoDoValidador | null | undefined = ctxBase()) {
  assertEquals(validarSaida(texto, ctx), { ok: false, regras: [regra] }, `"${texto}" devia falhar só em ${regra}`);
}

Deno.test("o texto de base dos negativos passa (o bloqueio vem só do que cada teste acrescenta)", () => {
  assertEquals(BASE, "Oi, Lenine (mensagem automática da HBR). Recebi e passei ao Gustavo; ele te responde hoje até as 19h.");
  assertEquals(validarSaida(BASE, ctxBase()), { ok: true });
});

Deno.test("vazio: texto vazio, só espaço ou só caractere invisível", () => {
  so("vazio", "");
  so("vazio", "   \n\t ");
  so("vazio", "\u200b\u00a0\ufeff");
  // texto que não é string (nulo vindo do JSON) também nunca sai, e não lança
  so("vazio", null as unknown as string);
  so("vazio", 42 as unknown as string);
});

Deno.test("contexto: ausente, de outro tipo, com campo faltando ou de tipo errado", () => {
  const texto = compor(MODELOS.T18, {}); // sem data, hora, nome nem afirmação
  so("contexto", texto, null);
  // undefined direto: passado ao `so`, o parâmetro padrão o trocaria pelo contexto de base
  assertEquals(validarSaida(texto, undefined), { ok: false, regras: ["contexto"] });
  so("contexto", texto, "cliente" as unknown as ContextoDoValidador);
  so("contexto", texto, [] as unknown as ContextoDoValidador);
  so("contexto", texto, {} as unknown as ContextoDoValidador);
  const campos = [
    "audiencia", "datas_permitidas", "horas_permitidas", "nome_permitido", "nomes_de_outros",
    "os_permitidas", "textos_do_cliente", "trechos_do_modelo", "marcas",
  ];
  for (const campo of campos) {
    const ctx = ctxBase() as unknown as Record<string, unknown>;
    delete ctx[campo];
    so("contexto", texto, ctx as unknown as ContextoDoValidador);
  }
  const errados: Array<[string, unknown]> = [
    ["audiencia", 1],
    ["datas_permitidas", "hoje"],
    ["horas_permitidas", ["19h", 19]],
    ["nome_permitido", 7],
    ["nomes_de_outros", null],
    ["os_permitidas", [null]],
    ["textos_do_cliente", "oi"],
    ["trechos_do_modelo", {}],
    ["marcas", null],
    ["marcas", { tem_proposta: false, tem_topo: false, cliente_ouviu: false }],
    ["marcas", { tem_proposta: false, tem_topo: "true", cliente_ouviu: false, conferida: false }],
  ];
  for (const [campo, valor] of errados) {
    const ctx = { ...ctxBase(), [campo]: valor } as unknown as ContextoDoValidador;
    const r = validarSaida(texto, ctx);
    assertEquals(r.ok, false, `${campo} = ${JSON.stringify(valor)}`);
    if (!r.ok) assert(r.regras.includes("contexto"), `${campo} = ${JSON.stringify(valor)}: ${r.regras}`);
  }
});

Deno.test("contexto null: a resposta é 'contexto' (e as outras regras ainda correm, com lista vazia)", () => {
  so("contexto", "Obrigado! Já passei ao Gustavo. Como posso te chamar?", null);
  // sem contexto, nenhuma data é permitida: o "hoje" do recibo também reprova
  assertEquals(validarSaida(BASE, null), { ok: false, regras: ["contexto", "data_fora", "hora_fora"] });
});

Deno.test("audiencia: só 'cliente' (parceiro é F4)", () => {
  so("audiencia", BASE, ctxBase({ audiencia: "parceiro" as "cliente" }));
  so("audiencia", BASE, ctxBase({ audiencia: "Cliente" as "cliente" }));
  so("audiencia", BASE, ctxBase({ audiencia: "" as "cliente" }));
});

Deno.test("dinheiro: R$, reais, %, sinal, pix, desconto, grátis, sem custo (e afins)", () => {
  for (
    const frase of [
      "O total é R$ 350.",
      "São 350 reais.",
      "Tem 10% a menos.",
      "Falta o sinal.",
      "Pode mandar por Pix.",
      "Tem desconto.",
      "A visita é grátis.",
      "A visita é gratis.",
      "A visita é sem custo.",
      "A visita é gratuita.",
      "Segue o preço.",
      "Segue o boleto.",
      "Falta o pagamento.",
      "Falta a parcela.",
      "Leve dinheiro.",
      "Total 350,00.",
      "Custa US$ 10.",
      "Dez por cento.",
      "Custa Ｒ＄ 350.", // largura cheia: o NFKC devolve o "R$"
    ]
  ) so("dinheiro", `${BASE} ${frase}`);
  // nome que começa com "custo" não é dinheiro
  assertEquals(validarSaida(`${BASE} O Custódio também.`, ctxBase()), { ok: true });
});

Deno.test("dado_pessoal: CPF, CNPJ, 11/14 dígitos, telefone, e-mail, chave Pix, placa, link", () => {
  for (
    const frase of [
      "CPF 123.456.78909.",
      "Documento 12345678909.",
      "CNPJ 12.345.678.0001.95.",
      "Documento 12345678000195.",
      "Ligue (47) 999991234.",
      "Ligue 4733334444.",
      "Ligue 99999.1234.",
      "Escreva para fulano@exemplo.org.",
      "Chave 3f2b8c1e-9a4d-4c2b-8e1f-0a1b2c3d4e5f.",
      "Placa ABC-1D23.",
      "Placa ABC1234.",
      "Placa abc-1234.",
      "Veja https://exemplo.org/x.",
      "Veja www.exemplo.",
      "Veja exemplo.com.",
      "Veja hbr.br.",
      "Veja wa.me/x.",
      "Documento １２３４５６７８９０９.", // dígitos de largura cheia
    ]
  ) so("dado_pessoal", `${BASE} ${frase}`);
  // Com traço ou barra entre dígitos o texto também tem cara de data (data_fora pega número/número e
  // número-número sem âncora): reprova nas duas, e o dado pessoal continua na lista.
  for (
    const frase of [
      "CPF 123.456.789-09.",
      "CNPJ 12.345.678/0001-95.",
      "Ligue (47) 99999-1234.",
      "Ligue +55 47 99999-1234.",
      "Ligue 99999-1234.",
      "Ligue (47) 3333-4444.",
    ]
  ) {
    assertEquals(validarSaida(`${BASE} ${frase}`, ctxBase()), { ok: false, regras: ["dado_pessoal", "data_fora"] }, frase);
  }
});

Deno.test("promessa: garanto, prometo, pode deixar, com certeza, fica pronto, pronto até", () => {
  for (
    const frase of [
      "Garanto.",
      "Prometo.",
      "Pode deixar.",
      "Com certeza.",
      "Fica pronto.",
      "Estará pronto até lá.",
      "Garantimos.",
      "Fica pronta.",
      "Ficará pronto.",
    ]
  ) so("promessa", `${BASE} ${frase}`);
});

Deno.test("data_fora: data, dia da semana, amanhã, hoje e ontem fora das permitidas", () => {
  // o contexto de base só permite "hoje"
  for (
    const quando of [
      "amanhã",
      "amanha",
      "ontem",
      "anteontem",
      "segunda",
      "segunda (09/11)",
      "terça-feira",
      "sáb",
      "dom",
      "seg",
      "ter",
      "09/11",
      "9/11/2026",
      "11/2026",
      "1/2027",
      "09/111",
      "09-11",
      "11-2026",
      "2026-11-09",
      "dia 9 de novembro",
      "em março",
    ]
  ) so("data_fora", BASE.replace("hoje", quando));
  // "hoje" sem estar nas permitidas nem no modelo
  so("data_fora", BASE, ctxBase({ datas_permitidas: [] }));
  // a permitida é "segunda (09/11)": "segunda (16/11)" não passa, nem a dd/mm de outro dia
  const ctx = ctxBase({ datas_permitidas: ["segunda (09/11)", "09/11"] });
  assertEquals(validarSaida(BASE.replace("hoje", "segunda (09/11)"), ctx), { ok: true });
  so("data_fora", BASE.replace("hoje", "segunda (16/11)"), ctx);
  so("data_fora", BASE.replace("hoje", "segunda (09/11) ou 10/11"), ctx);
  // a dd/mm permitida não cobre um número maior que começa por ela
  so("data_fora", BASE.replace("hoje", "09/111"), ctx);
  so("data_fora", BASE.replace("hoje", "09/11/2026"), ctx);
  // a palavra do modelo fixo passa (o "hoje" do T22), mas a mesma palavra fora do trecho não
  const t22 = MODELOS.T22;
  const dados = { nome: "Lenine", quando_lista: "amanhã" };
  const ctx22 = contextoDoPegar(t22, dados, { datas_permitidas: ["amanhã"], marcas: { ...SEM_MARCAS, tem_topo: true } });
  assertEquals(validarSaida(compor(t22, dados), ctx22), { ok: true });
  so("data_fora", compor(t22, dados) + " Até hoje.", ctx22);
  // "marco" (de marcar) não é mês
  assertEquals(validarSaida(`${BASE} Eu marco aqui.`, ctxBase()), { ok: true });
});

Deno.test("hora_fora: hora fora das permitidas", () => {
  // o contexto de base só permite "19h"
  for (const hora of ["20h", "19:30", "19 horas", "19 h", "10h30", "meio-dia", "meia noite", "1h"]) {
    so("hora_fora", BASE.replace("19h", hora));
  }
  so("hora_fora", `${BASE} Em 30 minutos.`);
  so("hora_fora", BASE, ctxBase({ horas_permitidas: [] }));
  so("hora_fora", BASE.replace("19h", "119h"));
  assertEquals(validarSaida(BASE.replace("19h", "10:30"), ctxBase({ horas_permitidas: ["10:30"] })), { ok: true });
});

Deno.test("os_de_outro: OS-n, ORÇ-n, ORC-n fora das permitidas", () => {
  for (const frase of ["Sobre a OS-00070.", "Sobre o ORÇ-123.", "Sobre o ORC-45.", "Sobre a OS 70.", "Sobre a os-12."]) {
    so("os_de_outro", `${BASE} ${frase}`);
  }
  // a OS permitida passa; outra, não
  const ctx = ctxBase({ os_permitidas: ["OS-00070"] });
  assertEquals(validarSaida(`${BASE} Sobre a OS-00070.`, ctx), { ok: true });
  so("os_de_outro", `${BASE} Sobre a OS-00071.`, ctx);
  // "os orçamentos" (T15) não é OS
  assertEquals(validarSaida(`${BASE} Ele faz os orçamentos.`, ctxBase()), { ok: true });
});

Deno.test("nome_de_outro: nome de outro cliente, sem acento e palavra inteira", () => {
  so("nome_de_outro", `${BASE} O Marcos também.`, ctxBase({ nomes_de_outros: ["Marcos"] }));
  so("nome_de_outro", `${BASE} O MARCOS também.`, ctxBase({ nomes_de_outros: ["Marcos"] }));
  so("nome_de_outro", `${BASE} O Joao também.`, ctxBase({ nomes_de_outros: ["João"] }));
  so("nome_de_outro", `${BASE} O João também.`, ctxBase({ nomes_de_outros: ["Joao"] }));
  so("nome_de_outro", `${BASE} A Ana  Paula também.`, ctxBase({ nomes_de_outros: ["Ana Paula"] }));
  // palavra inteira: "Ana" não casa dentro de "Anastácia"
  assertEquals(validarSaida(`${BASE} A Anastácia também.`, ctxBase({ nomes_de_outros: ["Ana"] })), { ok: true });
  // nome vazio na lista não bloqueia tudo
  assertEquals(validarSaida(BASE, ctxBase({ nomes_de_outros: ["", "  "] })), { ok: true });
});

Deno.test("afirmacao_sem_dado: cada afirmação só passa com a sua marca", () => {
  const casos: Array<[string, keyof Marcas]> = [
    ["Você já foi avisado.", "cliente_ouviu"],
    ["A peça foi conferida.", "conferida"],
    ["Seu orçamento está em preparação.", "tem_proposta"],
    ["Seu pedido abre a lista dele cedo.", "tem_topo"],
  ];
  for (const [frase, marca] of casos) {
    so("afirmacao_sem_dado", `${BASE} ${frase}`);
    // as outras marcas não servem
    const outras = { tem_proposta: true, tem_topo: true, cliente_ouviu: true, conferida: true, [marca]: false };
    so("afirmacao_sem_dado", `${BASE} ${frase}`, ctxBase({ marcas: outras }));
    assertEquals(validarSaida(`${BASE} ${frase}`, ctxBase({ marcas: { ...SEM_MARCAS, [marca]: true } })), { ok: true }, frase);
  }
});

Deno.test("eco_do_cliente: 4 palavras seguidas do cliente, com alguma que o banco não escreveu (R1-12)", () => {
  const ctx = ctxBase({ textos_do_cliente: ["A bomba de porão da lancha parou de funcionar"] });
  so("eco_do_cliente", `${BASE} Sobre a bomba de porão.`, ctx);
  so("eco_do_cliente", `${BASE} Sobre a BOMBA DE PORAO.`, ctx);
  // 3 palavras seguidas não são eco
  assertEquals(validarSaida(`${BASE} Sobre a bomba.`, ctx), { ok: true });
  // o cliente repetiu o modelo fixo: é do modelo, não é eco
  const copia = ctxBase({ textos_do_cliente: ["recebi e passei ao Gustavo?"] });
  assertEquals(validarSaida(BASE, copia), { ok: true });
  // a mesma frase do cliente cruzando um campo que o banco preencheu (hoje, 19h) também não é eco
  assertEquals(validarSaida(BASE, ctxBase({ textos_do_cliente: ["ele te responde hoje até as 19h?"] })), { ok: true });
  // a palavra do banco não salva a quadra que tem uma palavra só do cliente
  so("eco_do_cliente", `${BASE} A bomba parou hoje até as 19h.`, ctxBase({ textos_do_cliente: ["a bomba parou hoje até as 19h"] }));
  // o cumprimento cobre só as palavras dele: "aqui é o Pedro" fora do modelo continua eco
  so("eco_do_cliente", `${BASE} Boa tarde, aqui é o Pedro.`, ctxBase({ textos_do_cliente: ["Boa tarde, aqui é o Pedro, queria um orçamento"] }));
});

Deno.test("emoji: qualquer um", () => {
  for (const e of ["🙂", "👍", "🇧🇷", "❤️", "⏰", "👍🏽", "#️⃣"]) so("emoji", `${BASE} ${e}`);
});

Deno.test("tamanho: mais de 400 caracteres ou mais de 5 linhas", () => {
  const longo = BASE + " Seu pedido está anotado.".repeat(13);
  assert(longo.length > LIMITE_DE_CARACTERES);
  so("tamanho", longo);
  const seis = ["Oi, Lenine.", "Recebi.", "Passei ao Gustavo.", "Ele te responde hoje.", "Até as 19h.", "Obrigado."];
  so("tamanho", seis.join("\n"));
  so("tamanho", seis.join("\r\n"));
  // no limite, passa
  const exato = BASE + " ".repeat(LIMITE_DE_CARACTERES - BASE.length);
  assertEquals(exato.length, LIMITE_DE_CARACTERES);
  assertEquals(validarSaida(exato, ctxBase()), { ok: true });
  assertEquals(validarSaida(seis.slice(0, 5).join("\n"), ctxBase()), { ok: true });
  so("tamanho", exato + ".");
});

const PROIBIDAS: Array<[string, string, Partial<ContextoDoValidador>?]> = [
  ["prévia", "Segue a prévia."],
  ["chegar com o valor", "Vou chegar com o valor."],
  ["em campo", "O Gustavo está em campo."],
  ["na frente da fila", "Seu pedido está na frente da fila."],
  ["topo da lista", "Seu pedido está no topo da lista."],
  ["em atendimento", "Seu pedido está em atendimento."],
  // com a marca de conferida, para provar que quem barra é a palavra proibida
  ["já foi conferida", "A peça já foi conferida.", { marcas: { ...SEM_MARCAS, conferida: true } }],
  ["marco como prioridade", "Eu marco como prioridade."],
];

for (const [palavra, frase, extra] of PROIBIDAS) {
  Deno.test(`palavra_proibida: "${palavra}"`, () => {
    so("palavra_proibida", `${BASE} ${frase}`, ctxBase(extra ?? {}));
    so("palavra_proibida", `${BASE} ${frase.toUpperCase()}`, ctxBase(extra ?? {}));
  });
}

Deno.test("erro: exceção dentro do validador vira ['erro'], nunca lança", () => {
  const comGetter = {
    ...ctxBase(),
    get datas_permitidas(): string[] {
      throw new Error("getter que lança");
    },
  } as ContextoDoValidador;
  assertEquals(validarSaida(BASE, comGetter), { ok: false, regras: ["erro"] });
  const proxy = new Proxy({}, {
    get() {
      throw new Error("proxy que lança");
    },
  }) as ContextoDoValidador;
  assertEquals(validarSaida(BASE, proxy), { ok: false, regras: ["erro"] });
  const marcasQueLancam = {
    ...ctxBase(),
    marcas: {
      get tem_proposta(): boolean {
        throw new Error("marca que lança");
      },
    },
  } as unknown as ContextoDoValidador;
  assertEquals(validarSaida(BASE, marcasQueLancam), { ok: false, regras: ["erro"] });
});

Deno.test("o resultado lista TODAS as regras que falharam, na ordem do contrato", () => {
  assertEquals(validarSaida("Garanto R$ 350 amanhã 🙂", ctxBase()), {
    ok: false,
    regras: ["dinheiro", "promessa", "data_fora", "emoji"],
  });
  assertEquals(validarSaida("", null), { ok: false, regras: ["vazio", "contexto"] });
  assertEquals(
    validarSaida(`${BASE} Pix na OS-12 às 20h, CPF 12345678909, segue a prévia.`, ctxBase({ audiencia: "parceiro" as "cliente" })),
    { ok: false, regras: ["audiencia", "dinheiro", "dado_pessoal", "hora_fora", "os_de_outro", "palavra_proibida"] },
  );
});
