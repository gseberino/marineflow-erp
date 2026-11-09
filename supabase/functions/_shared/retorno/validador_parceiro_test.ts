// Retorno F4 (P4.2 e P4.4): o validador do texto ao parceiro (validarSaidaAoParceiro).
//
// Cada modelo P01–P16 (e as linhas do painel), copiado literal de _parceiro_texto (20270105100300_retorno_f4_textos.sql)
// e montado com dados inventados e o contexto que _parceiro_contexto_do_validador montaria, PASSA no validador real; os Q
// ao cliente final passam no validarSaida de hoje. Do outro lado, um teste NEGATIVO por regra. Se alguém mudar um modelo
// no SQL, este teste é o lembrete de copiar a mudança para cá.
//
// Reverter: apagar este arquivo junto com validarSaidaAoParceiro em validador.ts.

import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  type ContextoAoParceiro,
  type ContextoDoValidador,
  LIMITE_PARCEIRO_CARACTERES,
  LIMITE_PARCEIRO_LINHAS,
  type RegraDoValidador,
  validarSaida,
  validarSaidaAoParceiro,
} from "./validador.ts";

// ─── Os modelos (spec P4.1, literais; {comigo}{pessoa} é o prefixo {abertura}) ────────────────────────────────

const P: Record<string, string> = {
  P01: "{comigo}A partir de agora, no fim de cada dia útil em que algo mudar, mando um resumo dos motorhomes dos clientes de vocês que estão com a gente: o que andou e o próximo passo. Valores e dados ficam com cada cliente. A qualquer hora, mande *pátio*. Para pausar, mande *pausar*.",
  P02: "{abertura}Já passei sua mensagem ao Gustavo, e ele retorna para vocês {quando_fala}.",
  P03: "{abertura}Já passei seu pedido ao Gustavo, e ele retorna para vocês {quando_fala}. Para adiantar: qual é o veículo e o primeiro nome do cliente?",
  P04: "Obrigada! {primeiro_nome} tem WhatsApp? Se o cliente autorizar, me passa o número que o Gustavo fala direto.",
  P04_sem_nome: "O cliente tem WhatsApp? Se autorizar, me passa o número que o Gustavo fala direto.",
  P05: "Anotado, {nome}. Antes de começar, confirmo com o cliente e com o Gustavo e te aviso.",
  P05_sem_nome: "Anotado. Antes de começar, confirmo com o cliente e com o Gustavo e aviso vocês.",
  P07: "Pátio HBR: o {bem} de {cliente} ficou pronto. O cliente já foi avisado para combinar a retirada.",
  P08: "Pátio HBR: o serviço no {bem} de {cliente} vai atrasar porque uma peça não chegou. O cliente já foi avisado.",
  P09: "Pátio HBR: a peça do {bem} de {cliente} chegou. O cliente já foi avisado.",
  P10_vazio: "Pátio HBR: nenhum veículo dos clientes de vocês por aqui agora.",
  P12: "Combinado: o resumo fica pausado. Para voltar, mande *retomar*.",
  P13: "Pronto: o resumo volta no próximo dia útil em que algo mudar.",
  P14: "{abertura}{primeiro_nome} não tem WhatsApp com a gente. Pode repassar esta mensagem? \"{primeiro_nome}, o serviço no seu {bem} terminou. O Gustavo combina com você o melhor dia para buscar.\" Se o cliente autorizar, me passa o WhatsApp que o Gustavo fala direto.",
  P15: "{abertura}O orçamento do {bem} de {primeiro_nome} está com o Gustavo; ele retorna para vocês {quando_fala}.",
  P15_sem_nome: "{abertura}O orçamento do {bem} do cliente está com o Gustavo; ele retorna para vocês {quando_fala}.",
  P16: "{abertura}Segue o orçamento do {bem} de {primeiro_nome}, válido até {validade}.",
};

const Q: Record<string, string> = {
  Q01: "{nome}, aqui é a Claudia, assistente virtual da HBR. Como você veio pela {sigla}, ela também acompanha o andamento do seu {bem}, sem valores. Se preferir que não, responda NÃO {sigla}.",
  Q02: "{nome}, como você veio pela {sigla}, ela também acompanha o andamento do seu {bem}, sem valores. Se preferir que não, responda NÃO {sigla}.",
  Q03: "Combinado, {nome}: o andamento fica só entre nós.",
  Q03b: "Combinado: o andamento fica só entre nós.",
  Q04: "{nome}, aqui é a Claudia, assistente virtual da HBR. Este serviço no seu {bem} está sendo feito por meio da {sigla}, e ela acompanha o andamento. Se preferir que não, responda NÃO {sigla}.",
  Q05: "{nome}, este serviço no seu {bem} está sendo feito por meio da {sigla}, e ela acompanha o andamento. Se preferir que não, responda NÃO {sigla}.",
};

// As situações da linha do painel (P7.2), literais.
const SITUACAO: Record<string, string> = {
  pronto: "pronto; o cliente já foi avisado para combinar a retirada",
  peca_chegou: "a peça chegou em {dd/mm}",
  aguarda_peca: "aguardando uma peça; sem novidade desde {dd/mm}",
  aguarda_peca_sem_data: "aguardando uma peça",
  em_servico: "em serviço hoje",
  andamento: "sem novidade desde {dd/mm}",
  andamento_sem_data: "em serviço",
  orcamento: "orçamento pedido por vocês; com o Gustavo",
};

const ABERTURAS = {
  comigoComNome: "Carla, aqui é a Claudia, assistente virtual da HBR. ",
  comigoSemNome: "Aqui é a Claudia, assistente virtual da HBR. ",
  pessoa: "Oi, Carla! ",
  vazia: "",
};

const SEM_MARCAS: ContextoDoValidador["marcas"] = { tem_proposta: false, tem_topo: false, cliente_ouviu: false, conferida: false };
const OUVIU: ContextoDoValidador["marcas"] = { ...SEM_MARCAS, cliente_ouviu: true };

function compor(modelo: string, dados: Record<string, string>): string {
  return modelo.replace(/\{([a-z_]+)\}/g, (_, campo: string) => {
    const v = dados[campo];
    if (v === undefined) throw new Error(`teste sem o campo ${campo}`);
    return v;
  });
}

function linha(n: number, bem: string, cliente: string, estado: string, data = ""): string {
  const Bem = bem.charAt(0).toUpperCase() + bem.slice(1);
  return `${n}. ${Bem} de ${cliente}: ${SITUACAO[estado].replace("{dd/mm}", data)}.`;
}

/** P06: cabeçalho, linhas, "E mais", "Para ver de novo" e o rodapé semanal. */
function painel(cabecalho: string, linhas: string[], mais = 0, rodape = false): string {
  const partes = [cabecalho, ...linhas];
  if (mais > 0) partes.push(mais === 1 ? "E mais 1 veículo." : `E mais ${mais} veículos.`);
  partes.push("Para ver de novo, mande *pátio*.");
  if (rodape) partes.push("Valores e dados ficam com cada cliente.");
  return partes.join("\n");
}

/** O contexto como _parceiro_contexto_do_validador monta: os trechos são o texto cortado nos valores (o maior primeiro). */
function ctxParceiro(texto: string, valores: string[], extra: Partial<ContextoAoParceiro> = {}): ContextoAoParceiro {
  let corte = texto;
  for (const v of [...valores].filter((x) => x.trim() !== "").sort((a, b) => b.length - a.length)) {
    corte = corte.split(v).join("\u001f");
  }
  return {
    audiencia: "parceiro",
    datas_permitidas: [],
    horas_permitidas: [],
    nome_permitido: null,
    nomes_de_outros: [],
    nomes_da_lista: [],
    papel_do_parceiro: "indicou",
    os_permitidas: [],
    textos_do_cliente: [],
    trechos_do_modelo: corte.split("\u001f").filter((p) => p.trim() !== ""),
    marcas: SEM_MARCAS,
    ...extra,
  };
}

function ctxCliente(texto: string, nome: string | null, valores: string[]): ContextoDoValidador {
  let corte = texto;
  for (const v of [...valores].filter((x) => x.trim() !== "").sort((a, b) => b.length - a.length)) {
    corte = corte.split(v).join("\u001f");
  }
  return {
    audiencia: "cliente",
    datas_permitidas: [],
    horas_permitidas: [],
    nome_permitido: nome,
    nomes_de_outros: [],
    os_permitidas: [],
    textos_do_cliente: [],
    trechos_do_modelo: corte.split("\u001f").filter((p) => p.trim() !== ""),
    marcas: SEM_MARCAS,
  };
}

function passa(texto: string, ctx: ContextoAoParceiro, rotulo = texto) {
  assertEquals(validarSaidaAoParceiro(texto, ctx), { ok: true }, rotulo);
}

function reprova(texto: string, ctx: ContextoAoParceiro | null | undefined, ...regras: RegraDoValidador[]) {
  const r = validarSaidaAoParceiro(texto, ctx as ContextoAoParceiro);
  assert(!r.ok, `passou e devia reprovar: ${texto}`);
  for (const regra of regras) assert(r.regras.includes(regra), `${regra} não está em ${JSON.stringify(r.regras)}: ${texto}`);
}

function so(regra: RegraDoValidador, texto: string, ctx: ContextoAoParceiro) {
  assertEquals(validarSaidaAoParceiro(texto, ctx), { ok: false, regras: [regra] }, texto);
}

// ─── Os modelos passam no validador real ──────────────────────────────────────────────────────────────

Deno.test("P02, P03, P14, P15 e P16 nas 4 aberturas passam (20 combinações)", () => {
  for (const [rotulo, abertura] of Object.entries(ABERTURAS)) {
    for (const id of ["P02", "P03", "P14", "P15", "P15_sem_nome", "P16"]) {
      const dados = { abertura, quando_fala: "ainda hoje", bem: "motorhome", primeiro_nome: "João", validade: "15/01" };
      const texto = compor(P[id], dados);
      const ctx = ctxParceiro(texto, ["Carla", "ainda hoje", "motorhome", "João", "15/01"], {
        datas_permitidas: ["ainda hoje", "15/01"],
        nome_permitido: "Carla",
        nomes_da_lista: ["João"],
      });
      passa(texto, ctx, `${id}/${rotulo}`);
      assert(!texto.startsWith(" ") && !texto.includes("  "), `${id}/${rotulo}: espaço sobrando`);
    }
  }
});

Deno.test("P01 com {comigo} e sem prefixo, P04, P05, P10 vazio, P12 e P13 passam", () => {
  for (const comigo of [ABERTURAS.comigoComNome, ABERTURAS.comigoSemNome, ""]) {
    const texto = compor(P.P01, { comigo });
    passa(texto, ctxParceiro(texto, ["Carla"], { nome_permitido: "Carla" }));
  }
  assert(compor(P.P01, { comigo: "" }).startsWith("A partir de agora"));
  const p04 = compor(P.P04, { primeiro_nome: "João" });
  passa(p04, ctxParceiro(p04, ["João"], { nomes_da_lista: ["João"] }));
  for (const t of [P.P04_sem_nome, P.P05_sem_nome, P.P10_vazio, P.P12, P.P13]) passa(t, ctxParceiro(t, []));
  const p05 = compor(P.P05, { nome: "Carla" });
  passa(p05, ctxParceiro(p05, ["Carla"], { nome_permitido: "Carla" }));
});

Deno.test("P07, P08 e P09 (eco) passam com o cliente ouvido; sem a marca, afirmacao_sem_dado", () => {
  for (const id of ["P07", "P08", "P09"]) {
    const texto = compor(P[id], { bem: "motorhome", cliente: "João S." });
    passa(texto, ctxParceiro(texto, ["motorhome", "João S."], { nomes_da_lista: ["João S."], marcas: OUVIU }), id);
    so("afirmacao_sem_dado", texto, ctxParceiro(texto, ["motorhome", "João S."], { nomes_da_lista: ["João S."] }));
  }
});

Deno.test("painel misto: linha pronto (cliente ouviu) e linha 'em serviço hoje' passam", () => {
  const texto = painel("Pátio HBR · ter (12/01)", [
    linha(1, "motorhome", "João S.", "pronto"),
    linha(2, "motorhome", "Bruno C.", "em_servico"),
  ]);
  passa(texto, ctxParceiro(texto, ["ter (12/01)", "Motorhome", "João S.", "Bruno C."], {
    datas_permitidas: ["ter (12/01)", "12/01"],
    nomes_da_lista: ["João S.", "Bruno C."],
    marcas: OUVIU,
  }));
});

Deno.test("'chegou em 03/01' numa linha e 'pronto' na seguinte passam: data_de_pronto tem um sentido só, na mesma linha", () => {
  const texto = painel("Pátio HBR · ter (12/01)", [
    linha(1, "motorhome", "Ana B.", "peca_chegou", "03/01"),
    linha(2, "motorhome", "Bruno C.", "pronto"),
  ]);
  passa(texto, ctxParceiro(texto, ["ter (12/01)", "Motorhome", "Ana B.", "Bruno C.", "03/01"], {
    datas_permitidas: ["ter (12/01)", "12/01", "03/01"],
    nomes_da_lista: ["Ana B.", "Bruno C."],
    marcas: OUVIU,
  }));
  // "em serviço hoje" e, na linha seguinte, "pronto": também passa.
  const outro = painel("Pátio HBR · ter (12/01)", [
    linha(1, "motorhome", "Ana B.", "em_servico"),
    linha(2, "motorhome", "Bruno C.", "pronto"),
  ]);
  passa(outro, ctxParceiro(outro, ["ter (12/01)", "Motorhome", "Ana B.", "Bruno C."], {
    datas_permitidas: ["ter (12/01)", "12/01"],
    nomes_da_lista: ["Ana B.", "Bruno C."],
    marcas: OUVIU,
  }));
});

Deno.test("todas as linhas do painel, 'em serviço' sem data e 'E mais 3 veículos.' passam; P10 direto também", () => {
  const linhas = [
    linha(1, "motorhome", "Ana B.", "peca_chegou", "03/01"),
    linha(2, "trailer", "Bruno C.", "aguarda_peca", "02/01"),
    linha(3, "camper", "Caio D.", "aguarda_peca_sem_data"),
    linha(4, "motorhome", "Davi E.", "em_servico"),
    linha(5, "veículo", "Edu F.", "orcamento"),
    linha(6, "motorhome", "Fábio G.", "andamento", "28/12"),
    linha(7, "barco", "Gil H.", "andamento_sem_data"),
  ];
  const nomes = ["Ana B.", "Bruno C.", "Caio D.", "Davi E.", "Edu F.", "Fábio G.", "Gil H."];
  const bens = ["Motorhome", "Trailer", "Camper", "Veículo", "Barco"];
  const datas = ["ter (12/01)", "12/01", "03/01", "02/01", "28/12"];
  const texto = painel("Pátio HBR · ter (12/01)", linhas, 3, true);
  passa(texto, ctxParceiro(texto, [...nomes, ...bens, ...datas], { datas_permitidas: datas, nomes_da_lista: nomes }));
  assert(texto.includes("E mais 3 veículos."));
  const direto = ["Pátio HBR · 12/01", linha(1, "motorhome", "Ana B.", "andamento_sem_data"), "E mais 1 veículo."].join("\n");
  passa(direto, ctxParceiro(direto, ["12/01", "Motorhome", "Ana B."], { datas_permitidas: ["12/01"], nomes_da_lista: ["Ana B."] }));
});

Deno.test("recibo com o bloco P11 passa", () => {
  const texto = [
    compor(P.P02, { abertura: ABERTURAS.pessoa, quando_fala: "ainda hoje" }),
    "Enquanto isso, o pátio de hoje:",
    linha(1, "motorhome", "Ana B.", "em_servico"),
    linha(2, "motorhome", "Bruno C.", "andamento", "02/01"),
  ].join("\n");
  passa(texto, ctxParceiro(texto, ["Carla", "ainda hoje", "Motorhome", "Ana B.", "Bruno C.", "02/01"], {
    datas_permitidas: ["ainda hoje", "02/01"],
    nome_permitido: "Carla",
    nomes_da_lista: ["Ana B.", "Bruno C."],
  }));
});

Deno.test("Q01–Q05 e Q03b ao cliente final passam no validarSaida de hoje", () => {
  for (const [id, modelo] of Object.entries(Q)) {
    const texto = compor(modelo, { nome: "João", sigla: "MP", bem: "motorhome" });
    const nome = modelo.includes("{nome}") ? "João" : null;
    assertEquals(validarSaida(texto, ctxCliente(texto, nome, ["João", "MP", "motorhome"])), { ok: true }, id);
  }
});

Deno.test("os limites: 1.500 caracteres e 18 linhas passam; o painel cheio (cabeçalho, 14 linhas, E mais, rodapé) cabe", () => {
  assertEquals(LIMITE_PARCEIRO_CARACTERES, 1500);
  assertEquals(LIMITE_PARCEIRO_LINHAS, 18);
  const longo = "x".repeat(1500); // "a" repetido parece chave Pix (hex): dado_pessoal
  passa(longo, ctxParceiro(longo, []));
  const dezoito = Array.from({ length: 18 }, () => "Pátio HBR").join("\n");
  passa(dezoito, ctxParceiro(dezoito, []));
  const nomes = Array.from({ length: 14 }, (_, i) => `${String.fromCharCode(65 + i)}na B.`);
  const cheio = painel("Pátio HBR · ter (12/01)", nomes.map((n, i) => linha(i + 1, "motorhome", n, "em_servico")), 6, true);
  assertEquals(cheio.split("\n").length, 18);
  passa(cheio, ctxParceiro(cheio, ["ter (12/01)", "Motorhome", ...nomes], { datas_permitidas: ["ter (12/01)", "12/01"], nomes_da_lista: nomes }));
});

// ─── Homônimo e palavras fixas (P4.2) ──────────────────────────────────────────────────────────────────

Deno.test("homônimo: João S. na lista e João A. fora passa; João A. escrito no texto reprova com nome_de_outro", () => {
  const texto = compor(P.P07, { bem: "motorhome", cliente: "João S." });
  const extra = { nomes_da_lista: ["João S."], nomes_de_outros: ["João A."], marcas: OUVIU };
  passa(texto, ctxParceiro(texto, ["motorhome", "João S."], extra));
  const outro = compor(P.P07, { bem: "motorhome", cliente: "João A." });
  so("nome_de_outro", outro, ctxParceiro(outro, ["motorhome", "João A."], extra));
});

Deno.test("palavras fixas fora de nomes_de_outros: o P02 passa; com 'Gustavo' na lista de outros, reprovaria (por isso o banco tira)", () => {
  const texto = compor(P.P02, { abertura: ABERTURAS.vazia, quando_fala: "ainda hoje" });
  passa(texto, ctxParceiro(texto, ["ainda hoje"], { datas_permitidas: ["ainda hoje"], nomes_de_outros: [] }));
  so("nome_de_outro", texto, ctxParceiro(texto, ["ainda hoje"], { datas_permitidas: ["ainda hoje"], nomes_de_outros: ["Gustavo"] }));
});

// ─── Gênero (P4.1): "de" antes do nome, "o cliente" no lugar de pronome ───────────────────────────────

Deno.test("gênero: nenhum modelo à MP tem ' do {' antes de nome, 'ele já', 'a ele' ou 'dele'", () => {
  for (const [id, modelo] of Object.entries(P)) {
    assert(!/ do \{(?!bem\})/.test(modelo), `${id}: " do {" antes de nome`);
    assert(!/\bele j[aá]|\ba ele\b|\bdele\b/i.test(modelo), `${id}: pronome do cliente`);
  }
  assert(!/\bele\b/i.test(P.P04) && !/\bele\b/i.test(P.P04_sem_nome) && !/\bele\b/i.test(P.P14), "P04 e P14 sem pronome");
});

Deno.test("gênero: Maria C. sai sempre com 'de' em P04, P06, P07, P14, P15 e P16", () => {
  const dados = { abertura: "", quando_fala: "ainda hoje", bem: "motorhome", primeiro_nome: "Maria C.", cliente: "Maria C.", validade: "15/01" };
  const textos = [
    compor(P.P04, dados),
    painel("Pátio HBR · ter (12/01)", [linha(1, "motorhome", "Maria C.", "em_servico")]),
    compor(P.P07, dados),
    compor(P.P14, dados),
    compor(P.P15, dados),
    compor(P.P16, dados),
  ];
  for (const t of textos) {
    assert(!/\bdo Maria\b/.test(t) && !/\bele j[aá]|\ba ele\b|\bdele\b/.test(t), t);
  }
  for (const t of textos.slice(1)) {
    if (!t.startsWith("Maria")) assert(/\bde Maria C\./.test(t) || t.includes("\"Maria C.,"), t);
  }
});

// ─── Um negativo por regra ─────────────────────────────────────────────────────────────────────────────

Deno.test("valor_a_parceiro: valor com número, R$ e Pix reprovam, inclusive para contratante", () => {
  const valor = "Já passei o valor de 350 ao Gustavo.";
  so("valor_a_parceiro", valor, ctxParceiro(valor, []));
  so("valor_a_parceiro", valor, ctxParceiro(valor, [], { papel_do_parceiro: "contratante" }));
  const real = "O total ficou R$ 1.200.";
  reprova(real, ctxParceiro(real, []), "dinheiro", "valor_a_parceiro");
  const pix = "Pode pagar pelo Pix.";
  reprova(pix, ctxParceiro(pix, [], { papel_do_parceiro: "pagador" }), "dinheiro", "valor_a_parceiro");
  const fixo = "Valores e dados ficam com cada cliente.";
  passa(fixo, ctxParceiro(fixo, []));
});

Deno.test("data_de_pronto: 'ficou pronto em 10/12' e 'ficou pronto hoje' reprovam, mesmo com a data permitida", () => {
  const emData = "Pátio HBR: o motorhome de João S. ficou pronto em 10/12.";
  so("data_de_pronto", emData, ctxParceiro(emData, ["motorhome", "João S."], { datas_permitidas: ["10/12"], nomes_da_lista: ["João S."] }));
  const hoje = "Pátio HBR: o motorhome de João S. ficou pronto hoje.";
  so("data_de_pronto", hoje, ctxParceiro(hoje, ["motorhome", "João S."], { datas_permitidas: ["hoje"], nomes_da_lista: ["João S."] }));
  const amanha = "Pronto amanhã.";
  so("data_de_pronto", amanha, ctxParceiro(amanha, [], { datas_permitidas: ["amanhã"] }));
  const diaUtil = "Pronto: o resumo volta no próximo dia útil em que algo mudar.";
  passa(diaUtil, ctxParceiro(diaUtil, []));
});

Deno.test("dado_pessoal: CPF, telefone, e-mail e placa reprovam", () => {
  for (const texto of [
    "O CPF 123.456.789-09 está com o Gustavo.",
    "Ligue para 47 99999 1234.",
    "Mande para joao@exemplo.com.",
    "O motorhome ABC1D23 está com o Gustavo.",
  ]) {
    reprova(texto, ctxParceiro(texto, []), "dado_pessoal");
  }
});

Deno.test("as outras regras de hoje valem ao parceiro: promessa, hora, eco, emoji, OS", () => {
  const promessa = "Garanto que sai ainda hoje.";
  so("promessa", promessa, ctxParceiro(promessa, ["ainda hoje"], { datas_permitidas: ["ainda hoje"] }));
  const hora = "O Gustavo retorna às 19h.";
  so("hora_fora", hora, ctxParceiro(hora, []));
  // O trecho do cliente entrou no texto por um {campo}: não é trecho do modelo, e o eco reprova.
  const eco = "Anotado: como está o motorhome do Pedro.";
  so("eco_do_cliente", eco, ctxParceiro(eco, ["como está o motorhome do Pedro"], { textos_do_cliente: ["como está o motorhome do Pedro?"] }));
  const emoji = "Pátio HBR 🚐";
  so("emoji", emoji, ctxParceiro(emoji, []));
  const os = "Pátio HBR: a OS-74 está com o Gustavo.";
  so("os_de_outro", os, ctxParceiro(os, []));
});

Deno.test("tamanho: 1.501 caracteres e 19 linhas reprovam", () => {
  const longo = "x".repeat(1501);
  so("tamanho", longo, ctxParceiro(longo, []));
  const dezenove = Array.from({ length: 19 }, () => "Pátio HBR").join("\n");
  so("tamanho", dezenove, ctxParceiro(dezenove, []));
});

Deno.test("audiência e contexto: só 'parceiro'; contexto ausente, sem nomes_da_lista ou com papel estranho reprova", () => {
  const texto = P.P12;
  reprova(texto, null, "contexto");
  reprova(texto, undefined, "contexto");
  so("audiencia", texto, { ...ctxParceiro(texto, []), audiencia: "cliente" as "parceiro" });
  const semLista = ctxParceiro(texto, []) as Partial<ContextoAoParceiro>;
  delete semLista.nomes_da_lista;
  so("contexto", texto, semLista as ContextoAoParceiro);
  const semPapel = ctxParceiro(texto, []) as Partial<ContextoAoParceiro>;
  delete semPapel.papel_do_parceiro;
  so("contexto", texto, semPapel as ContextoAoParceiro);
  so("contexto", texto, { ...ctxParceiro(texto, []), papel_do_parceiro: "anfitria" as "indicou" });
  passa(texto, { ...ctxParceiro(texto, []), papel_do_parceiro: null });
});

Deno.test("validarSaida segue reprovando a audiência 'parceiro'; validarSaidaAoParceiro nunca lança", () => {
  const texto = Q.Q03b;
  const ctx = { ...ctxCliente(texto, null, []), audiencia: "parceiro" as "cliente" };
  assertEquals(validarSaida(texto, ctx), { ok: false, regras: ["audiencia"] });
  const armadilha = {
    ...ctxParceiro(texto, []),
    get nomes_de_outros(): string[] {
      throw new Error("getter quebrado");
    },
  };
  assertEquals(validarSaidaAoParceiro(texto, armadilha as ContextoAoParceiro), { ok: false, regras: ["erro"] });
});
