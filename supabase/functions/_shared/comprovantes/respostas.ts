// O parser das respostas do dono à conversa dos comprovantes (F2, 11/10/2026 — spec-f2.md, 3.4).
//
// Determinístico, sem LLM: o áudio chega pela transcrição que já existe (whatsapp-transcribe-audio)
// e passa pelos mesmos leitores. O edge só INTERPRETA ("2" no menu do para quê = opção 2); quem
// valida contra o passo e grava é o banco (comprovante_responder / comprovante_comando).
//
// O que nunca aprova: o grupo "ok"; "sim" com texto a mais; um número no passo confirmar (lá só
// sim/não — o número e a frase curta voltam como "ok", que pede o sim de novo, para não escapar ao
// assistente).
//
// Revisão de 11/10/2026 (respostas reais, digitadas rápido ou faladas): o enchimento do começo ("é o
// Brisa", "é pro estoque", "foi no débito") sai antes de procurar; o número com o rótulo do menu
// ("1 pix", "4 - dinheiro") vale se os dois batem; no como pagou / quem pagou / cobrar / para quê,
// vale a frase com UMA palavra-chave do passo ("paguei no débito", "pode cobrar", "é custo nosso");
// "segunda opção"; o nome tem até 3 palavras (um recado ao assistente não vira nome de barco).
//
// F3 (11/10/2026 — spec-f3.md, 4.2): o passo "banco" (a pergunta do extrato de um CMP já gravado).
// "0"/"nenhuma destas" = não; o número só vale na lista (azul) — no verde só sim/não ligam ou recusam.
import { dataEmSaoPaulo } from "../dropbox/nucleo.ts";
import { lerNumero, lerSimNao, normalizarResposta, type Opcao } from "../whatsapp/pergunta-ativa.ts";

export type Palavra =
  | "estoque" | "insumo" | "empresa" | "pessoal" | "os"
  | "cobrar" | "custo"
  | "socio" | "tecnico" | "cliente"
  | "pix" | "debito" | "credito" | "dinheiro" | "boleto" | "transferencia";

/** O contrato com o banco (spec 2.3): o que o edge entendeu da resposta. */
export type Interpretacao =
  | { tipo: "opcao"; n: number }
  | { tipo: "sim" }
  | { tipo: "nao" }
  | { tipo: "ok" }
  | { tipo: "valor"; valor: string }
  | { tipo: "data"; data: string }
  | { tipo: "os"; numero: number }
  | { tipo: "palavra"; valor: Palavra }
  | { tipo: "nome"; texto: string };

export type Passo =
  | "valor" | "para_que" | "qual_os" | "mesma_compra" | "como_pagou" | "quem_pagou" | "qual_tecnico" | "cobrar" | "categoria"
  | "data" | "confirmar" | "corrigir"
  /** F3: "apareceu no extrato, ligo?" (verde: sim/não) ou a lista de linhas com "0 Nenhuma destas" (azul). */
  | "banco";

// ---------------------------------------------------------------------------------------------
// Os menus fixos (o banco manda as opções; estes valem quando a pergunta não as trouxe)
// ---------------------------------------------------------------------------------------------

export const MENU_COMO_PAGOU: Opcao[] = [
  { n: 1, rotulo: "Pix", valor: "pix" },
  { n: 2, rotulo: "Débito", valor: "debito" },
  { n: 3, rotulo: "Crédito", valor: "credito" },
  { n: 4, rotulo: "Dinheiro", valor: "dinheiro" },
  { n: 5, rotulo: "Boleto", valor: "boleto" },
  { n: 6, rotulo: "Transferência", valor: "transferencia" },
];

export const MENU_QUEM_PAGOU: Opcao[] = [
  { n: 1, rotulo: "A empresa (dinheiro do Caixa)", valor: "empresa" },
  { n: 2, rotulo: "Eu, do meu bolso (fica como reembolso para você)", valor: "socio" },
  { n: 3, rotulo: "Um técnico", valor: "tecnico" },
  { n: 4, rotulo: "O cliente pagou direto", valor: "cliente" },
];

export const MENU_COBRAR: Opcao[] = [
  { n: 1, rotulo: "Cobrar do cliente (entra no total da OS)", valor: "cobrar" },
  { n: 2, rotulo: "Custo da HBR (não entra no total)", valor: "custo" },
];

export const MENU_MESMA_COMPRA: Opcao[] = [
  { n: 1, rotulo: "Sim, é a mesma compra: só guardar o arquivo", valor: "mesma" },
  { n: 2, rotulo: "Não, é outra compra", valor: "outra" },
];

export const MENU_CATEGORIA: Opcao[] = [
  "Combustível e deslocamento", "Alimentação de campo", "Pedágio e estacionamento", "Ferramentas e equipamentos",
  "Manutenção de veículo", "Material de escritório", "Hospedagem e Hotelaria", "Outras despesas",
].map((rotulo, i) => ({ n: i + 1, rotulo, valor: rotulo }));

export const MENU_CORRIGIR: Opcao[] = [
  { n: 1, rotulo: "Valor", valor: "valor" },
  { n: 2, rotulo: "Data", valor: "data" },
  { n: 3, rotulo: "Para quê", valor: "para_que" },
  { n: 4, rotulo: "Como foi pago", valor: "como_pagou" },
  { n: 5, rotulo: "Quem pagou", valor: "quem_pagou" },
  { n: 6, rotulo: "Cobrar ou não", valor: "cobrar" },
  { n: 7, rotulo: "Categoria", valor: "categoria" },
  { n: 8, rotulo: "Cancelar este comprovante", valor: "cancelar" },
  { n: 9, rotulo: "Deixar para depois", valor: "depois" },
];

/**
 * As opções que valem para o passo: as do banco; sem elas, o menu fixo do passo (se há). O passo
 * "banco" (F3) não tem menu fixo: valem só as linhas que a pergunta trouxe.
 */
export function opcoesDoPasso(passo: string | null | undefined, opcoes: Opcao[] | null | undefined): Opcao[] {
  if (Array.isArray(opcoes) && opcoes.length > 0) return opcoes;
  switch (passo) {
    case "como_pagou": return MENU_COMO_PAGOU;
    case "quem_pagou": return MENU_QUEM_PAGOU;
    case "cobrar": return MENU_COBRAR;
    case "mesma_compra": return MENU_MESMA_COMPRA;
    case "categoria": return MENU_CATEGORIA;
    case "corrigir": return MENU_CORRIGIR;
    default: return [];
  }
}

// ---------------------------------------------------------------------------------------------
// Valor, data e número de OS
// ---------------------------------------------------------------------------------------------

const VALOR_MAXIMO_CENTAVOS = 99_999_999; // 999.999,99

function centavosParaTexto(c: number): string {
  return `${Math.floor(c / 100)}.${String(c % 100).padStart(2, "0")}`;
}

/** "1.234,56" / "62,5" / "62.50" → centavos; ambíguo ("1,234.56", "1,234") → null. */
function centavosDoNumero(s: string): number | null {
  let inteiro: string;
  let fracao = "";
  let m: RegExpExecArray | null;
  if ((m = /^(\d{1,3}(?:\.\d{3})+)(?:,(\d{1,2}))?$/.exec(s))) {
    inteiro = m[1].replace(/\./g, "");
    fracao = m[2] ?? "";
  } else if ((m = /^(\d+)(?:,(\d{1,2}))?$/.exec(s))) {
    inteiro = m[1];
    fracao = m[2] ?? "";
  } else if ((m = /^(\d+)\.(\d{1,2})$/.exec(s))) {
    inteiro = m[1];
    fracao = m[2];
  } else {
    return null;
  }
  if (inteiro.length > 9) return null;
  const centavos = Number(inteiro) * 100 + Number(fracao.padEnd(2, "0") || "0");
  return Number.isSafeInteger(centavos) ? centavos : null;
}

/**
 * Valor em reais: "62", "62,5", "62,50", "r$ 62,50", "1.234,56", "1.234", "62.50", "62 reais",
 * "62 reais e 50 centavos" → "62.00", "62.50", …, "1234.56". Ambíguo ("1,234.56"), zero ou acima de
 * 999.999,99 → null. Recebe o texto JÁ normalizado.
 */
export function lerValor(textoNormalizado: string): string | null {
  let s = String(textoNormalizado ?? "").trim().replace(/^(?:foi |deu |ficou |valor |e |eh |o valor e |o certo e |certo e |pra |para )+/, "");
  s = s.replace(/^r\s?\$\s*/, "").replace(/\s+/g, " ").trim();
  let centavos: number | null = null;
  const extenso = /^(\d[\d.]*(?:,\d{1,2})?) ?(?:reais|real|conto|contos)(?: e (\d{1,2}) centavos?)?$/.exec(s);
  if (extenso) {
    const base = centavosDoNumero(extenso[1]);
    if (base === null) return null;
    const extra = extenso[2] ? Number(extenso[2]) : 0;
    if (extenso[2] && extenso[1].includes(",")) return null; // "62,50 reais e 10 centavos"
    centavos = base + extra;
  } else {
    centavos = centavosDoNumero(s.replace(/ /g, ""));
  }
  if (centavos === null || centavos <= 0 || centavos > VALOR_MAXIMO_CENTAVOS) return null;
  return centavosParaTexto(centavos);
}

const MESES: Record<string, number> = {
  janeiro: 1, fevereiro: 2, marco: 3, abril: 4, maio: 5, junho: 6, julho: 7, agosto: 8, setembro: 9, outubro: 10,
  novembro: 11, dezembro: 12,
};

function somarDias(dia: string, n: number): string {
  const d = new Date(`${dia}T12:00:00Z`);
  d.setUTCDate(d.getUTCDate() + n);
  return d.toISOString().slice(0, 10);
}

function diaQueExiste(ano: number, mes: number, dia: number): string | null {
  if (mes < 1 || mes > 12 || dia < 1 || dia > 31) return null;
  const d = new Date(Date.UTC(ano, mes - 1, dia, 12));
  if (d.getUTCFullYear() !== ano || d.getUTCMonth() !== mes - 1 || d.getUTCDate() !== dia) return null;
  return d.toISOString().slice(0, 10);
}

/**
 * Data da compra: "10/10", "10-10", "10/10/26", "10/10/2026", "10 de outubro", "dia 10", "hoje",
 * "ontem", "anteontem" → "AAAA-MM-DD" (dia de São Paulo). Sem ano e no futuro → ano anterior (sem
 * mês: mês anterior); com ano no futuro → null. Recebe o texto JÁ normalizado.
 */
export function lerData(textoNormalizado: string, agora: Date = new Date()): string | null {
  const hoje = dataEmSaoPaulo(agora);
  let s = String(textoNormalizado ?? "").trim().replace(/^(?:foi |comprei |compra |no |em |de |e |eh |a data e |pra |para )+/, "");
  if (s === "hoje") return hoje;
  if (s === "ontem") return somarDias(hoje, -1);
  if (s === "anteontem") return somarDias(hoje, -2);
  const [anoHoje, mesHoje] = [Number(hoje.slice(0, 4)), Number(hoje.slice(5, 7))];

  let m: RegExpExecArray | null = /^dia (\d{1,2})$/.exec(s);
  if (m) {
    // "dia 10": o mês atual (no futuro → o mês anterior)
    const dia = Number(m[1]);
    const doMes = diaQueExiste(anoHoje, mesHoje, dia);
    if (doMes && doMes <= hoje) return doMes;
    const anterior = mesHoje === 1 ? { a: anoHoje - 1, m: 12 } : { a: anoHoje, m: mesHoje - 1 };
    return diaQueExiste(anterior.a, anterior.m, dia);
  }
  s = s.replace(/^dia /, "");

  let dia: number, mes: number, ano: number | null = null;
  if ((m = /^(\d{1,2})[/-](\d{1,2})(?:[/-](\d{2}|\d{4}))?$/.exec(s))) {
    dia = Number(m[1]);
    mes = Number(m[2]);
    if (m[3]) ano = m[3].length === 2 ? 2000 + Number(m[3]) : Number(m[3]);
  } else if ((m = /^(\d{1,2}) de ([a-z]+)(?: de (\d{4}))?$/.exec(s)) && MESES[m[2]]) {
    dia = Number(m[1]);
    mes = MESES[m[2]];
    if (m[3]) ano = Number(m[3]);
  } else {
    return null;
  }
  if (ano !== null) {
    const d = diaQueExiste(ano, mes, dia);
    return d && d <= hoje ? d : null;
  }
  const esteAno = diaQueExiste(anoHoje, mes, dia);
  if (esteAno && esteAno <= hoje) return esteAno;
  return diaQueExiste(anoHoje - 1, mes, dia);
}

/** "os 112", "os-112", "os112", "os-00112", "da os 112", "ordem 112" → 112. */
export function lerOs(textoNormalizado: string): number | null {
  const m = /^(?:(?:e|eh|da|na|a|pra|para|foi|e da|e na) )?(?:os|ordem|ordem de servico)[\s-]*0*(\d{1,6})$/.exec(
    String(textoNormalizado ?? "").trim(),
  );
  if (!m) return null;
  const n = Number(m[1]);
  return n > 0 ? n : null;
}

// ---------------------------------------------------------------------------------------------
// Palavras de cada passo
// ---------------------------------------------------------------------------------------------

/** O enchimento do começo da frase falada/digitada: "é o Brisa", "é pro estoque", "foi no débito". */
const ENCHIMENTO = new Set([
  "e", "eh", "foi", "do", "da", "dos", "das", "de", "pro", "pra", "para", "o", "a", "os", "as", "no", "na", "nos", "nas",
  "em", "com", "barco", "lancha", "veleiro", "cliente", "um", "uma",
]);

/** Tira o enchimento do começo ("é o brisa" → "brisa"; "é pro estoque" → "estoque"). Nunca deixa vazio. */
export function semEnchimento(t: string): string {
  const tokens = String(t ?? "").split(" ").filter(Boolean);
  let i = 0;
  while (i < tokens.length - 1 && ENCHIMENTO.has(tokens[i])) i++;
  return tokens.slice(i).join(" ");
}

const PALAVRAS_DO_PASSO: Record<string, Record<string, Palavra>> = {
  para_que: {
    "estoque": "estoque", "para estoque": "estoque", "pro estoque": "estoque", "e estoque": "estoque",
    "insumo": "insumo", "insumos": "insumo", "e insumo": "insumo",
    "empresa": "empresa", "da empresa": "empresa", "pra empresa": "empresa", "empresa sem os": "empresa", "adm": "empresa",
    "administrativo": "empresa", "e da empresa": "empresa",
    "pessoal": "pessoal", "e pessoal": "pessoal", "particular": "pessoal",
    "os": "os", "uma os": "os", "e de os": "os",
  },
  como_pagou: {
    "pix": "pix", "no pix": "pix", "foi pix": "pix", "via pix": "pix", "foi no pix": "pix",
    "debito": "debito", "cartao de debito": "debito", "no debito": "debito", "foi debito": "debito", "foi no debito": "debito",
    "credito": "credito", "cartao de credito": "credito", "no credito": "credito", "foi credito": "credito", "foi no credito": "credito",
    "dinheiro": "dinheiro", "especie": "dinheiro", "em especie": "dinheiro", "em dinheiro": "dinheiro", "no dinheiro": "dinheiro",
    "foi dinheiro": "dinheiro", "cash": "dinheiro",
    "boleto": "boleto", "no boleto": "boleto", "foi boleto": "boleto",
    "transferencia": "transferencia", "ted": "transferencia", "doc": "transferencia", "transf": "transferencia",
    "por transferencia": "transferencia", "foi transferencia": "transferencia",
  },
  quem_pagou: {
    "empresa": "empresa", "a empresa": "empresa", "foi a empresa": "empresa", "caixa": "empresa", "do caixa": "empresa", "hbr": "empresa",
    "eu": "socio", "fui eu": "socio", "eu paguei": "socio", "paguei eu": "socio", "do meu bolso": "socio", "meu bolso": "socio",
    "eu do meu bolso": "socio", "socio": "socio", "o socio": "socio",
    "tecnico": "tecnico", "um tecnico": "tecnico", "o tecnico": "tecnico", "foi o tecnico": "tecnico",
    "cliente": "cliente", "o cliente": "cliente", "cliente pagou": "cliente", "o cliente pagou": "cliente",
    "cliente pagou direto": "cliente", "o cliente pagou direto": "cliente",
  },
  cobrar: {
    "cobrar": "cobrar", "cobra": "cobrar", "cliente paga": "cobrar", "cobrar do cliente": "cobrar", "cobra do cliente": "cobrar",
    "cobrar a parte": "cobrar", "cobra a parte": "cobrar", "repassa": "cobrar", "repassar": "cobrar", "repassa pro cliente": "cobrar",
    "custo": "custo", "hbr": "custo", "custo da hbr": "custo", "por nossa conta": "custo", "nossa conta": "custo",
    "da casa": "custo", "nao cobrar": "custo", "nao cobra": "custo", "custo nosso": "custo", "e custo": "custo",
    "por conta da casa": "custo", "por conta da hbr": "custo", "por conta nossa": "custo", "e por conta da casa": "custo",
  },
};

/**
 * A frase com UMA palavra-chave do passo ("paguei no débito", "pode cobrar", "é custo nosso",
 * "eu paguei do meu bolso"): vale se aparece exatamente uma classe; duas ("débito ou crédito?") não.
 */
const CHAVES_DO_PASSO: Record<string, Array<[Palavra, (tokens: string[], frase: string) => boolean]>> = {
  como_pagou: [
    ["pix", (k) => k.includes("pix")],
    ["debito", (k) => k.includes("debito")],
    ["credito", (k) => k.includes("credito")],
    ["dinheiro", (k) => k.includes("dinheiro") || k.includes("especie") || k.includes("cash")],
    ["boleto", (k) => k.includes("boleto")],
    ["transferencia", (k) => k.includes("transferencia") || k.includes("ted") || k.includes("transf")],
  ],
  cobrar: [
    // "não cobra(r)" é custo; "cobr…" sem o "não" antes é cobrar
    ["cobrar", (k, f) => k.some((t) => t.startsWith("cobr")) && !/\bnao cobr/.test(f)],
    ["custo", (k, f) => k.includes("custo") || k.includes("hbr") || / nossa conta /.test(` ${f} `) || / da casa /.test(` ${f} `)
      || /\bnao cobr/.test(f)],
  ],
  quem_pagou: [
    ["empresa", (k) => k.includes("empresa") || k.includes("caixa")],
    ["socio", (k) => k.includes("eu") || k.includes("bolso") || k.includes("socio")],
    ["tecnico", (k) => k.includes("tecnico")],
    ["cliente", (k) => k.includes("cliente")],
  ],
  para_que: [
    ["estoque", (k) => k.includes("estoque")],
    ["insumo", (k) => k.includes("insumo") || k.includes("insumos")],
    ["empresa", (k) => k.includes("empresa") || k.includes("administrativo")],
    ["pessoal", (k) => k.includes("pessoal") || k.includes("particular")],
  ],
};

function chaveUnica(passo: string, t: string): Palavra | null {
  const regras = CHAVES_DO_PASSO[passo];
  if (!regras) return null;
  const tokens = t.split(" ");
  if (tokens.length > 8) return null;
  const achadas = regras.filter(([, testa]) => testa(tokens, t)).map(([p]) => p);
  return achadas.length === 1 ? achadas[0] : null;
}

/** No corrigir, a palavra leva à opção (pelo valor da opção do banco). */
const PALAVRAS_DO_CORRIGIR: Record<string, string> = {
  "valor": "valor", "o valor": "valor", "data": "data", "a data": "data",
  "para que": "para_que", "para": "para_que", "destino": "para_que", "os": "para_que",
  "como pagou": "como_pagou", "forma": "como_pagou", "pagamento": "como_pagou", "como foi pago": "como_pagou",
  "quem pagou": "quem_pagou", "quem": "quem_pagou",
  "cobrar": "cobrar", "cobrar ou nao": "cobrar",
  "categoria": "categoria", "a categoria": "categoria",
  "cancelar": "cancelar", "cancela": "cancelar",
  "depois": "depois", "deixar para depois": "depois", "deixa pra depois": "depois", "mais tarde": "depois",
};

/** Verbos de pedido: texto que começa assim é conversa com o assistente, não nome de barco. */
const VERBOS_DE_PEDIDO = new Set([
  "lanca", "lance", "lancar", "manda", "mande", "mandar", "envia", "envie", "enviar", "cria", "crie", "criar", "faz", "faca",
  "fazer", "abre", "abra", "abrir", "agenda", "agende", "agendar", "marca", "marque", "registra", "registre", "cadastra",
  "cadastre", "busca", "busque", "procura", "procure", "mostra", "mostre", "ve", "veja", "ver", "verifica", "verifique", "liga",
  "ligue", "qual", "quais", "quanto", "quanta", "quantos", "quantas", "quando", "como", "onde", "quem", "porque", "por", "me",
  "preciso", "quero", "queria", "gostaria", "pode", "poderia", "consegue", "tem", "tenho", "vamos", "vai", "faltou", "falta",
  "esqueci", "cancela", "cancele", "apaga", "apague", "exclui", "exclua", "atualiza", "atualize", "muda", "mude", "altera",
  "altere", "gera", "gere", "emite", "emita", "aprova", "aprove", "paga", "pague", "cobra", "cobre", "avisa", "avise", "lembra",
  "lembre", "responde", "responda", "oi", "ola", "bom", "boa", "tudo", "e", "eh", "o", "a", "isso", "esse", "essa", "este",
  "esta", "nao", "sim", "ok", "corrigir", "corrige", "pular", "sair", "cmp", "pendentes", "lote", "saldo", "extrato",
  "orcamento", "tarefa", "tarefas", "agenda", "ja", "obrigado", "valeu",
]);

/** Pedido ou pergunta ao assistente (começa com verbo de pedido/pergunta, ou tem "?"). */
export function pareceConversa(original: string, t: string): boolean {
  if (/\?/.test(original)) return true;
  const primeira = t.split(" ")[0];
  return VERBOS_DE_PEDIDO.has(primeira) && !["sim", "nao", "ok", "isso", "e", "eh", "o", "a", "esse", "essa", "este", "esta"].includes(primeira);
}

/**
 * Nome (barco, cliente, técnico, categoria): sem o enchimento ("do", "barco", "o"…), 3 a 60 letras,
 * até 3 palavras, sem "?" e sem começar por verbo de pedido ("manda o orçamento do Brisa", "saldo
 * do nubank hoje" vão ao assistente).
 */
function lerNome(original: string, t: string, maxPalavras = 3): string | null {
  if (!t || t.length > 60 || /\?/.test(original) || !/^[a-z]/.test(t)) return null;
  if (VERBOS_DE_PEDIDO.has(t.split(" ")[0]) && !ENCHIMENTO.has(t.split(" ")[0])) return null;
  const limpo = semEnchimento(t);
  const letras = (limpo.match(/[a-z]/g) ?? []).length;
  if (letras < 3) return null;
  const palavras = limpo.split(" ");
  if (palavras.length > maxPalavras) return null;
  if (VERBOS_DE_PEDIDO.has(palavras[0])) return null;
  return limpo;
}

/** A opção cujo rótulo é exatamente o texto ("pix", "outras despesas", "empresa (sem os)"). */
function opcaoPeloRotulo(t: string, opcoes: Opcao[]): number | null {
  for (const o of opcoes) {
    const r = normalizarResposta(o.rotulo);
    const semParenteses = r.replace(/\s*\(.*\)\s*$/, "").trim();
    if (t === r || (semParenteses && t === semParenteses)) return o.n;
  }
  return null;
}

/**
 * O número com o rótulo do menu ("1 pix", "4 - dinheiro", "2) débito", "6 empresa"): vale se o
 * texto depois do número é o rótulo (ou o começo dele, ou uma palavra dele, ou a palavra do passo
 * que dá o mesmo valor). Número e rótulo que não batem ("1 dinheiro" com 1 = Pix) = não é resposta.
 */
function numeroComRotulo(passo: string, t: string, opcoes: Opcao[]): number | null {
  const m = /^0*(\d{1,2})\s*[-).:]*\s+(.+)$/.exec(t);
  if (!m) return null;
  const n = Number(m[1]);
  const o = opcoes.find((x) => x.n === n);
  if (!o) return null;
  const resto = m[2].replace(/[()]/g, " ").replace(/\s+/g, " ").trim();
  const rotulo = normalizarResposta(o.rotulo).replace(/[()·]/g, " ").replace(/\s+/g, " ").trim();
  if (!resto) return null;
  if (rotulo === resto || rotulo.startsWith(resto) || ` ${rotulo} `.includes(` ${resto} `)) return n;
  const palavra = PALAVRAS_DO_PASSO[passo]?.[resto] ?? chaveUnica(passo, resto);
  if (palavra && o.valor === palavra) return n;
  return null;
}

/** Número puro ("112"): opção do menu se cabe nele; senão, no para quê / qual OS, é o número da OS. */
function numeroPuro(t: string): number | null {
  const m = /^0*(\d{1,6})$/.exec(t);
  return m && Number(m[1]) > 0 ? Number(m[1]) : null;
}

/** "certo", "tá certo", "correto" valem como "sim" no passo valor (o valor lido está certo). */
const CERTO_NO_VALOR = new Set(["certo", "ta certo", "esta certo", "correto", "ta correto", "esta correto", "isso ai", "e isso"]);

/**
 * F3 (spec-f3.md, 4.2): "nenhuma destas" na pergunta do extrato. O 0 é a opção "Nenhuma destas" da
 * lista (o lerNumero não lê 0); no verde, "não é essa" é o mesmo "não".
 */
const NENHUMA_DO_EXTRATO = new Set([
  "0", "00", "zero", "opcao 0", "opcao zero", "numero 0",
  "nenhum", "nenhuma", "nenhum desses", "nenhuma dessas", "nenhuma destas", "nenhum destes", "nenhum deles", "nenhuma delas",
  "nao e nenhum", "nao e nenhuma", "nao eh nenhum", "nao eh nenhuma", "nao e nenhum desses", "nao e nenhuma dessas",
  "nao e essa", "nao e esse", "nao eh essa", "nao eh esse", "nao e essa nao", "nao e esse nao",
]);

/**
 * A resposta à pergunta do extrato (passo "banco"). Verde (sem a opção 0): sim/não/ok; um número
 * vira "ok" — número nunca liga no verde (o banco pede o sim de novo). Azul (com a opção 0): o
 * número da linha, ou 0/"nenhuma destas" (= não); número fora da lista vira "ok" (o banco pede o
 * número de novo, em vez de o "4" escapar ao assistente). O resto (texto livre) é null.
 */
function respostaDoExtrato(t: string, menu: Opcao[]): Interpretacao | null {
  if (NENHUMA_DO_EXTRATO.has(t)) return { tipo: "nao" };
  const sn = lerSimNao(t);
  if (sn) return { tipo: sn };
  const n = lerNumero(t, 99);
  if (n === null) return null;
  const azul = menu.some((o) => o.n === 0);
  if (!azul) return { tipo: "ok" };
  const linhas = menu.filter((o) => o.n > 0).map((o) => o.n);
  return linhas.includes(n) ? { tipo: "opcao", n } : { tipo: "ok" };
}

/**
 * O que a resposta quer dizer no passo (null = não é resposta: texto livre, que vai ao assistente
 * com a pergunta ainda aberta). sim/não/ok valem em qualquer passo (o banco decide o que fazem); no
 * confirmar, só eles — um número ou uma frase curta lá voltam como "ok" (nunca aprovam e pedem o
 * sim de novo, em vez de escapar ao assistente).
 */
export function interpretarResposta(
  passo: string | null | undefined,
  opcoes: Opcao[] | null | undefined,
  texto: string,
  agora: Date = new Date(),
): Interpretacao | null {
  const original = String(texto ?? "");
  const t = normalizarResposta(original);
  if (!t || t.length > 200) return null;
  const sn = lerSimNao(t);
  const menu = opcoesDoPasso(passo, opcoes);

  if (passo === "banco") return respostaDoExtrato(t, menu);
  if (passo === "confirmar") {
    if (sn) return { tipo: sn };
    if (lerNumero(t, 99) !== null) return { tipo: "ok" };
    // a frase curta ("sim, mas é da OS 12", "62,50", "beleza então") não aprova e não escapa:
    // pede o sim de novo. Pergunta ou pedido ao assistente segue para ele.
    if (t.split(" ").length <= 6 && !pareceConversa(original, t)) return { tipo: "ok" };
    return null;
  }
  if (passo === "valor" && CERTO_NO_VALOR.has(t)) return { tipo: "sim" };
  if (sn) return { tipo: sn };

  const n = lerNumero(t, menu.length);
  const comRotulo = menu.length ? numeroComRotulo(String(passo ?? ""), t, menu) : null;
  // "1 dinheiro" com 1 = Pix: número e rótulo que não batem não é resposta (nem pela palavra)
  const numeroQueNaoBate = comRotulo === null && /^0*\d{1,2}\s*[-).:]*\s+\S/.test(t);
  const t2 = semEnchimento(t);
  switch (passo) {
    case "valor": {
      const valor = lerValor(t);
      return valor ? { tipo: "valor", valor } : null;
    }
    case "data": {
      const data = lerData(t, agora);
      return data ? { tipo: "data", data } : null;
    }
    case "para_que":
    case "qual_os": {
      if (n !== null) return { tipo: "opcao", n };
      if (comRotulo !== null) return { tipo: "opcao", n: comRotulo };
      const os = lerOs(t) ?? lerOs(t2);
      if (os !== null) return { tipo: "os", numero: os };
      const puro = numeroPuro(t);
      if (puro !== null) return { tipo: "os", numero: puro };
      if (numeroQueNaoBate) return null;
      if (passo === "para_que") {
        const palavra = PALAVRAS_DO_PASSO.para_que[t] ?? PALAVRAS_DO_PASSO.para_que[t2];
        if (palavra) return { tipo: "palavra", valor: palavra };
      }
      const pelo = opcaoPeloRotulo(t, menu) ?? opcaoPeloRotulo(t2, menu);
      if (pelo !== null) return { tipo: "opcao", n: pelo };
      if (passo === "para_que" && !pareceConversa(original, t)) {
        const chave = chaveUnica("para_que", t);
        if (chave) return { tipo: "palavra", valor: chave };
      }
      const nome = lerNome(original, t);
      return nome ? { tipo: "nome", texto: nome } : null;
    }
    case "mesma_compra": {
      if (n !== null) return { tipo: "opcao", n };
      if (comRotulo !== null) return { tipo: "opcao", n: comRotulo };
      const k = t2.split(" ");
      const mesma = k.includes("mesma") || k.includes("igual") || k.includes("repetido") || k.includes("repetida");
      const outra = k.includes("outra") || k.includes("diferente");
      const alvo = mesma && !outra ? "mesma" : outra && !mesma ? "outra" : null;
      const o = alvo ? menu.find((x) => x.valor === alvo) : undefined;
      return o ? { tipo: "opcao", n: o.n } : null;
    }
    case "como_pagou":
    case "quem_pagou":
    case "cobrar": {
      if (n !== null) return { tipo: "opcao", n };
      if (comRotulo !== null) return { tipo: "opcao", n: comRotulo };
      if (numeroQueNaoBate) return null;
      const palavra = PALAVRAS_DO_PASSO[passo][t] ?? PALAVRAS_DO_PASSO[passo][t2];
      if (palavra) return { tipo: "palavra", valor: palavra };
      const pelo = opcaoPeloRotulo(t, menu);
      if (pelo !== null) return { tipo: "opcao", n: pelo };
      // "por conta da casa", "pode cobrar", "cobra sim" começam como pedido, mas são a resposta do passo
      if (pareceConversa(original, t) && !t.startsWith("pode cobr") && !t.startsWith("cobra") && !t.startsWith("por conta")) return null;
      const chave = chaveUnica(passo, t);
      return chave ? { tipo: "palavra", valor: chave } : null;
    }
    case "qual_tecnico":
    case "categoria": {
      if (n !== null) return { tipo: "opcao", n };
      if (comRotulo !== null) return { tipo: "opcao", n: comRotulo };
      const pelo = opcaoPeloRotulo(t, menu) ?? opcaoPeloRotulo(t2, menu);
      if (pelo !== null) return { tipo: "opcao", n: pelo };
      const nome = lerNome(original, t, passo === "categoria" ? 5 : 3);
      return nome ? { tipo: "nome", texto: nome } : null;
    }
    case "corrigir": {
      if (n !== null) return { tipo: "opcao", n };
      if (comRotulo !== null) return { tipo: "opcao", n: comRotulo };
      const valor = PALAVRAS_DO_CORRIGIR[t] ?? PALAVRAS_DO_CORRIGIR[t2];
      const opcao = valor ? menu.find((o) => o.valor === valor) : undefined;
      if (opcao) return { tipo: "opcao", n: opcao.n };
      const pelo = opcaoPeloRotulo(t, menu);
      return pelo !== null ? { tipo: "opcao", n: pelo } : null;
    }
    default:
      return n !== null ? { tipo: "opcao", n } : null;
  }
}

/**
 * Mensagem curta que NÃO é resposta nem conversa ("cartão", "sessenta e dois"): com a pergunta do
 * CMP aberta, recebe "Não entendi para o CMP-00124…" + a pergunta de novo em vez de ir ao assistente
 * (que não sabe da pergunta). Até 3 palavras, sem "?", sem verbo de pedido nem saudação.
 */
export function respostaNaoEntendida(texto: string): boolean {
  const original = String(texto ?? "");
  const t = normalizarResposta(original);
  if (!t || t.length > 40) return false;
  if (t.split(" ").length > 3) return false;
  if (pareceConversa(original, t)) return false;
  return /[a-z0-9]/.test(t);
}

/**
 * A frase solta logo depois da foto ("essa é da OS do Brisa", "gasolina do Brisa"): dica do CMP que
 * está chegando, não conversa com o assistente. Sem "?", até 12 palavras, sem verbo de pedido.
 */
export function pareceDica(texto: string): boolean {
  const original = String(texto ?? "");
  const t = normalizarResposta(original);
  if (!t || t.length > 200 || /\?/.test(original)) return false;
  if (t.split(" ").length > 12) return false;
  const primeira = t.split(" ")[0];
  if (VERBOS_DE_PEDIDO.has(primeira) && !["e", "eh", "esse", "essa", "este", "esta", "o", "a"].includes(primeira)) return false;
  return lerSimNao(t) === null && lerNumero(t, 99) === null;
}

// ---------------------------------------------------------------------------------------------
// Comandos (no começo da mensagem)
// ---------------------------------------------------------------------------------------------

export type Forma = "pix" | "debito" | "credito" | "dinheiro" | "boleto" | "transferencia";
export type DestinoSimples = "estoque" | "insumo" | "empresa" | "pessoal";

/** `cmp` = o número do CMP dito ("corrigir cmp 124 valor 70"); sem ele, o da pergunta aberta. */
type Alvo = { cmp?: number };

export type Comando =
  | { comando: "pendentes" }
  | { comando: "cmp"; numero: number }
  | { comando: "cancelar"; numero: number; motivo: string | null }
  /** "cancelar esse <motivo>" / "cancela o último": o CMP em contexto (o edge resolve o número). */
  | { comando: "cancelar_contexto"; motivo: string | null }
  | { comando: "feito"; numero: number }
  | { comando: "lote_antigo" }
  | { comando: "pular" }
  | { comando: "sair" }
  | ({ comando: "corrigir"; campo: "valor"; valor: string } & Alvo)
  | ({ comando: "corrigir"; campo: "data"; data: string } & Alvo)
  | ({ comando: "corrigir"; campo: "forma"; forma: Forma } & Alvo)
  | ({ comando: "corrigir"; campo: "os"; numero: number } & Alvo)
  | ({ comando: "corrigir"; campo: "quem" } & Alvo)
  | ({ comando: "corrigir"; campo: "para"; destino?: DestinoSimples } & Alvo)
  | ({ comando: "corrigir"; campo: "categoria"; categoria?: string } & Alvo)
  /** "corrigir valor" sem o valor: o edge responde como mandar (não vai ao banco). */
  | { comando: "corrigir_incompleto"; campo: "valor" | "data" | "forma" | "os" }
  /** "corrigir" sozinho: no resumo, o menu do corrigir; fora dele, como mandar. */
  | { comando: "corrigir_menu" };

export type ClasseDoComando = "pendentes" | "comprovante" | "contexto";

/** "pendentes" = o comando pendentes; "comprovante" = cmp N / cancelar / feito / lote antigo; "contexto" = corrigir / pular / sair / cancelar esse. */
export function classeDoComando(c: Comando | null): ClasseDoComando | null {
  if (!c) return null;
  if (c.comando === "pendentes") return "pendentes";
  if (c.comando === "cmp" || c.comando === "cancelar" || c.comando === "feito" || c.comando === "lote_antigo") return "comprovante";
  return "contexto";
}

const FORMAS: Record<string, Forma> = {
  "pix": "pix", "debito": "debito", "credito": "credito", "dinheiro": "dinheiro", "especie": "dinheiro", "boleto": "boleto",
  "transferencia": "transferencia", "ted": "transferencia", "transf": "transferencia",
};

const DESTINOS: Record<string, DestinoSimples> = {
  "estoque": "estoque", "insumo": "insumo", "insumos": "insumo", "empresa": "empresa", "pessoal": "pessoal", "particular": "pessoal",
};

const CMP = String.raw`cmp[\s-]*0*(\d{1,6})`;

/** "c.m.p. 124", "cê eme pê 124" (o Whisper) e "comprovante 124" viram "cmp 124". */
function comCmp(t: string): string {
  return t
    .replace(/\bc\s?\.\s?m\s?\.\s?p\b\.?/g, "cmp")
    .replace(/\b(?:ce|se) (?:eme|m) (?:pe|p)\b/g, "cmp")
    .replace(/\bcomprovante(?= *-? *0*\d)/g, "cmp");
}

/**
 * O comando no começo da mensagem: pendentes; cmp 124 / cmp-00124; cancelar cmp 124 <motivo>;
 * cancelar esse <motivo>; feito cmp 124; lote antigo; pular (pula esse, depois, mais tarde); sair/parar;
 * corrigir [cmp 124] valor 62,50 | data 10/10 | forma pix | pix | os 112 | quem | para [estoque] |
 * categoria [nome]; corrigir sozinho. "sim, mas é da OS 12" não é comando.
 */
export function lerComando(texto: string, agora: Date = new Date()): Comando | null {
  const original = String(texto ?? "").trim();
  const t = comCmp(normalizarResposta(original)).replace(/\s*:\s*/g, " ").replace(/\s+/g, " ").trim();
  if (!t || t.length > 400) return null;

  if (/^(?:pendentes|pendencias|pendente|pendencia|comprovantes pendentes|cmp pendentes|comprovantes em aberto)$/.test(t)) {
    return { comando: "pendentes" };
  }
  if (/^lotes? antigos?$/.test(t)) return { comando: "lote_antigo" };
  if (/^(?:pular|pula|pule|pula esse|pula essa|pula este|pula esta|depois|mais tarde|deixa pra depois|deixa para depois|deixar para depois|depois eu vejo|vejo depois)$/.test(t)) {
    return { comando: "pular" };
  }
  if (/^(?:sair|parar|pare|chega por hoje)$/.test(t)) return { comando: "sair" };

  let m = new RegExp(`^${CMP}$`).exec(t);
  if (m) return { comando: "cmp", numero: Number(m[1]) };
  m = new RegExp(`^feito (?:o )?${CMP}$`).exec(t);
  if (m) return { comando: "feito", numero: Number(m[1]) };
  m = new RegExp(`^cancela(?:r)? (?:o )?${CMP}(?:\\b.*)?$`).exec(t);
  if (m) {
    // o motivo vem do texto original (com acento e maiúsculas), sem a pontuação de ligação
    const semMarca = comCmpOriginal(original.replace(/^[\s🎤"'“”‘’«»]+/u, ""));
    const mo = /^cancela(?:r)?\s+(?:o\s+)?cmp[\s-]*0*\d{1,6}\s*[,.:;-]*\s*(.*)$/i.exec(semMarca);
    const motivo = (mo?.[1] ?? "").replace(/[\s.!"”’]+$/u, "").trim();
    return { comando: "cancelar", numero: Number(m[1]), motivo: motivo || null };
  }
  m = /^cancela(?:r)? (?:esse|essa|este|esta|o ultimo|a ultima|o comprovante|esse comprovante)(?: (.*))?$/.exec(t);
  if (m) {
    const mo = /^cancela(?:r)?\s+(?:esse|essa|este|esta|o\s+[uú]ltimo|a\s+[uú]ltima|o\s+comprovante|esse\s+comprovante)\s*[,.:;-]*\s*(.*)$/i
      .exec(original.replace(/^[\s🎤"'“”‘’«»]+/u, ""));
    const motivo = (mo?.[1] ?? "").replace(/[\s.!"”’]+$/u, "").trim();
    return { comando: "cancelar_contexto", motivo: motivo || null };
  }

  if (/^corrig(?:ir|e|a)$/.test(t)) return { comando: "corrigir_menu" };
  m = /^corrig(?:ir|e|a)\s+(.+)$/.exec(t);
  if (!m) return null;
  let resto = m[1].trim();
  let alvo: Alvo = {};
  const doCmp = new RegExp(`^${CMP}\\s+(.+)$`).exec(resto);
  if (doCmp) {
    alvo = { cmp: Number(doCmp[1]) };
    resto = doCmp[2].trim();
  }
  resto = resto.replace(/^(?:o|a)\s+/, "");
  let r: RegExpExecArray | null;
  if ((r = /^valor(?: (?:para |pra |e |de )?(.+))?$/.exec(resto))) {
    const valor = r[1] ? lerValor(r[1]) : null;
    return valor ? { comando: "corrigir", campo: "valor", valor, ...alvo } : { comando: "corrigir_incompleto", campo: "valor" };
  }
  if ((r = /^data(?: (?:para |pra |e |de )?(.+))?$/.exec(resto))) {
    const data = r[1] ? lerData(r[1], agora) : null;
    return data ? { comando: "corrigir", campo: "data", data, ...alvo } : { comando: "corrigir_incompleto", campo: "data" };
  }
  if ((r = /^(?:forma|pagamento|forma de pagamento)(?: (?:para |pra |e |de )?(?:no |em )?(.+))?$/.exec(resto))) {
    const forma = r[1] ? FORMAS[r[1].trim()] : undefined;
    return forma ? { comando: "corrigir", campo: "forma", forma, ...alvo } : { comando: "corrigir_incompleto", campo: "forma" };
  }
  if (FORMAS[resto]) return { comando: "corrigir", campo: "forma", forma: FORMAS[resto], ...alvo };
  if ((r = /^os(?:[\s-]*(?:para |pra |e )?(?:os[\s-]*)?0*(\d{1,6}))?$/.exec(resto))) {
    const numero = r[1] ? Number(r[1]) : 0;
    return numero > 0 ? { comando: "corrigir", campo: "os", numero, ...alvo } : { comando: "corrigir_incompleto", campo: "os" };
  }
  if (/^quem(?: pagou)?$/.test(resto)) return { comando: "corrigir", campo: "quem", ...alvo };
  if ((r = /^(?:para(?: que| quem)?|destino)(?: (?:para |pra |e |o |a )?(.+))?$/.exec(resto))) {
    if (!r[1]) return { comando: "corrigir", campo: "para", ...alvo };
    const destino = DESTINOS[r[1].trim()];
    return destino ? { comando: "corrigir", campo: "para", destino, ...alvo } : null;
  }
  if ((r = /^categoria(?: (?:para |pra |e |de )?(.+))?$/.exec(resto))) {
    return r[1] ? { comando: "corrigir", campo: "categoria", categoria: r[1].trim().slice(0, 100), ...alvo }
      : { comando: "corrigir", campo: "categoria", ...alvo };
  }
  return null;
}

/** O "c.m.p." / "comprovante 124" também no texto original (o motivo do cancelar sai dele). */
function comCmpOriginal(s: string): string {
  return s.replace(/\bc\s?\.\s?m\s?\.\s?p\b\.?/gi, "cmp").replace(/\bcomprovante(?= *-? *0*\d)/gi, "cmp");
}
