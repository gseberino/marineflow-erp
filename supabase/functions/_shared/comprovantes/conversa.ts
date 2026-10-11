// Os textos da conversa dos comprovantes (F2, 11/10/2026 — spec-f2.md, 3.3).
//
// Textos FIXOS: o banco decide o passo, as opções e o plano; aqui só se monta a mensagem. Todo texto
// leva o código CMP; sem emoji (a marca 🤖 só no par do histórico do assistente). Fornecedor só do
// cadastro ou da Receita (BrasilAPI), nunca do OCR; nunca CPF. Até 4096 caracteres.
//
// Revisão de 11/10/2026: o resumo mostra o que o dono ainda não conferiu (valor lido sem certeza,
// data do dia do envio), a categoria em todo destino, de QUAL registro é o "usar o que já existe";
// OS concluída ≠ faturada; o CMP sem leitura diz de quando é a foto; os erros da rota viram texto do
// dono (e o código vai para app_error_logs).
//
// F3 (11/10/2026 — spec-f3.md, 4.3): a pergunta do extrato (verde: "apareceu no extrato, ligo?";
// azul: a lista com "0 Nenhuma destas"), os resultados da resposta, o "No extrato:" do cartão e os
// efeitos novos do plano e da gravação (ligar_linha, aguardar_banco, reembolso_tecnico).
//
// Ajustes do dono (11/10/2026 — spec-ajustes-dono.md): o comprovante NUNCA aparece para o cliente
// nem muda o total da OS — o "cobrar do cliente?" saiu; na OS, primeiro o lançamento que já existe
// (só comprova), senão "peça ou despesa" (a despesa é custo interno). O sim já lança a linha no
// Extrato (aprovada no sim). PESSOAL pago pela empresa é gasto pessoal do sócio (desconta do
// pró-labore). Lançamento que já existe só tem o vazio preenchido. "Quem pagou?" depois de 5 dias
// sem aparecer em conta da empresa (regra E). O reembolso nas Diárias é "reembolso de despesa paga
// pelo técnico".
import { type Opcao, passoLegivel } from "../whatsapp/pergunta-ativa.ts";
import { diaMes, faixaDeCodigos, formatarCnpj, formatarReais, horaNoNome, PASTA_COMPROVANTES, TIPO_NO_AVISO } from "./nucleo.ts";
import { type Interpretacao, MENU_QUEM_PAGOU_PESSOAL, opcoesDoPasso } from "./respostas.ts";

// ---------------------------------------------------------------------------------------------
// As formas do banco (spec 2.3, 2.6.2, 2.6.3)
// ---------------------------------------------------------------------------------------------

export type OsDoCmp = {
  id: string;
  numero: string;
  barco: string | null;
  cliente: string | null;
  status: string;
  faturada?: boolean;
  assinada?: boolean;
  pasta_registrada?: boolean;
};

/**
 * O que o banco achou já lançado na OS para o comprovante (`_comprovante_lancamento_na_os`): uma
 * despesa ou uma peça (o CMP só comprova), ou duas ou mais iguais (`ambiguo`: não escolhe nenhuma).
 */
export type LancamentoNaOs = {
  /** "despesa" ou "peca" (o lançamento que já está na OS); ausente com `ambiguo`. */
  tipo?: "despesa" | "peca" | string;
  /** Quantos lançamentos iguais há na OS (2+: o CMP não escolhe nenhum). */
  ambiguo?: number;
  id?: string | null;
  descricao?: string | null;
  categoria?: string | null;
  produto?: string | null;
  valor?: string | number | null;
  data?: string | null;
};

export type CmpResumo = {
  id: string;
  codigo: string;
  numero?: number | null;
  situacao: string;
  tipo: string | null;
  valor: string | null;
  valor_lido?: string | null;
  valor_confianca?: string | null;
  data: string | null;
  /** De onde veio a data: lida do documento, o dia do envio (a leitura não trouxe) ou dita pelo dono. */
  data_origem?: "leitura" | "envio" | "dono" | null;
  /** Quando chegou ao WhatsApp (o cabeçalho do CMP sem leitura diz de quando é a foto). */
  recebido_em?: string | null;
  hora?: string | null;
  forma?: string | null;
  fornecedor?: string | null;
  fornecedor_origem?: "cadastro" | "receita" | null;
  cnpj?: string | null;
  cnpj_confianca?: string | null;
  destino?: string | null;
  os?: OsDoCmp | null;
  /** Ajustes do dono: peça ou despesa da OS (nulo = não perguntado, ou resolvido pelo lançamento que já existe). */
  tipo_na_os?: "peca" | "despesa" | string | null;
  /** O lançamento que já está na OS e que o CMP só comprova (ou `ambiguo`). */
  na_os?: LancamentoNaOs | null;
  quem_pagou?: string | null;
  pagador_nome?: string | null;
  categoria?: string | null;
  /** O dono disse que é a mesma compra deste outro CMP (só o arquivo). */
  mesma_compra?: { codigo: string } | null;
  pendencias?: string[];
  gravado_em?: string | null;
  /** F3: onde o CMP está na conciliação com o extrato (null = não procura linha). */
  banco?: BancoNoResumo | null;
};

// ---------------------------------------------------------------------------------------------
// F3: as formas da conciliação com o extrato (spec-f3.md, 3.7)
// ---------------------------------------------------------------------------------------------

/**
 * O que ligar a linha faz com ela: classificar a proposta, anexar ao lançamento, casar com a conta aberta, esperar a compra
 * confirmar. "conflito": o CMP anexou uma conta a pagar em aberto e a linha já virou OUTRO lançamento (o mesmo gasto duas
 * vezes) — não liga; o dono cancela um dos dois no Financeiro.
 */
export type AcaoNaLinha = "classificar" | "anexar" | "casar" | "aguardar" | "conflito";

/** Uma linha do extrato candidata a um CMP (`Candidata`) ou a do resumo (`LinhaCurta`). */
export type LinhaDoBanco = {
  n?: number;
  id?: string;
  data: string | null;
  valor: string | number | null;
  descricao?: string | null;
  nome?: string | null;
  conta?: string | null;
  cartao?: boolean;
  /** "1/3" na compra parcelada. */
  parcela?: string | null;
  total_da_compra?: string | number | null;
  /** A compra ainda está PENDING no cartão (sem proposta na fila do Extrato). */
  pendente?: boolean;
  acao?: AcaoNaLinha | string | null;
  /**
   * A linha já virou lançamento. `os_numero` nulo = a OS dele está vazia (o CMP preenche); ausente =
   * o banco não disse (o texto não promete preencher a OS).
   */
  lancamento?: { categoria?: string | null; descricao?: string | null; os_numero?: string | null } | null;
  /** A conta a pagar em aberto que o CMP anexou (casar; conflito). */
  conta_aberta?: { descricao?: string | null; valor?: string | number | null } | null;
  motivos?: string[];
  forte?: boolean;
};

/** A última avaliação do CMP contra o extrato (`Avaliacao`). */
export type AvaliacaoDoBanco = {
  regra?: string | null;
  nivel: "verde" | "azul" | "cinza" | string;
  linhas: LinhaDoBanco[];
  /** Quantas candidatas ficaram fora da lista (só as 3 mais próximas vão nela). */
  mais?: number;
  hash?: string | null;
};

/** `CmpResumo.banco` (`BancoNoResumo`). */
export type BancoNoResumo = {
  /** "banco_quem": a regra E (5 dias sem aparecer em conta da empresa) espera o "quem pagou?". */
  estado: "esperando" | "perguntar" | "pergunta_aberta" | "ligado" | "abandonado" | "banco_quem" | string;
  nivel?: string | null;
  desde?: string | null;
  /** O dia do abandono (30 dias; 45 no crédito). */
  ate?: string | null;
  linha?: { data?: string | null; valor?: string | number | null; descricao?: string | null; conta?: string | null; como?: string | null } | null;
  candidatos?: number;
};

/**
 * A pergunta do extrato (`PerguntaDoBancoF3`): passo "banco" no registro único da F2. Regra E
 * (ajustes do dono): passo "banco_quem" ("Quem pagou?"), com as opções empresa / socio /
 * payee:<uuid> / pessoal e `banco.nivel` = "cinza".
 */
export type PerguntaDoExtrato = {
  pergunta_id: string;
  dedupe_key: string;
  cmp: CmpResumo;
  passo: string;
  opcoes: Opcao[];
  retomada?: boolean;
  banco: AvaliacaoDoBanco | null;
};

/** A proposta da fila do Extrato que o sim do dono aprova (R11; null = nada a aprovar agora). */
export type AAprovar = { proposta_id?: string | null } | null;

/**
 * O que comprovante_banco_responder devolve (`RespostaDoBanco`). Regra E (passo banco_quem):
 * "esperando" (a empresa pagou: continua esperando o extrato), "regravado" (desfez e gravou de novo
 * com o pagador certo, na mesma transação: `gravacao`) ou "nao_trocado" (bloqueio ou erro de rota:
 * nada mudou, `motivo`/`bloqueios`).
 */
export type RespostaDoBanco = {
  resultado:
    | "ligado" | "recusado" | "mudou" | "invalida" | "ok_nao_aprova" | "ignorada" | "nao_ligado"
    | "esperando" | "regravado" | "nao_trocado" | string;
  cmp?: CmpResumo | null;
  /** O efeito ligar_linha gravado (como, mensagens da rota…). */
  ligacao?: Efeito | null;
  proxima?: PerguntaDoExtrato | null;
  motivo?: string | null;
  ate?: string | null;
  /** Ajustes do dono: a proposta classificada que o sim aprova (o edge chama o finance-review). */
  aprovar?: AAprovar;
  /** Regra E, "regravado": a gravação de novo. */
  gravacao?: Gravacao | null;
  /** Regra E, "nao_trocado": os bloqueios do desfazer (os mesmos do cancelar). */
  bloqueios?: Array<{ efeito?: string; motivo?: string; como_destravar?: string }>;
};

/**
 * O resultado da aprovação da linha no Extrato pelo sim (a ação approve_cmp do finance-review):
 * ok = lançada; nada = não havia proposta a aprovar ainda; ok false = falhou (o próximo "gerar" do
 * Extrato tenta de novo).
 */
export type Aprovacao = { ok: boolean; nada?: boolean; motivo?: string | null };

export type Efeito = { tipo: string; [campo: string]: unknown };

export type Plano = { efeitos: Efeito[]; avisos?: string[]; situacao_final?: string; pasta?: string };

export type PerguntaDoBanco = {
  pergunta_id: string;
  dedupe_key: string;
  cmp: CmpResumo;
  passo: string;
  opcoes: Opcao[];
  posicao?: number;
  total?: number;
  primeira_do_lote?: { n: number; codigos: string[]; antigos?: number } | null;
  retomada?: boolean;
  /** O passo veio do "corrigir" (o dono disse que o dado estava errado). */
  forcado?: boolean;
  /** No passo mesma_compra: o CMP que parece ser a mesma compra. */
  mesma_compra?: { codigo: string; valor?: string | null; data?: string | null } | null;
  avisos?: string[];
  plano?: Plano | null;
  versao?: number | null;
  pasta?: string | null;
};

export type Gravacao = {
  situacao: string;
  efeitos: Efeito[];
  avisos?: string[];
  mensagens?: string[];
  mes?: string | null;
  pasta?: string | null;
  /** F3: o nível da avaliação do plano e se há pergunta do extrato a fazer logo depois (azul). */
  banco?: { nivel?: string | null; perguntar?: boolean } | null;
  /** Ajustes do dono: ligou e classificou na gravação — a proposta que o sim aprova. */
  aprovar?: AAprovar;
};

export const MAX_MENSAGEM = 4096;

function cortar(texto: string): string {
  return texto.length <= MAX_MENSAGEM ? texto : `${texto.slice(0, MAX_MENSAGEM - 1)}…`;
}

// ---------------------------------------------------------------------------------------------
// Peças
// ---------------------------------------------------------------------------------------------

/** O número do CMP para os comandos ("cmp 124"). */
export function numeroDoCmp(cmp: Pick<CmpResumo, "numero" | "codigo">): number | null {
  if (typeof cmp.numero === "number" && cmp.numero > 0) return cmp.numero;
  const m = /(\d+)$/.exec(String(cmp.codigo ?? ""));
  return m ? Number(m[1]) : null;
}

/** Fornecedor: o cadastro; senão a Receita, com " (Receita)"; senão o CNPJ formatado; senão nada. */
export function fornecedorDoCmp(cmp: CmpResumo): string | null {
  if (cmp.fornecedor && cmp.fornecedor_origem === "receita") return `${cmp.fornecedor} (Receita)`;
  if (cmp.fornecedor) return cmp.fornecedor;
  const digitos = String(cmp.cnpj ?? "");
  if (/^\d{14}$/.test(digitos)) return `CNPJ ${formatarCnpj(digitos)}`;
  return null;
}

/** O valor ainda não conferido pelo dono: lido sem selo alta (o banco não copiou, ou copiou o de selo média). */
function valorSemConferir(cmp: CmpResumo): boolean {
  const naoConfirmado = cmp.valor == null ||
    (cmp.valor_confianca === "media" && cmp.valor_lido != null && Number(cmp.valor) === Number(cmp.valor_lido));
  return naoConfirmado && cmp.valor_confianca !== "alta";
}

/** "R$ 62,00", com " (confira)" quando o selo não é alta e o dono ainda não confirmou. */
function valorDoCabecalho(cmp: CmpResumo): string | null {
  const reais = formatarReais(cmp.valor ?? cmp.valor_lido ?? null);
  if (!reais) return null;
  return valorSemConferir(cmp) ? `${reais} (confira)` : reais;
}

/** "foto das 10h41 de 11/10" (quando a leitura não trouxe o bastante para o dono reconhecer). */
function deQuandoEhAFoto(cmp: CmpResumo): string | null {
  const t = Date.parse(String(cmp.recebido_em ?? ""));
  if (Number.isNaN(t)) return null;
  const p = new Intl.DateTimeFormat("pt-BR", {
    timeZone: "America/Sao_Paulo", day: "2-digit", month: "2-digit", hour: "2-digit", minute: "2-digit", hour12: false,
  }).formatToParts(new Date(t));
  const v = (tipo: string) => p.find((x) => x.type === tipo)?.value ?? "";
  return `foto das ${v("hour")}h${v("minute")} de ${v("day")}/${v("month")}`;
}

function osComNome(os: OsDoCmp, sep = " "): string {
  const nome = os.barco || os.cliente;
  return nome ? `${os.numero}${sep}${nome}` : os.numero;
}

/** "CMP-00124 (1 de 4) · cupom NFC-e · Auto Posto Exemplo · 10/10 · R$ 62,00". */
export function cabecalho(p: Pick<PerguntaDoBanco, "cmp" | "posicao" | "total">): string {
  const c = p.cmp;
  const posicao = (p.total ?? 0) > 1 && (p.posicao ?? 0) > 0 ? ` (${p.posicao} de ${p.total})` : "";
  const fornecedor = fornecedorDoCmp(c);
  const valor = valorDoCabecalho(c);
  // sem fornecedor ou sem valor, o dono não reconhece a foto: diz de quando ela é
  const foto = !fornecedor || !valor ? deQuandoEhAFoto(c) : null;
  return [`${c.codigo}${posicao}`, TIPO_NO_AVISO[c.tipo ?? ""] ?? "documento", fornecedor, diaMes(c.data), valor, foto]
    .filter((x): x is string => Boolean(x))
    .join(" · ");
}

function linhas(opcoes: Opcao[]): string {
  return opcoes.map((o) => `${o.n} ${o.rotulo}`).join("\n");
}

/** O texto do passo (depois do cabeçalho). */
export function textoDoPasso(p: PerguntaDoBanco): string {
  const c = p.cmp;
  // o quem pagou do PESSOAL é um sim/não (o banco manda as opções; sem elas, o menu fixo dele)
  const pessoal = p.passo === "quem_pagou" && c.destino === "pessoal";
  const menu = pessoal && !(Array.isArray(p.opcoes) && p.opcoes.length) ? MENU_QUEM_PAGOU_PESSOAL : opcoesDoPasso(p.passo, p.opcoes);
  switch (p.passo) {
    case "valor": {
      const lido = formatarReais(c.valor_lido ?? null);
      // do "corrigir" (o dono disse que está errado) ou lido com selo alta/média: o valor certo, sem "sim"
      if (p.forcado || c.valor_confianca === "alta" || c.valor_confianca === "media" || !lido) {
        return lido ? `${c.codigo}: qual o valor certo? (ex.: 62,50)` : "Qual o valor? Responda só o número (ex.: 62,50).";
      }
      return `Li ${lido}, mas sem certeza. Responda *sim* se está certo, ou o valor certo (ex.: 62,50).`;
    }
    case "para_que":
      return `Para quê?\n${linhas(menu)}\nResponda o número, o nome do barco ou *os N*.`;
    case "qual_os":
      return menu.length
        ? `Qual OS? Responda o número da lista, *os N* ou o nome do barco.\n${linhas(menu)}`
        : "Qual OS? Responda *os N* ou o nome do barco.";
    case "mesma_compra": {
      const m = p.mesma_compra;
      const de = m ? [formatarReais(m.valor ?? null), diaMes(m.data ?? null)].filter(Boolean).join(" em ") : "";
      return `Parece a mesma compra do ${m?.codigo ?? "outro comprovante"}${de ? ` (${de})` : ""}, que já foi gravado. É a mesma?\n${linhas(menu)}`;
    }
    case "como_pagou":
      return `Como foi pago?\n${linhas(menu)}`;
    case "quem_pagou":
      return pessoal
        ? `Gasto pessoal. Saiu da conta ou do cartão da EMPRESA?\n${linhas(menu)}`
        : `Quem pagou?\n${linhas(menu)}`;
    case "qual_tecnico":
      return `Qual técnico pagou?\n${linhas(menu)}\nOu escreva o nome.`;
    case "tipo_na_os":
      // ajustes do dono: o comprovante nunca entra no total nem aparece para o cliente
      return `Para a ${c.os ? osComNome(c.os, " · ") : "OS"}: o que foi esta compra?\n${linhas(menu)}`;
    case "categoria":
      return `Qual a categoria?\n${linhas(menu)}\nOu escreva o nome da categoria.`;
    case "data":
      return "Qual a data da compra? (ex.: 10/10)";
    case "corrigir":
      return `${c.codigo}: o que corrigir?\n${linhas(menu)}`;
    default:
      return `Responda à pergunta sobre ${passoLegivel(p.passo)}.`;
  }
}

/**
 * A linha antes da pergunta: a primeira do lote ("Recebi 4 comprovantes: …", com os antigos da fila à
 * parte), a retomada do vigia ("Ainda falta conferir o CMP-00124.") ou nada.
 */
export function prefixoDaPergunta(p: PerguntaDoBanco, motivo: string): string | null {
  const lote = p.primeira_do_lote;
  if (lote && lote.n >= 1 && (motivo === "abertura" || motivo === "lote_antigo")) {
    const codigos = (lote.codigos ?? []).filter(Boolean);
    const antigos = Math.max(0, Number(lote.antigos ?? 0) || 0);
    const fila = antigos === 1 ? " Há também 1 antigo na fila." : antigos > 1 ? ` Há também ${antigos} antigos na fila.` : "";
    if (lote.n === 1) return `Recebi o comprovante ${codigos[0] ?? p.cmp.codigo}.${fila}`;
    return `Recebi ${lote.n} comprovantes: ${faixaDeCodigos(codigos.length ? codigos : [p.cmp.codigo])}. Vou perguntar um de cada vez (para parar: *sair*).${fila}`;
  }
  if (motivo === "vigia" && p.retomada) return `Ainda falta conferir o ${p.cmp.codigo}.`;
  return null;
}

/** A pergunta inteira: prefixo, cabeçalho e passo — ou o resumo, no passo confirmar. */
export function textoDaPergunta(p: PerguntaDoBanco, prefixo: string | null = null): string {
  const corpo = p.passo === "confirmar" ? textoDoResumo(p) : `${cabecalho(p)}\n${textoDoPasso(p)}`;
  return cortar(prefixo ? `${prefixo}\n${corpo}` : corpo);
}

// ---------------------------------------------------------------------------------------------
// O resumo antes do sim
// ---------------------------------------------------------------------------------------------

const FORMA_TEXTO: Record<string, string> = {
  pix: "Pix", debito: "débito", credito: "crédito", dinheiro: "dinheiro", boleto: "boleto", transferencia: "transferência",
  deposito: "depósito", cheque: "cheque", credito_loja: "crédito na loja", outro: "outra forma",
};

/** "o Pix", "o débito", "a transferência". */
function formaComArtigo(forma: string | null | undefined): string {
  const t = FORMA_TEXTO[String(forma ?? "")] ?? "pagamento";
  return forma === "transferencia" ? `a ${t}` : `o ${t}`;
}

export const PENDENCIA_TEXTO: Record<string, string> = {
  dar_entrada: "dar entrada no estoque",
  // ajustes do dono: o comprovante de peça só comprova; a peça entra pela OS
  incluir_na_os: "lançar a peça na OS, se ainda não lançou",
  acerto_tecnico: "acerto do técnico",
  classificar_no_extrato: "classificar no Extrato",
  dar_baixa: "dar baixa na conta a pagar",
  conferir_estorno: "conferir a despesa da compra estornada no banco",
  // regra E (revisão dos ajustes): o dono disse que não foi a empresa e a compra apareceu numa conta dela
  conferir_quem_pagou: "conferir quem pagou: a compra apareceu numa conta da empresa",
};

/** "a despesa (Combustível e deslocamento) R$ 62,00 de 10/10" — o que já estava lançado na OS. */
function jaLancadoNaOs(n: LancamentoNaOs, c: CmpResumo): string {
  const valor = formatarReais((n.valor as string | number | null | undefined) ?? c.valor ?? null);
  const dia = diaMes(String(n.data ?? "")) ?? null;
  const oQue = n.tipo === "peca"
    ? (typeof n.produto === "string" && n.produto.trim() ? n.produto.trim().slice(0, 60) : "a peça")
    : (typeof n.categoria === "string" && n.categoria ? n.categoria
      : typeof n.descricao === "string" && n.descricao.trim() ? n.descricao.trim().replace(/["\n\r]+/g, " ").slice(0, 60) : "a despesa");
  return [oQue, valor, dia ? `de ${dia}` : null].filter(Boolean).join(" ");
}

function destinoNoResumo(c: CmpResumo, comCategoria = true): string {
  const cat = comCategoria && c.categoria ? ` · ${c.categoria}` : "";
  switch (c.destino) {
    case "os": {
      if (!c.os) return `OS${cat}`;
      const base = osComNome(c.os);
      if (c.quem_pagou === "cliente") return `${base} · o cliente pagou direto`;
      // ajustes do dono: nada do comprovante aparece para o cliente nem muda o total da OS. O que o
      // dono escolheu (peça ou despesa) vale antes do lançamento que o banco achou na OS (a mesma
      // ordem do plano: o achado só vale com tipo_na_os nulo).
      if (c.tipo_na_os === "peca") return `${base} · peça/material (só comprova; lance a peça na OS se ainda não lançou)`;
      if (c.tipo_na_os === "despesa") return `${base} · despesa da OS (custo interno: não aparece para o cliente)${cat}`;
      const n = c.na_os;
      if (n && typeof n.ambiguo === "number") return `${base} · só comprova (há ${n.ambiguo} lançamentos iguais na OS)`;
      if (n && n.tipo) return `${base} · já lançado na OS: ${jaLancadoNaOs(n, c)} (só comprova)`;
      return `${base}${cat}`;
    }
    case "estoque": return `estoque${cat}`;
    case "insumo": return `insumo${cat}`;
    case "empresa": return `empresa (sem OS)${cat}`;
    case "pessoal":
      // ajustes do dono: PESSOAL que saiu da empresa é gasto pessoal do sócio (desconta do pró-labore)
      return c.quem_pagou === "empresa"
        ? "PESSOAL, pago pela empresa (gasto pessoal do sócio: desconta do pró-labore do mês)"
        : "pessoal";
    default: return "a definir";
  }
}

function pagoNoResumo(c: CmpResumo): string | null {
  // PESSOAL só mostra o pagamento quando saiu da empresa (a forma decide a linha do extrato)
  if ((c.destino === "pessoal" && c.quem_pagou !== "empresa") || c.mesma_compra) return null;
  const forma = c.forma ? FORMA_TEXTO[c.forma] ?? c.forma : null;
  let quem: string | null;
  switch (c.quem_pagou) {
    case "socio": quem = "do seu bolso (fica como reembolso para você)"; break;
    case "tecnico": quem = c.pagador_nome ? `pelo técnico ${c.pagador_nome}` : "por um técnico"; break;
    case "cliente": quem = "pelo cliente, direto"; break;
    default:
      if (!forma) return null; // documento NF-e: a conta é a da nota
      quem = c.forma === "dinheiro"
        ? "pela empresa, do Caixa (se não foi a empresa: *corrigir quem*)"
        : "pela empresa (se não foi a empresa: *corrigir quem*)";
  }
  return [forma, quem].filter(Boolean).join(", ");
}

function numeroDaOs(ef: Efeito, c: CmpResumo): string {
  return String(ef.os_numero ?? c.os?.numero ?? "OS");
}

function reaisDoEfeito(ef: Efeito, c: CmpResumo): string {
  return formatarReais((ef.valor as string | number | null | undefined) ?? c.valor ?? null) ?? "o valor";
}

/** "'Pix Eliane' · Alimentação de campo" — de QUAL registro é o "usar o que já existe". */
function qualRegistro(ef: Efeito): string {
  const desc = typeof ef.descricao === "string" && ef.descricao.trim() ? `"${ef.descricao.trim().replace(/["\n\r]+/g, " ").slice(0, 60)}"` : null;
  const cat = typeof ef.categoria === "string" && ef.categoria ? ef.categoria : null;
  return [desc, cat].filter(Boolean).join(" · ");
}

/** "a peça (Filtro de óleo, R$ 62,00)" do efeito anexar_peca. */
function pecaDoEfeito(ef: Efeito, c: CmpResumo): string {
  const produto = typeof ef.produto === "string" && ef.produto.trim() ? ef.produto.trim().replace(/["\n\r]+/g, " ").slice(0, 60) : null;
  return [produto, reaisDoEfeito(ef, c)].filter(Boolean).join(", ");
}

/** Uma frase por efeito do plano (o "Vou: …" do resumo). */
export function frasesDoPlano(plano: Plano | null | undefined, c: CmpResumo): string[] {
  const frases: string[] = [];
  for (const ef of plano?.efeitos ?? []) {
    const os = numeroDaOs(ef, c);
    switch (ef.tipo) {
      case "despesa_os": {
        // ajustes do dono: a despesa do comprovante é custo INTERNO (nunca faturável, nunca no documento do cliente)
        const oQue = ef.nota === true ? "o valor da nota" : "a despesa";
        let f = `lançar ${oQue} na ${os} como custo interno (não muda o total nem aparece para o cliente; entra no Lucro por OS)`;
        if (ef.paid_by === "technician") f += `, paga pelo ${c.pagador_nome ?? "técnico"}`;
        frases.push(f);
        break;
      }
      case "anexar_despesa": {
        const qual = qualRegistro(ef);
        const dia = diaMes(String(ef.data ?? c.data ?? "")) ?? "mesmo dia";
        frases.push(`usar a despesa que já está na ${os} (${[qual || null, reaisDoEfeito(ef, c), dia].filter(Boolean).join(", ")}): só comprovo, não lanço de novo`);
        break;
      }
      case "anexar_peca":
        frases.push(`usar a peça que já está na ${os} (${pecaDoEfeito(ef, c)}): só comprovo, não lanço custo`);
        break;
      case "comprovar_na_os":
        frases.push(ef.motivo === "ambiguo"
          ? `guardar o comprovante como prova da ${os} sem escolher lançamento (não lanço custo)`
          : `guardar o comprovante como prova da peça da ${os} (não lanço custo)`);
        break;
      case "itens_da_nota": {
        const n = Number(ef.itens ?? 0);
        const nota = ef.nfe_numero ? `da nota ${ef.nfe_numero}` : "da nota";
        frases.push(n === 1 ? `ligar o item ${nota} à ${os}` : `ligar os ${n} itens ${nota} à ${os}`);
        break;
      }
      case "aguardar_nota":
        frases.push("esperar a nota (XML) entrar no sistema para ligar os itens");
        break;
      case "mesma_compra":
        frases.push(`só guardar o arquivo junto do ${String(ef.cmp ?? "outro comprovante")} (a mesma compra: nada na OS nem no financeiro)`);
        break;
      case "anotar":
        frases.push(`anotar ${formaComArtigo(String(ef.forma ?? c.forma ?? ""))} para quando o banco trouxer (se já trouxe, classifico a linha)`);
        break;
      case "anexar_anotacao": {
        const qual = qualRegistro(ef);
        frases.push(`usar a anotação que já espera o banco (${qual ? `${qual}, ` : ""}${reaisDoEfeito(ef, c)}, ${diaMes(String(ef.data ?? c.data ?? "")) ?? "mesmo dia"})`);
        break;
      }
      case "caixa":
        frases.push(`lançar a saída de ${reaisDoEfeito(ef, c)} no Caixa`);
        break;
      case "reembolso_socio":
        frases.push(`lançar ${reaisDoEfeito(ef, c)} como reembolso a você${ef.socio_nome ? ` (${ef.socio_nome})` : ""}`);
        break;
      case "anexar_lancamento": {
        const qual = qualRegistro({ ...ef, categoria: null });
        const onde = ef.origem === "despesa_da_os" ? "a conta a pagar da despesa da OS"
          : ef.origem === "conta_em_aberto" ? "a conta a pagar que já está em aberto"
          : "o lançamento que já existe";
        frases.push(`usar ${onde} (${[ef.conta && ef.origem !== "despesa_da_os" && ef.origem !== "conta_em_aberto" ? String(ef.conta) : null, qual || null, reaisDoEfeito(ef, c), diaMes(String(ef.data ?? c.data ?? "")) ?? "mesmo dia"].filter(Boolean).join(", ")}) — não lanço de novo`);
        break;
      }
      case "aguardar_fatura":
        // F3: a compra no crédito da empresa espera a linha do cartão (e pergunta); crédito na loja/outro segue a F2
        frases.push(c.forma === "credito"
          ? "nada no financeiro agora: quando a compra aparecer no cartão, pergunto se é esta"
          : "nada no financeiro agora: a compra no crédito entra pela fatura");
        break;
      case "ligar_linha":
        frases.push(fraseDoLigarNoPlano(ef, c));
        break;
      case "aguardar_banco":
        frases.push(fraseDoAguardarBanco(ef, c, true));
        break;
      case "reembolso_tecnico":
        frases.push(`lançar ${reaisDoEfeito(ef, c)} nas Diárias do ${String(ef.favorecido_nome ?? c.pagador_nome ?? "técnico")} como reembolso de despesa paga pelo técnico (entra no próximo acerto dele)`);
        break;
      case "nada":
        if (ef.motivo === "pessoal") frases.push("só guardar o arquivo em PESSOAL (nada no financeiro)");
        else if (ef.motivo === "cliente_pagou") frases.push("nada no financeiro: o cliente pagou direto");
        else if (ef.motivo === "tecnico_f2b") {
          frases.push(`anotar que o ${c.pagador_nome ?? "técnico"} pagou; o reembolso dele ainda não entra nas Diárias: fica a pendência "acerto do técnico" para você acertar com ele`);
        } else if (ef.motivo === "ja_reembolsado") {
          frases.push(`nada no financeiro: a despesa da OS já foi reembolsada ao ${String(ef.pagador_nome ?? c.pagador_nome ?? "técnico")}`);
        } else frases.push("nada no financeiro: a conta vem da nota fiscal");
        break;
      case "pendencia":
        // a do técnico já foi dita na frase dele
        if (ef.qual === "acerto_tecnico" && (plano?.efeitos ?? []).some((x) => x.tipo === "nada" && x.motivo === "tecnico_f2b")) break;
        frases.push(`deixar a pendência "${PENDENCIA_TEXTO[String(ef.qual)] ?? String(ef.qual)}"`);
        break;
    }
  }
  return frases;
}

/** O extra de almoço do dia (`extra_do_dia` do efeito reembolso_tecnico) e de quem é o reembolso. */
function almocoNoExtra(efeitos: Efeito[] | null | undefined, c: CmpResumo): { nome: string; valor: string; dia: string | null } {
  const ef = (Array.isArray(efeitos) ? efeitos : []).find((e) => e?.tipo === "reembolso_tecnico" && e.extra_do_dia && typeof e.extra_do_dia === "object");
  const extra = (ef?.extra_do_dia ?? {}) as { valor?: string | number | null; data?: string | null };
  return {
    nome: String(ef?.favorecido_nome ?? c.pagador_nome ?? "técnico"),
    valor: formatarReais(extra.valor ?? null) ?? "o extra",
    dia: diaMes(extra.data ?? c.data ?? null),
  };
}

/** A categoria do lançamento que já existia (o banco não troca: só preenche o vazio). */
function categoriaQueJaEstava(efeitos: Efeito[] | null | undefined): string | null {
  for (const e of Array.isArray(efeitos) ? efeitos : []) {
    const d = e?.diferente && typeof e.diferente === "object" ? e.diferente as { categoria?: unknown } : null;
    if (typeof d?.categoria === "string" && d.categoria.trim()) return d.categoria.trim().slice(0, 80);
  }
  return null;
}

/**
 * Os avisos que vão no resumo (um por linha). Os desconhecidos não aparecem. `efeitos` (do plano ou
 * da gravação) dão o extra de almoço e a categoria que já estava; `gravado` = depois do sim (o
 * aviso do almoço não pede mais o sim).
 */
export function textosDosAvisos(avisos: string[], c: CmpResumo, efeitos: Efeito[] | null = null, gravado = false): string[] {
  const os = c.os?.numero ?? "OS";
  const valor = formatarReais(c.valor ?? c.valor_lido ?? null) ?? "o valor";
  const almoco = almocoNoExtra(efeitos, c);
  const ambiguo = c.na_os && typeof c.na_os.ambiguo === "number" && c.na_os.ambiguo > 1 ? c.na_os.ambiguo : 2;
  const jaEstava = categoriaQueJaEstava(efeitos);
  const mapa: Record<string, string> = {
    duplicado_ambiguo: "Há mais de um lançamento igual já feito: não lanço; fica para classificar no Extrato.",
    sem_socio_cadastrado: "Não achei o seu cadastro de sócio para o reembolso: se foi a empresa, *corrigir quem*.",
    valor_incerto: `Li o valor sem certeza total: confira. Se não for ${valor}: *corrigir valor 52,00*.`,
    parecido_sem_identidade: "Já há um lançamento do mesmo valor e data, de outro fornecedor: confira se não é o mesmo gasto.",
    pecas_da_nota_ja_na_os: `Peças desta nota já estão na ${os}: o custo delas já conta; não lanço o valor da nota de novo.`,
    // ajustes do dono (11/10/2026)
    varios_na_os: `Há ${ambiguo} lançamentos de ${valor} na ${os} sem comprovante: não liguei a nenhum e não lancei custo.` +
      (gravado ? "" : ' Se for um gasto novo, responda *não* e escolha "Peça ou despesa".'),
    almoco_ja_no_extra: gravado
      ? `O ${almoco.nome} já tinha recebido ${almoco.valor} de almoço (extra da diária${almoco.dia ? ` de ${almoco.dia}` : ""}): confira se o reembolso não ficou em dobro.`
      : `O ${almoco.nome} já recebeu ${almoco.valor} de almoço (extra da diária${almoco.dia ? ` de ${almoco.dia}` : ""}). Reembolsar mesmo assim? *sim* grava; ` +
        'se o extra já pagou este almoço, responda *não* e escolha "Cancelar este comprovante" (nada é lançado).',
    categoria_existente_diferente: `O lançamento que já existe está como ${jaEstava ?? "outra categoria"}: não troco (só preencho o que está vazio). ` +
      "Se estiver errado, corrija no Extrato.",
    categoria_inativa: "A categoria não está mais ativa: escolha outra (*corrigir categoria*).",
    // F3 / F2b
    tecnico_fora_das_diarias: `O ${c.pagador_nome ?? "técnico"} não tem diária nas Diárias: o reembolso fica como pendência "acerto do técnico".`,
    linha_lancada_em_outro: "A linha do banco já foi lançada em outro registro: confira no Extrato.",
    conta_aberta_e_linha_lancada:
      "A conta a pagar deste gasto continua em aberto e a linha do banco já virou outro lançamento: é o mesmo gasto duas vezes. Cancele um dos dois no Financeiro; não ligo a linha.",
    despesa_ja_reembolsada: `A despesa da OS já foi reembolsada ao ${c.pagador_nome ?? "técnico"} (Financeiro › Reembolsos): não lanço outro reembolso nas Diárias.`,
    // revisão dos ajustes: do bolso do sócio, com a conta do fornecedor ainda a pagar
    conta_aberta_paga_pelo_socio: "A conta a pagar deste fornecedor (mesmo valor) continua em aberto: não lanço reembolso para você, seria o mesmo " +
      "gasto duas vezes. Se você pagou essa conta do seu bolso, cancele-a em Financeiro › Contas a pagar e lance o seu reembolso " +
      "(Lançar › Do bolso de um sócio); se a empresa ainda vai pagá-la, fica assim.",
  };
  return [...new Set(avisos)].map((a) => mapa[a]).filter((x): x is string => Boolean(x));
}

/** "em 10/10 às 12h57" — e, quando a leitura não trouxe a data, que é o dia do envio. */
function quandoNoResumo(c: CmpResumo): string {
  const quando = diaMes(c.data) ?? "data a confirmar";
  const hora = horaNoNome(c.hora ?? null);
  const envio = c.data_origem === "envio" ? ` (dia do envio; se foi outro dia: *corrigir data ${diaMes(c.data) ?? "10/10"}*)` : "";
  return `em ${quando}${hora ? ` às ${hora}` : ""}${envio}`;
}

/**
 * O resumo do passo confirmar: o que VAI acontecer, a pasta, os avisos e o pedido do sim.
 * O "sim" é sobre este plano (o banco confere o hash).
 */
export function textoDoResumo(p: PerguntaDoBanco): string {
  const c = p.cmp;
  const fornecedor = fornecedorDoCmp(c);
  const valor = formatarReais(c.valor ?? c.valor_lido ?? null) ?? "valor a confirmar";
  const confira = valorSemConferir(c) && formatarReais(c.valor ?? c.valor_lido ?? null) ? " (confira)" : "";
  const partes = [
    `${c.codigo} · confira antes de gravar:`,
    `• ${valor}${confira} ${quandoNoResumo(c)}${fornecedor ? ` · ${fornecedor}` : ""}`,
    `• Para: ${destinoNoResumo(c, !c.mesma_compra)}`,
  ];
  const pago = pagoNoResumo(c);
  if (pago) partes.push(`• Pago: ${pago}`);
  const frases = frasesDoPlano(p.plano, c);
  if (frases.length) partes.push(`Vou: ${frases.join("; ")}.`);
  const pasta = p.pasta ?? pastaNoTexto(c);
  if (pasta) partes.push(`Arquivo: ${pasta}.`);
  const avisos = [...(p.avisos ?? []), ...(p.plano?.avisos ?? [])];
  // "(confira)" já está na linha do valor: o aviso do valor incerto vira a saída (*corrigir valor*)
  partes.push(...textosDosAvisos(avisos, c, p.plano?.efeitos ?? null));
  partes.push("Responda *sim* para gravar ou *não* para corrigir.");
  return cortar(partes.join("\n"));
}

/**
 * A pasta como o dono a vê ("Brisa/1- DOC's/Compras", "COMPROVANTES/2026/2026-10"), quando o banco
 * não mandou. A pasta do barco só com a pasta registrada (a mesma regra do usaPastaDoBarco).
 */
export function pastaNoTexto(c: CmpResumo): string | null {
  const mes = /^\d{4}-\d{2}/.exec(String(c.data ?? ""))?.[0];
  if (c.situacao === "cancelado") return "COMPROVANTES/_CANCELADOS";
  if (!mes) return null;
  if (c.destino === "pessoal") return `COMPROVANTES/PESSOAL/${mes}`;
  if (c.destino === "os" && c.os?.barco && c.os.pasta_registrada) return `${c.os.barco}/1- DOC's/Compras`;
  return `COMPROVANTES/${mes.slice(0, 4)}/${mes}`;
}

/** Caminho de dentro do Dropbox como o dono o vê ("COMPROVANTES/…" em vez do caminho inteiro). */
export function caminhoLegivel(caminho: string | null | undefined): string | null {
  if (!caminho) return null;
  const base = PASTA_COMPROVANTES.slice(0, PASTA_COMPROVANTES.lastIndexOf("/") + 1);
  return caminho.startsWith(base) ? caminho.slice(base.length) : caminho.replace(/^\/+/, "");
}

// ---------------------------------------------------------------------------------------------
// Depois do sim
// ---------------------------------------------------------------------------------------------

const EFEITOS_DO_FINANCEIRO = new Set([
  "anotar", "anexar_anotacao", "anexar_lancamento", "caixa", "reembolso_socio", "aguardar_fatura", "nada", "mesma_compra",
  // F3 / F2b
  "ligar_linha", "aguardar_banco", "reembolso_tecnico",
]);

/**
 * "a OS e a categoria" do `corrigido` de um lançamento que já existia (ajustes do dono: o banco só
 * preenche o que estava vazio; nunca troca).
 */
function preenchidosNoLancamento(corrigido: unknown): string[] {
  if (!corrigido || typeof corrigido !== "object") return [];
  const chaves = Object.keys(corrigido as object);
  const campos: string[] = [];
  if (chaves.some((k) => /os|service_order/i.test(k))) campos.push("a OS");
  if (chaves.some((k) => /categ/i.test(k))) campos.push("a categoria");
  return campos;
}

/** O motivo da aprovação que falhou, para o dono: código conhecido em texto fixo; frase das nossas rotas até 120; o resto, "erro no sistema". */
export function motivoDaAprovacao(motivo: string | null | undefined): string {
  const m = String(motivo ?? "").replace(/\s+/g, " ").trim();
  const fixos: Record<string, string> = {
    autor_diferente: "a aprovação é só do dono do comprovante",
    sem_resposta: "o Extrato não respondeu",
    nao_aprovada: "a linha não foi aprovada",
    proposta_mudou: "a linha mudou na fila do Extrato",
    linha_lancada: "a linha já virou outro lançamento",
  };
  if (fixos[m]) return fixos[m];
  if (!m || /^[a-z_:0-9]{1,60}$/.test(m)) return "erro no sistema";
  const cru = /violat|constraint|relation|column|syntax|function|null value|duplicate key|permission denied|does not exist|invalid input|operator|\bsql\b|\berror\b/i
    .test(m);
  return cru ? "erro no sistema" : m.replace(/[.\s]+$/u, "").slice(0, 120);
}

/** A linha classificada pelo CMP: lançada pelo sim, ou o que falta (a próxima rodada do Extrato tenta de novo). */
function lancadaNoExtrato(c: CmpResumo, ef: Efeito | null, aprovacao: Aprovacao | null | undefined): { lancada: boolean; falha: string | null } {
  if (aprovacao && !aprovacao.ok) return { lancada: false, falha: motivoDaAprovacao(aprovacao.motivo) };
  if (aprovacao?.ok && !aprovacao.nada) return { lancada: true, falha: null };
  return { lancada: Boolean(ef?.aprovado && typeof ef.aprovado === "object"), falha: null };
}

/**
 * O que foi feito, no passado (gravação e cartão). `aprovacao`: o resultado da aprovação da linha
 * pelo sim (ajustes do dono), quando o edge acabou de tentar; sem ela, o `aprovado` do efeito.
 */
export function frasesDaGravacao(efeitos: Efeito[] | null | undefined, c: CmpResumo, aprovacao: Aprovacao | null = null): string[] {
  const frases: string[] = [];
  const lista = Array.isArray(efeitos) ? efeitos : [];
  const temF2b = lista.some((x) => x.tipo === "nada" && x.motivo === "tecnico_f2b");
  for (const ef of lista) {
    const os = numeroDaOs(ef, c);
    switch (ef.tipo) {
      case "despesa_os": {
        let f = `lancei a despesa na ${os} como custo interno (não muda o total nem aparece para o cliente; entra no Lucro por OS)`;
        if (ef.paid_by === "technician" || c.quem_pagou === "tecnico") f += `, paga pelo ${c.pagador_nome ?? "técnico"}`;
        frases.push(f);
        break;
      }
      case "anexar_despesa":
        frases.push(`usei a despesa que já estava na ${os}: só comprovei, não lancei de novo`);
        break;
      case "anexar_peca": {
        const produto = typeof ef.produto === "string" && ef.produto.trim() ? ` (${ef.produto.trim().replace(/["\n\r]+/g, " ").slice(0, 60)})` : "";
        frases.push(`usei a peça que já estava na ${os}${produto}: só comprovei, não lancei custo`);
        break;
      }
      case "comprovar_na_os":
        frases.push(ef.motivo === "ambiguo"
          ? `guardei o comprovante como prova da ${os} sem escolher lançamento (não lancei custo)`
          : `guardei o comprovante como prova da peça da ${os} (não lancei custo)`);
        break;
      case "itens_da_nota": {
        const n = Array.isArray(ef.itens) ? ef.itens.length : Number(ef.itens ?? 0);
        frases.push(n === 1 ? `liguei o item da nota à ${os}` : `liguei ${n} itens da nota à ${os}`);
        break;
      }
      case "aguardar_nota":
        frases.push("vou ligar os itens quando a nota (XML) entrar no sistema");
        break;
      case "mesma_compra":
        frases.push(`guardei só o arquivo, junto do ${String(ef.cmp ?? "outro comprovante")} (a mesma compra)`);
        break;
      case "anotar": {
        if (ef.resultado !== "aplicada") {
          frases.push(`anotei ${formaComArtigo(c.forma)} para quando o banco trouxer`);
          break;
        }
        // o banco já trouxe: a anotação classificou a linha; o sim aprova (ajustes do dono)
        const l = lancadaNoExtrato(c, null, aprovacao);
        frases.push(l.lancada
          ? `lancei a linha do banco no Extrato ${comoClassifica(c, false)}`
          : l.falha
          ? `classifiquei a linha do banco, mas não consegui aprovar agora (${l.falha}): tento de novo na próxima rodada do Extrato`
          : "classifiquei a linha do banco (lanço no Extrato na próxima rodada)");
        break;
      }
      case "anexar_anotacao":
        frases.push("usei a anotação que já esperava o banco");
        break;
      case "anexar_lancamento": {
        const campos = preenchidosNoLancamento(ef.corrigido);
        frases.push(campos.length
          ? `anexei ao lançamento que já existia e preenchi ${campos.join(" e ")}, que estava${campos.length > 1 ? "m" : ""} vazi${campos.length > 1 ? "as" : "a"}`
          : "anexei ao lançamento que já existia (não lancei de novo)");
        break;
      }
      case "caixa":
        frases.push(`lancei a saída de ${formatarReais(c.valor) ?? "o valor"} no Caixa`);
        break;
      case "reembolso_socio":
        frases.push(`lancei ${formatarReais(c.valor) ?? "o valor"} como reembolso a você`);
        break;
      case "aguardar_fatura":
        frases.push(c.forma === "credito"
          ? "nada no financeiro agora: quando a compra aparecer no cartão, pergunto se é esta"
          : "nada no financeiro agora: a compra no crédito entra pela fatura");
        break;
      case "ligar_linha":
        frases.push(fraseDoLigarNaGravacao(ef, c, aprovacao));
        break;
      case "aguardar_banco":
        frases.push(fraseDoAguardarBanco(ef, c, false));
        break;
      case "reembolso_tecnico":
        frases.push(`lancei ${formatarReais((ef.valor as string | number | null | undefined) ?? c.valor ?? null) ?? "o valor"} nas Diárias do ${String(ef.favorecido_nome ?? c.pagador_nome ?? "técnico")} como reembolso de despesa paga pelo técnico`);
        break;
      case "nada":
        if (ef.motivo === "pessoal") frases.push("só guardei o arquivo (nada no financeiro)");
        else if (ef.motivo === "cliente_pagou") frases.push("nada no financeiro: o cliente pagou direto");
        else if (ef.motivo === "tecnico_f2b") frases.push(`anotei que o ${c.pagador_nome ?? "técnico"} pagou; o reembolso dele ainda não entra nas Diárias (ficou a pendência "acerto do técnico")`);
        else if (ef.motivo === "anotacao_recusada") frases.push("não anotei no extrato (fica para classificar no Extrato)");
        else if (ef.motivo === "ja_reembolsado") {
          frases.push(`nada no financeiro: a despesa da OS já tinha sido reembolsada ao ${String(ef.pagador_nome ?? c.pagador_nome ?? "técnico")}`);
        } else frases.push("nada no financeiro: a conta vem da nota fiscal");
        break;
      case "pendencia":
        if (ef.qual === "acerto_tecnico" && temF2b) break;
        frases.push(`deixei a pendência "${PENDENCIA_TEXTO[String(ef.qual)] ?? String(ef.qual)}"`);
        break;
    }
  }
  if (!lista.some((e) => EFEITOS_DO_FINANCEIRO.has(e.tipo))) {
    if (c.destino === "pessoal") frases.push("só guardei o arquivo (nada no financeiro)");
    else if (c.quem_pagou === "cliente") frases.push("nada no financeiro: o cliente pagou direto");
    else if (c.quem_pagou === "tecnico") frases.push(`anotei que o ${c.pagador_nome ?? "técnico"} pagou; o reembolso dele ainda não entra nas Diárias (ficou a pendência "acerto do técnico")`);
    else if (c.forma === "credito" || c.forma === "credito_loja" || c.forma === "outro") frases.push("nada no financeiro agora: a compra no crédito entra pela fatura");
    else if (!frases.length) frases.push("nada no financeiro");
  }
  return frases;
}

/**
 * "CMP-00124 gravado: <o que foi feito>. Arquivo: <pasta>." + as mensagens da rota + a próxima
 * pergunta ("Próximo: …") ou "Fila vazia: …". F3: sem próxima e com a pergunta do extrato aberta
 * logo depois da gravação (azul), a cauda é "No extrato: <a pergunta>" no lugar de "Fila vazia".
 * `aprovacao`: o sim já lançou a linha no Extrato (ajustes do dono), ou o porquê de não.
 */
export function textoDaGravacao(p: {
  cmp: CmpResumo;
  gravacao: Gravacao | null;
  proxima: PerguntaDoBanco | null;
  banco?: PerguntaDoExtrato | null;
  aprovacao?: Aprovacao | null;
}): string {
  const c = p.cmp;
  const frases = frasesDaGravacao(p.gravacao?.efeitos, c, p.aprovacao ?? null);
  const pasta = p.gravacao?.pasta ?? pastaNoTexto(c);
  let texto = `${c.codigo} gravado: ${frases.join("; ")}.${pasta ? ` Arquivo: ${pasta}.` : ""}`;
  const mensagens = (p.gravacao?.mensagens ?? []).filter((m) => typeof m === "string" && m.trim());
  if (mensagens.length) texto += `\n${mensagens.map((m) => m.trim().slice(0, 300)).join("\n")}`;
  const avisos = textosDosAvisos((p.gravacao?.avisos ?? []).filter((a) => a !== "valor_incerto"), c, p.gravacao?.efeitos ?? null, true);
  if (avisos.length) texto += `\n${avisos.join("\n")}`;
  if (p.proxima) texto += `\n\nPróximo: ${textoDaPergunta(p.proxima)}`;
  else if (p.banco) texto += `\n\nNo extrato: ${textoDaPerguntaDoExtrato(p.banco)}`;
  else texto += "\n\nFila vazia: não há mais comprovantes para conferir.";
  return cortar(texto);
}

/**
 * Os erros que a rota devolve, em texto do dono (com a saída). O resto vira "deu um erro no sistema
 * (código X)" — a mensagem crua do Postgres ("violates check constraint…") nunca vai ao dono.
 */
export function motivoDoNaoGravado(motivo: string | null | undefined, numero: number | null): { texto: string; conhecido: boolean } {
  const m = String(motivo ?? "");
  const cancelar = `*cancelar cmp ${numero ?? "N"} motivo*`;
  const mes = /m[eê]s (\d{2})\/(\d{4}) est[aá] fechado/i.exec(m) ?? /est[aá] fechado/i.exec(m);
  if (mes) {
    const qual = mes[1] ? ` (${mes[1]}/${mes[2]})` : "";
    return { texto: `o mês${qual} está fechado no financeiro: reabra o mês ou ${cancelar}`, conhecido: true };
  }
  if (/Categoria .* n[aã]o existe/i.test(m)) return { texto: "a categoria não existe mais no plano de contas: *corrigir categoria*", conhecido: true };
  if (/A OS .*(cancelada|rascunho)|OS da despesa n[aã]o existe/i.test(m)) return { texto: "a OS não está mais aberta para receber a despesa: *corrigir os N*", conhecido: true };
  if (/Falta responder/i.test(m)) return { texto: "ainda falta responder uma pergunta dele", conhecido: true };
  if (/Caixa/i.test(m) && /saldo/i.test(m)) return { texto: "o Caixa não tem saldo para essa saída", conhecido: true };
  return { texto: "deu um erro no sistema", conhecido: false };
}

export function textoNaoGravado(codigo: string, motivo: string | null | undefined, numero: number | null = null, codigoDoErro: string | null = null): string {
  const r = motivoDoNaoGravado(motivo, numero);
  const m = r.conhecido ? r.texto : `${r.texto}${codigoDoErro ? ` (código ${codigoDoErro})` : ""}`;
  // "tentar de novo" só quando o erro pode ser passageiro (o mês fechado repetiria o mesmo erro)
  const saida = r.conhecido ? "Responda *não* para corrigir." : "Responda *sim* para tentar de novo ou *não* para corrigir.";
  return `Não gravei o ${codigo}: ${m}. Nada mudou. ${saida}`;
}

export function textoOkNaoAprova(codigo: string, comTextoAMais = false): string {
  return comTextoAMais
    ? `Para gravar o ${codigo}, responda só *sim*. Para mudar algo: *corrigir os 12*, *corrigir valor 62,50*… (ou *não* para o menu).`
    : `Para gravar o ${codigo}, responda *sim* (ou *não* para corrigir).`;
}

/** "Não achei a OS-00098. " / "essa opção" / "essa categoria" (+ a pergunta de novo, por quem chama). */
export function textoInvalida(i: Interpretacao | null, passo: string | null | undefined, motivo: string | null | undefined): string {
  const os = i?.tipo === "os" ? `OS-${String(i.numero).padStart(5, "0")}` : null;
  if (motivo === "os_cancelada") return `A ${os ?? "OS"} está cancelada. `;
  if (motivo === "os_rascunho") return `A ${os ?? "OS"} ainda é rascunho. `;
  if (motivo === "sem_socio_cadastrado") return "Não achei o seu cadastro de sócio. ";
  if (motivo === "data_futura") return "A data não pode ser futura. ";
  if (motivo === "qual_o_valor") return "";
  if (motivo === "resposta_anterior_a_pergunta") return "Essa resposta chegou antes desta pergunta; responda de novo a ela:";
  if (motivo === "nome_nao_achado" && i?.tipo === "nome") {
    const t = i.texto.replace(/["\n\r]+/g, " ").slice(0, 40);
    return passo === "qual_tecnico"
      ? `Não achei o técnico "${t}". Responda o número da lista. `
      : `Não achei barco nem OS aberta com "${t}". Responda o número da lista ou *os N* (se a OS já foi fechada, *os N* também serve). Se era para o assistente, mande de novo depois de responder (ou *pular*). `;
  }
  if (i?.tipo === "ok" || i?.tipo === "sim" || i?.tipo === "nao") return "Para seguir, responda à pergunta. ";
  if (os) return `Não achei a ${os}. `;
  if (passo === "categoria") return "Não achei essa categoria. ";
  return "Não achei essa opção. ";
}

export function textoPulado(codigo: string): string {
  return `${codigo} fica para depois (foi para o fim da fila).`;
}

export function textoSair(fila: number, numero: number | null = null): string {
  const n = Math.max(0, Math.trunc(Number(fila) || 0));
  const falta = n === 0 ? "" : n === 1 ? " Falta 1 comprovante." : ` Faltam ${n} comprovantes.`;
  const continuar = numero ? `*cmp ${numero}*` : "*cmp N*";
  return n === 0
    ? "Ok, parei."
    : `Ok, parei.${falta} Volto a perguntar em até 12 h; para continuar antes: ${continuar} (ou *pendentes* para ver a lista).`;
}

export function textoJaGravado(codigo: string, numero: number | null): string {
  return `O ${codigo} já foi gravado. Para mudar: *cancelar cmp ${numero ?? "N"} motivo* e mande o arquivo de novo.`;
}

export function textoOcupado(codigo: string, titulo: string | null | undefined): string {
  const t = String(titulo ?? "o pedido do assistente").replace(/["\n\r]+/g, " ").replace(/\s+/g, " ").trim().slice(0, 80);
  return `Anotei para o ${codigo}. Continuo depois que você responder: "${t}".`;
}

/** O comprovante novo que não foi perguntado agora (o dono está ocupado com outro pedido ou conversando). */
export function textoNaFila(codigos: string[], numero: number | null, ocupadoCom: string | null | undefined): string {
  const t = ocupadoCom ? String(ocupadoCom).replace(/["\n\r]+/g, " ").replace(/\s+/g, " ").trim().slice(0, 80) : null;
  const depois = t ? `pergunto depois do pedido "${t}"` : "pergunto daqui a pouco";
  const quais = codigos.length > 1
    ? `${codigos.length} comprovantes (${faixaDeCodigos(codigos)}); estão na fila`
    : `o ${codigos[0] ?? "comprovante"}; está na fila`;
  return `Recebi ${quais}: ${depois}. Para conferir agora: *cmp ${numero ?? "N"}*.`;
}

export function textoFeito(codigo: string, resolvidas: string[]): string {
  const nomes = resolvidas.map((q) => `"${PENDENCIA_TEXTO[q] ?? q}"`);
  if (!nomes.length) return `${codigo} não tinha pendência.`;
  if (nomes.length === 1) return `${codigo}: pendência ${nomes[0]} marcada como resolvida.`;
  return `${codigo}: pendências ${nomes.join(", ")} marcadas como resolvidas.`;
}

export function textoLote(entraram: Array<{ codigo?: string | null }>, restam: number): string | null {
  const codigos = entraram.map((e) => e.codigo).filter((c): c is string => Boolean(c));
  if (!entraram.length) return "Não há comprovantes antigos para conferir.";
  const faixa = codigos.length ? ` (${faixaDeCodigos(codigos)})` : "";
  const fora = restam === 1 ? " Ainda há 1 antigo: mande *lote antigo* de novo depois."
    : restam > 1 ? ` Ainda há ${restam} antigos: mande *lote antigo* de novo depois.` : "";
  return entraram.length === 1
    ? `Coloquei 1 comprovante antigo na fila${faixa}.${fora}`
    : `Coloquei ${entraram.length} comprovantes antigos na fila${faixa}.${fora}`;
}

export function textoSemMotivo(numero: number): string {
  return `Para cancelar, diga o motivo: *cancelar cmp ${numero} comprei em dobro*.`;
}

export function textoCorrigirIncompleto(campo: "valor" | "data" | "forma" | "os"): string {
  const exemplo = { valor: "corrigir valor 62,50", data: "corrigir data 10/10", forma: "corrigir forma pix", os: "corrigir os 112" }[campo];
  return `Para corrigir, mande junto o novo dado: *${exemplo}*.`;
}

/** "corrigir" sozinho fora do resumo: como mandar. */
export const TEXTO_CORRIGIR_COMO =
  "Para corrigir, mande junto o que muda: *corrigir valor 62,50*, *corrigir data 10/10*, *corrigir os 112*, *corrigir forma pix*, " +
  "*corrigir para estoque*, *corrigir quem* ou *corrigir categoria*.";

export function textoNaoExiste(numero: number): string {
  return `Não achei o CMP-${String(numero).padStart(5, "0")}.`;
}

/** Logo depois de gravar um e abrir o próximo, "corrigir valor 70" sem dizer qual: qual dos dois? */
export function textoQualCmp(gravado: string, aberto: string, comando: string): string {
  const n = (c: string) => /(\d+)$/.exec(c)?.[1] ? String(Number(/(\d+)$/.exec(c)![1])) : "N";
  return `Corrigir o ${gravado} (já gravado) ou o ${aberto}? Para o ${aberto}: *corrigir cmp ${n(aberto)} ${comando}*. ` +
    `O ${gravado} já foi gravado: para mudar, *cancelar cmp ${n(gravado)} motivo* e mande o arquivo de novo.`;
}

const CAMPO_NO_TEXTO: Record<string, string> = { valor: "valor", data: "data", forma: "forma de pagamento", os: "OS", categoria: "categoria" };

/** "CMP-00125: valor corrigido para R$ 70,00." — antes da pergunta seguinte (o dono vê QUAL mudou). */
export function textoCorrigido(codigo: string, corrigido: { campo?: string; valor?: unknown } | null | undefined): string | null {
  if (!corrigido?.campo) return null;
  const v = corrigido.valor;
  let valor = String(v ?? "");
  if (corrigido.campo === "valor") valor = formatarReais(v as string) ?? valor;
  else if (corrigido.campo === "data") valor = diaMes(String(v ?? "")) ?? valor;
  else if (corrigido.campo === "forma") valor = FORMA_TEXTO[valor] ?? valor;
  return `${codigo}: ${CAMPO_NO_TEXTO[corrigido.campo] ?? corrigido.campo} corrigid${corrigido.campo === "data" || corrigido.campo === "forma" || corrigido.campo === "os" || corrigido.campo === "categoria" ? "a" : "o"} para ${valor}.`;
}

/** O texto solto depois da foto virou dica do CMP que está chegando. */
export function textoDica(codigo: string | null): string {
  return codigo ? `Anotei para o ${codigo}.` : "Anotei para o comprovante que está chegando.";
}

/** Mensagem curta que não é resposta, com a pergunta do CMP aberta: "Não entendi para o CMP-00124…". */
export function textoNaoEntendi(codigo: string): string {
  return `Não entendi para o ${codigo}. Se era para o assistente, mande de novo depois de responder (ou *pular*).`;
}

/** A pergunta do CMP foi "interrompida" pela conversa com o assistente: confirma antes de aplicar o "sim"/número. */
export function textoRetomadaInterrompida(codigo: string): string {
  return `Essa resposta é para o ${codigo}? Como você falou com o assistente depois da pergunta, confirmo antes: se é para ` +
    `o ${codigo}, responda de novo a esta pergunta. Se era para o assistente, mande de novo citando a mensagem dele.`;
}

export const TEXTO_SEM_CMP = "Não há comprovante em conferência para corrigir. Para abrir um: *cmp N* (ou *pendentes*).";

/** O webhook manda quando o responder recusou ANTES de processar (nada foi gravado). */
export const TEXTO_FALHA = "Não consegui registrar essa resposta agora. Mande de novo daqui a pouco.";

// ---------------------------------------------------------------------------------------------
// Pendentes, cartão e cancelamento
// ---------------------------------------------------------------------------------------------

export type ItemPendente = {
  codigo: string;
  numero?: number | null;
  data?: string | null;
  valor?: string | null;
  fornecedor?: string | null;
  situacao: string;
  falta?: string | null;
  pendencias?: string[];
  /**
   * F3: "perguntar" = falta ligar ao extrato (a pergunta do extrato espera a vez ou a resposta).
   * Regra E: "banco_quem" = falta dizer quem pagou (não apareceu em conta da empresa em 5 dias).
   */
  banco?: string | null;
  /** F3: a NF-e que o CMP espera chegou por e-mail e ainda não foi importada. */
  nota_no_email?: boolean;
};

const SITUACAO_NA_LISTA: Record<string, string> = {
  aguardando_xml: "esperando a nota (XML)",
  aguardando_banco: "esperando o banco", conciliado: "ligado ao extrato", abandonado: "sem linha no extrato",
};

/** F3: gravado de fato (o financeiro foi feito), mesmo esperando ou ligado à linha do extrato. */
const GRAVADOS_DE_FATO = new Set(["gravado", "aguardando_banco", "conciliado", "abandonado"]);

function linhaPendente(i: ItemPendente, n: number): string {
  const cab = [i.codigo, diaMes(i.data ?? null), formatarReais(i.valor ?? null), i.fornecedor || null].filter(Boolean).join(" · ");
  let falta: string;
  if (GRAVADOS_DE_FATO.has(i.situacao)) {
    const faltas = (i.pendencias ?? []).map((q) => PENDENCIA_TEXTO[q] ?? q);
    if (i.banco === "perguntar") faltas.push("ligar ao extrato");
    if (ehEstadoDoQuemPagou(i.banco)) faltas.push("quem pagou (não apareceu no extrato)");
    const rotulo = i.situacao === "gravado" ? "gravado" : SITUACAO_NA_LISTA[i.situacao];
    falta = `${rotulo}; falta: ${faltas.join(", ") || "nada"}`;
  } else if (i.situacao === "aguardando_xml" && i.nota_no_email) {
    falta = "a nota chegou por e-mail: importe em Entrada de Mercadoria";
  } else if (SITUACAO_NA_LISTA[i.situacao]) {
    falta = SITUACAO_NA_LISTA[i.situacao];
  } else if (i.situacao === "aguardando_sim" || i.falta === "confirmar") {
    falta = "falta: seu sim";
  } else {
    falta = `falta: ${i.falta ? passoLegivel(i.falta).replace(/^(o|a) /, "") : "conferir"}`;
  }
  return `${n}. ${cab} — ${falta}`;
}

/** A lista do "pendentes" (até 10 linhas + "e mais N"); null quando não há nada (não manda). */
export function textoDosPendentes(r: { abertos?: ItemPendente[]; total?: number; antigos?: number }): string | null {
  const abertos = Array.isArray(r.abertos) ? r.abertos : [];
  const total = Math.max(abertos.length, Number(r.total ?? 0) || 0);
  const antigos = Math.max(0, Number(r.antigos ?? 0) || 0);
  if (!total && !antigos) return null;
  const antigosTexto = antigos > 0 ? `Antigos ainda não conferidos: ${antigos} (*lote antigo*).` : "";
  if (!total) return `Nenhum comprovante em aberto. ${antigosTexto}`;
  const partes = [`Comprovantes em aberto (${total}):`, ...abertos.slice(0, 10).map((i, k) => linhaPendente(i, k + 1))];
  if (total > 10) partes.push(`e mais ${total - 10}`);
  const primeiro = abertos[0] ? numeroDoCmp({ numero: abertos[0].numero ?? null, codigo: abertos[0].codigo }) : null;
  partes.push([primeiro ? `Para continuar um: *cmp ${primeiro}*.` : "", antigosTexto].filter(Boolean).join(" "));
  return cortar(partes.filter(Boolean).join("\n"));
}

const SITUACAO_NO_CARTAO: Record<string, string> = {
  gravado: "gravado", aguardando_xml: "esperando a nota", cancelado: "cancelado",
  aguardando_vez: "na fila", perguntando: "em conferência", aguardando_sim: "esperando o seu sim",
  aguardando_banco: "esperando o banco", conciliado: "ligado ao extrato", abandonado: "sem linha no extrato",
};

/** O cartão do "cmp N" de um CMP já gravado (ou cancelado). F3: + "No extrato: <onde está>." */
export function textoDoCartao(c: CmpResumo, efeitos: Efeito[] | null | undefined): string {
  const situacao = SITUACAO_NO_CARTAO[c.situacao] ?? "guardado";
  const resumo = [
    `${formatarReais(c.valor ?? c.valor_lido ?? null) ?? "sem valor"} em ${diaMes(c.data) ?? "data a confirmar"}`,
    fornecedorDoCmp(c),
    c.destino ? destinoNoResumo(c) : null,
  ].filter(Boolean).join(" · ");
  if (c.situacao === "cancelado") return cortar(`${c.codigo} (${situacao}): ${resumo}.`);
  const feito = frasesDaGravacao(efeitos, c);
  const numero = numeroDoCmp(c);
  const extrato = bancoNoCartao(c);
  return cortar(`${c.codigo} (${situacao}): ${resumo}. Feito: ${feito.join("; ")}.${extrato ? ` No extrato: ${extrato}.` : ""} Para cancelar: *cancelar cmp ${numero ?? "N"} motivo*.`);
}

const DESFEITO_TEXTO: Record<string, string> = {
  despesa_os: "a despesa interna da OS",
  anexar_despesa: "o vínculo com a despesa da OS",
  anexar_peca: "o vínculo com a peça da OS",
  comprovar_na_os: "o comprovante como prova da OS",
  itens_da_nota: "o vínculo dos itens da nota com a OS",
  anotar: "a anotação do extrato",
  anexar_anotacao: "o vínculo com a anotação",
  anexar_lancamento: "o vínculo com o lançamento",
  caixa: "a saída do Caixa (estornada)",
  reembolso_socio: "o reembolso",
  pendencia: "a pendência",
  // F3 / F2b
  ligar_linha: "a ligação com a linha do banco (a linha volta para a fila do Extrato)",
  reembolso_tecnico: "o reembolso nas Diárias",
};

/** ligar_linha cuja linha o sim aprovou (ajustes do dono): o cancelar desfaz a aprovação também. */
const DESFEITO_LIGAR_APROVADO = "a aprovação e a ligação com a linha do banco (a linha volta para a fila do Extrato)";

const BLOQUEIO_TEXTO: Record<string, string> = {
  anotacao_aplicada: "a linha do banco já recebeu a classificação; corrija pelo Extrato",
  mes_fechado: "o mês está fechado no financeiro; reabra o mês e cancele de novo",
  reembolso_pago: "o reembolso já foi pago; desfaça o pagamento e cancele de novo",
};

/**
 * F3: os bloqueios com dia ou número no texto ("a linha do banco de 08/10 já virou lançamento…",
 * "reabra o acerto nº 0007…"): o banco monta o texto (`como_destravar`, de um modelo fixo, sem dado do
 * documento); sem ele, o texto sem o dia/número.
 */
const BLOQUEIO_DA_F3: Record<string, string> = {
  linha_lancada: "a linha do banco já virou lançamento: desfaça pelo Extrato e cancele de novo",
  linha_casada: "a linha do banco já deu baixa na conta a pagar: desfaça pelo Extrato e cancele de novo",
  reembolso_acertado: "o reembolso já está num acerto fechado das Diárias: reabra o acerto em Financeiro › Diárias e cancele de novo",
  // revisão dos ajustes: o reembolso já foi pago ao técnico num pagamento dividido (Pix, Caixa ou bolso do sócio)
  reembolso_dividido: "o reembolso já foi pago ao técnico num pagamento dividido: desfaça a divisão em Financeiro › Diárias e cancele de novo",
};

function textoDoBloqueioDaF3(b: { motivo?: string; como_destravar?: string }): string | null {
  const padrao = BLOQUEIO_DA_F3[String(b.motivo ?? "")];
  if (!padrao) return null;
  const doBanco = typeof b.como_destravar === "string" ? b.como_destravar.replace(/[\r\n]+/g, " ").trim().slice(0, 200) : "";
  return doBanco || padrao;
}

export type Cancelamento = {
  ok?: boolean;
  codigo?: string;
  /** `aprovado` no ligar_linha: o sim tinha aprovado a linha (o cancelar desfez a aprovação). */
  desfeitos?: Array<string | { tipo?: string; aprovado?: unknown }>;
  avisos?: string[];
  /** Os CMPs guardados como "a mesma compra" deste (continuam: só arquivo). */
  mesma_compra?: string[];
  bloqueios?: Array<{ efeito?: string; motivo?: string; como_destravar?: string }>;
};

/** Os bloqueios do desfazer (cancelar e trocar quem pagou), em texto do dono. */
function textoDosBloqueios(bloqueios: Cancelamento["bloqueios"]): string[] {
  return (bloqueios ?? [])
    .map((b) => textoDoBloqueioDaF3(b) ?? BLOQUEIO_TEXTO[String(b.motivo)] ?? b.como_destravar ?? b.motivo)
    .filter((x): x is string => typeof x === "string" && x.trim() !== "")
    .map((x) => x.replace(/[\r\n]+/g, " ").trim().slice(0, 200));
}

/** "CMP-00124 cancelado (<motivo>). Desfeito: …" ou "Não cancelei o CMP-00124: … Nada mudou." */
export function textoDoCancelamento(codigo: string, motivo: string | null, r: Cancelamento | null): string {
  if (r?.ok) {
    const desfeitos = [...new Set((r.desfeitos ?? []).map((d) => {
      const tipo = typeof d === "string" ? d : String(d?.tipo ?? "");
      if (tipo === "ligar_linha" && typeof d === "object" && d?.aprovado) return DESFEITO_LIGAR_APROVADO;
      return DESFEITO_TEXTO[tipo] ?? null;
    }).filter((x): x is string => Boolean(x)))];
    const lista = desfeitos.length ? desfeitos.join(", ") : "nada (ainda não tinha sido gravado)";
    const m = String(motivo ?? "").replace(/[()\n\r]+/g, " ").replace(/\s+/g, " ").trim().slice(0, 120);
    const copias = (r.mesma_compra ?? []).filter(Boolean);
    const aviso = copias.length
      ? ` ${copias.length === 1 ? `O ${copias[0]} foi guardado` : `Os ${copias.join(", ")} foram guardados`} como a mesma compra: se também não vale, cancele.`
      : "";
    return cortar(`${codigo} cancelado${m ? ` (${m})` : ""}. Desfeito: ${lista}. Arquivo em COMPROVANTES/_CANCELADOS.${aviso}`);
  }
  const bloqueios = textoDosBloqueios(r?.bloqueios);
  return cortar(`Não cancelei o ${codigo}: ${bloqueios.join("; ") || "a gravação não pôde ser desfeita"}. Nada mudou.`);
}

// ---------------------------------------------------------------------------------------------
// O par do histórico do assistente
// ---------------------------------------------------------------------------------------------

export const MARCA_DO_FLUXO = "🤖 Fluxo de comprovantes (respostas do dono pelo menu, não pelo assistente):";

/**
 * O par que entra em ai_operator_messages a cada gravação, cancelamento ou lista de pendentes: o
 * assistente fica sabendo do que o sistema fez. As perguntas e as respostas do menu NÃO entram.
 */
export function historicoDoFluxo(resumo: string, referencia: string | null, texto: string): { user: string; assistant: string } {
  return {
    user: `${MARCA_DO_FLUXO} ${resumo}.`,
    assistant: `${texto}${referencia ? `\n\nReferência: ${referencia}.` : ""}`,
  };
}

// =============================================================================================
// F3: a conversa da conciliação com o extrato (spec-f3.md, 4.3)
// =============================================================================================
//
// O banco decide o nível (verde/azul/cinza), as linhas e o que ligar faz com cada uma; aqui só se
// monta a mensagem. A linha do extrato vai ao dono (é dele); nunca ao log.

/** "R$ 50,98" do valor da linha (a saída pode vir com sinal). */
function reaisDaLinha(v: string | number | null | undefined): string | null {
  if (v === null || v === undefined || v === "") return null;
  const n = Math.abs(Number(v));
  return Number.isFinite(n) ? formatarReais(n) : null;
}

/** Texto do banco numa linha só, até 40 caracteres. */
function descricaoCurta(s: string | null | undefined): string | null {
  const t = String(s ?? "").replace(/[\r\n\t]+/g, " ").replace(/\s+/g, " ").trim();
  return t ? t.slice(0, 40).trim() : null;
}

/**
 * "C6 - Conta PJ HBR · 08/10 · DEBITO DE CARTAO · R$ 50,98" + " (cartão)" + " · parcela 1/3 da
 * compra de R$ 600,00" + " · ainda pendente no cartão" + " · já lançada (<categoria>)".
 */
export function linhaDoExtrato(l: LinhaDoBanco): string {
  let s = [descricaoCurta(l.conta), diaMes(l.data ?? null), descricaoCurta(l.descricao ?? l.nome), reaisDaLinha(l.valor)]
    .filter(Boolean)
    .join(" · ");
  if (l.cartao) s += " (cartão)";
  if (l.parcela) {
    const total = reaisDaLinha(l.total_da_compra);
    s += ` · parcela ${String(l.parcela).trim()}${total ? ` da compra de ${total}` : ""}`;
  }
  if (l.pendente) s += " · ainda pendente no cartão";
  if (l.lancamento) {
    const cat = descricaoCurta(l.lancamento.categoria);
    s += ` · já lançada${cat ? ` (${cat})` : ""}`;
  }
  return s;
}

/** "como Peças e materiais, OS-00112 Brisa" / "na OS-00112 Brisa" / "com os dados do comprovante". */
function comoClassifica(c: CmpResumo, comBarco = true): string {
  const os = c.destino === "os" && c.os ? (comBarco ? osComNome(c.os) : c.os.numero) : null;
  if (c.categoria) return `como ${c.categoria}${os ? `, ${os}` : ""}`;
  return os ? `na ${os}` : "com os dados do comprovante";
}

/**
 * Regra G (ajustes do dono): o lançamento que já existe só tem o VAZIO preenchido — "(preencho a
 * OS-00112 Brisa, que está vazia)" / "(nada a preencher)"; nunca "corrijo para". A OS só entra quando
 * o banco disse que ela está vazia (`os_numero` nulo); sem o lançamento, nada é prometido ("").
 */
function oQuePreenche(c: CmpResumo, l: LinhaDoBanco | null): string {
  const lanc = l?.lancamento;
  if (!lanc || typeof lanc !== "object") return "";
  const campos: string[] = [];
  if (c.destino === "os" && c.os && "os_numero" in lanc && !lanc.os_numero) campos.push(`a ${osComNome(c.os)}`);
  if (c.categoria && !String(lanc.categoria ?? "").trim()) campos.push(`a categoria ${c.categoria}`);
  if (!campos.length) return " (nada a preencher)";
  return ` (preencho ${campos.join(" e ")}, que ${campos.length > 1 ? "estão vazias" : "está vazia"})`;
}

/** O que ligar faz com a linha, no presente (a pergunta do extrato): "lanço a linha no Extrato como …". */
export function acaoNoTexto(c: CmpResumo, l: LinhaDoBanco): string {
  switch (l.acao) {
    case "anexar":
      return `uso o lançamento que já existe dela${oQuePreenche(c, l)}`;
    case "casar": {
      const desc = descricaoCurta(l.conta_aberta?.descricao)?.replace(/"/g, "'") ?? null;
      const valor = reaisDaLinha(l.conta_aberta?.valor ?? null);
      return `dou baixa na conta a pagar${desc ? ` "${desc}"` : ""}${valor ? ` (${valor})` : ""} com ela`;
    }
    case "aguardar":
      return "lanço quando o cartão confirmar a compra (aprovada no seu sim)";
    case "conflito":
      return textoDoConflito(l);
    default:
      // ajustes do dono: o sim já aprova a linha no Extrato (ligar = classificar + aprovar)
      return `lanço a linha no Extrato ${comoClassifica(c)} (aprovada no seu sim)`;
  }
}

/** A linha já lançada em outro registro com a conta do CMP em aberto: "não ligo essa: a conta a pagar … — cancele um dos dois". */
function textoDoConflito(l: LinhaDoBanco): string {
  const desc = descricaoCurta(l.conta_aberta?.descricao)?.replace(/"/g, "'") ?? null;
  const valor = reaisDaLinha(l.conta_aberta?.valor ?? null);
  return `não ligo essa: a conta a pagar${desc ? ` "${desc}"` : ""}${valor ? ` (${valor})` : ""} continua em aberto e a linha já virou outro lançamento — o mesmo gasto duas vezes; cancele um dos dois no Financeiro`;
}

/** O efeito ligar_linha do plano (o "Vou:" do resumo, no verde): "ligar à linha do banco de 08/10 (…) e classificá-la como …". */
function fraseDoLigarNoPlano(ef: Efeito, c: CmpResumo): string {
  const l = (ef.linha && typeof ef.linha === "object" ? ef.linha : null) as LinhaDoBanco | null;
  const acao = String(ef.acao ?? l?.acao ?? "classificar");
  const onde = l?.cartao ? "à compra do cartão" : "à linha do banco";
  const dia = diaMes(l?.data ?? null);
  const detalhe = l ? [descricaoCurta(l.conta), descricaoCurta(l.descricao ?? l.nome), reaisDaLinha(l.valor)].filter(Boolean).join(", ") : "";
  let fim: string;
  switch (acao) {
    case "anexar":
      fim = `usar o lançamento que já existe dela${oQuePreenche(c, l)}`;
      break;
    case "casar":
      fim = "dar baixa na conta a pagar com ela";
      break;
    case "aguardar":
      fim = "lançá-la no Extrato quando o cartão confirmar a compra (aprovada no seu sim)";
      break;
    default:
      fim = `lançá-la no Extrato ${comoClassifica(c)} (aprovada no seu sim)`;
  }
  return `ligar ${onde}${dia ? ` de ${dia}` : ""}${detalhe ? ` (${detalhe})` : ""} e ${fim}`;
}

/**
 * O efeito ligar_linha gravado (gravação, varredura, sim do dono), no passado, pelo `como`. No
 * "classificou", o sim aprova a linha (ajustes do dono): lançada, falhou agora (tento de novo) ou a
 * proposta ainda não está na fila (lanço quando ela entrar).
 */
function fraseDoLigarNaGravacao(ef: Efeito, c: CmpResumo, aprovacao: Aprovacao | null = null): string {
  const l = (ef.linha && typeof ef.linha === "object" ? ef.linha : null) as LinhaDoBanco | null;
  const dia = diaMes(l?.data ?? c.banco?.linha?.data ?? null);
  const de = dia ? ` de ${dia}` : "";
  switch (String(ef.como ?? "")) {
    case "anexou": {
      const campos = preenchidosNoLancamento(ef.corrigido);
      return campos.length
        ? `liguei à linha do banco${de} e anexei ao lançamento dela (preenchi ${campos.join(" e ")}, que estava${campos.length > 1 ? "m" : ""} vazi${campos.length > 1 ? "as" : "a"})`
        : `liguei à linha do banco${de} e anexei ao lançamento dela`;
    }
    case "casou":
      return `liguei à linha do banco${de} e dei baixa na conta a pagar`;
    case "aguardando":
      return c.forma === "credito" || l?.cartao
        ? `liguei à compra do cartão${de} (lanço no Extrato quando ela for confirmada)`
        : `liguei à linha do banco${de} (lanço no Extrato quando ela entrar na fila)`;
    default: {
      // revisão dos ajustes: o dono desfez no Extrato a aprovação que o sim fez — a linha é dele (nunca aprovo de novo)
      if (ef.aprovado_desfeito && typeof ef.aprovado_desfeito === "object" && !ef.aprovado) {
        return `liguei à linha do banco${de}; a aprovação foi desfeita no Extrato e a linha ficou para você classificar lá`;
      }
      const a = lancadaNoExtrato(c, ef, aprovacao);
      if (a.lancada) return `liguei à linha do banco${de} e lancei no Extrato ${comoClassifica(c, false)}`;
      if (a.falha) {
        return `liguei à linha do banco${de} e a classifiquei, mas não consegui aprovar agora (${a.falha}): tento de novo na próxima rodada do Extrato`;
      }
      return `liguei à linha do banco${de} e a classifiquei ${comoClassifica(c, false)} (lanço no Extrato na próxima rodada)`;
    }
  }
}

/** aguardar_banco (débito, ou Pix/boleto sem linha forte): o que acontece quando a linha aparecer. */
function fraseDoAguardarBanco(ef: Efeito, c: CmpResumo, noPlano: boolean): string {
  // na gravação, verde = a linha estava lá, mas ligar foi recusado (a baixa da conta: mês fechado…)
  if (!noPlano && ef.nivel === "verde") return "não liguei agora à linha do extrato: pergunto de novo se é esta";
  if (ef.nivel === "azul") {
    return noPlano
      ? "nada no financeiro agora (já há linhas parecidas no extrato: logo depois de gravar pergunto qual é)"
      : "já há linhas parecidas no extrato: pergunto qual é";
  }
  const debito = ef.regra === "debito" || c.forma === "debito";
  const esteOuEsta = c.forma === "transferencia" ? "esta" : "este";
  const pergunta = debito || !noPlano ? `pergunto se é ${esteOuEsta}` : "pergunto qual linha é";
  const quando = `quando ${formaComArtigo(c.forma)} aparecer no extrato, ${pergunta}`;
  return noPlano ? `nada no financeiro agora: ${quando}` : quando;
}

/** A pergunta é a lista (azul, com "0 Nenhuma destas") ou o sim/não de uma linha só (verde)? */
export function ehPerguntaAzul(p: Pick<PerguntaDoExtrato, "opcoes" | "banco">): boolean {
  const opcoes = Array.isArray(p.opcoes) ? p.opcoes : [];
  return opcoes.length ? opcoes.some((o) => o.n === 0) : p.banco?.nivel === "azul";
}

/** As linhas da pergunta na ordem das opções (a do banco pelo id "tx:<uuid>"; sem a avaliação, o rótulo da opção). */
function linhasDaPergunta(p: PerguntaDoExtrato): Array<{ n: number; texto: string; linha: LinhaDoBanco | null }> {
  const lidas = p.banco?.linhas;
  const doBanco: LinhaDoBanco[] = Array.isArray(lidas) ? lidas : [];
  const opcoes = (Array.isArray(p.opcoes) ? p.opcoes : []).filter((o) => o.n > 0);
  if (!opcoes.length) return doBanco.map((l, i) => ({ n: l.n ?? i + 1, texto: linhaDoExtrato(l), linha: l }));
  return opcoes.map((o) => {
    const id = /^tx:(.+)$/.exec(String(o.valor ?? ""))?.[1] ?? null;
    const l = (id ? doBanco.find((x) => x.id === id) : undefined) ?? doBanco.find((x) => x.n === o.n) ?? null;
    return { n: o.n, texto: l ? linhaDoExtrato(l) : String(o.rotulo ?? "").trim(), linha: l };
  });
}

/**
 * A pergunta do extrato (cabeçalho da F2 sem "(1 de N)"). Verde: "Apareceu no extrato: <linha>. É
 * deste comprovante? Se for, ligo e <ação>." Azul: as linhas numeradas, "0 Nenhuma destas" e, com
 * mais de 3 candidatas, "Há mais N…".
 */
export function textoDaPerguntaDoExtrato(p: PerguntaDoExtrato, prefixo: string | null = null): string {
  const c = p.cmp;
  if (p.passo === "banco_quem") return textoDaPerguntaDoQuemPagou(p, prefixo);
  const linhas = linhasDaPergunta(p);
  const partes = [cabecalho({ cmp: c })];
  if (ehPerguntaAzul(p)) {
    const zero = (p.opcoes ?? []).find((o) => o.n === 0)?.rotulo?.trim() || "Nenhuma destas";
    partes.push("Apareceram no extrato linhas que podem ser deste comprovante:");
    partes.push(...linhas.map((l) => `${l.n} ${l.texto}`));
    partes.push(`0 ${zero}`);
    // a linha em conflito (a conta do CMP em aberto + a linha já lançada) tem a frase própria, embaixo
    const conhecidas = linhas.map((l) => l.linha).filter((l): l is LinhaDoBanco => l !== null && l.acao !== "conflito");
    const acoes = new Set(conhecidas.map((l) => String(l.acao ?? "classificar")));
    const ligando = acoes.size === 1
      ? ` Ligando, ${acaoNoTexto(c, conhecidas[0])}.`
      : acoes.size > 1
      ? " Ligando, faço o que a linha escolhida pede (classificar, usar o lançamento que já existe ou dar baixa na conta a pagar)."
      : "";
    partes.push(`Responda o número da linha certa (ou 0).${ligando}`);
    for (const l of linhas) {
      if (l.linha?.acao === "conflito") partes.push(`A linha ${l.n}: ${textoDoConflito(l.linha)}.`);
    }
    const mais = Math.max(0, Math.trunc(Number(p.banco?.mais ?? 0)) || 0);
    if (mais > 0) {
      partes.push(`Há mais ${mais === 1 ? "1 linha igual" : `${mais} linhas iguais`} nesses dias: se não for nenhuma destas, responda 0 e classifique no Extrato.`);
    }
  } else {
    const l = linhas[0] ?? null;
    partes.push(`Apareceu no extrato: ${l?.texto || "uma linha do mesmo valor"}.`);
    partes.push(l?.linha ? `É deste comprovante? Se for, ligo e ${acaoNoTexto(c, l.linha)}.` : "É deste comprovante?");
    partes.push("Responda *sim* para ligar ou *não* se não for essa.");
  }
  const corpo = partes.join("\n");
  return cortar(prefixo ? `${prefixo}\n${corpo}` : corpo);
}

/**
 * Regra E (ajustes do dono): o CMP gravado não apareceu em nenhuma conta da empresa em 5 dias.
 * "Esta compra de 10/10 ainda não apareceu em nenhuma conta da empresa. Quem pagou?" + as opções do
 * banco (a empresa / eu / o técnico / gasto pessoal; no PESSOAL, só a empresa ou não).
 */
export function textoDaPerguntaDoQuemPagou(p: PerguntaDoExtrato, prefixo: string | null = null): string {
  const c = p.cmp;
  const dia = diaMes(c.data);
  const opcoes = (Array.isArray(p.opcoes) ? p.opcoes : []).filter((o) => o.n > 0);
  const corpo = [
    cabecalho({ cmp: c }),
    `Esta compra${dia ? ` de ${dia}` : ""} ainda não apareceu em nenhuma conta da empresa. Quem pagou?`,
    ...opcoes.map((o) => `${o.n} ${String(o.rotulo ?? "").replace(/[\r\n]+/g, " ").trim()}`),
  ].join("\n");
  return cortar(prefixo ? `${prefixo}\n${corpo}` : corpo);
}

/** A retomada do vigia: "Ainda falta ligar o CMP-00124 ao extrato." (regra E: "… saber quem pagou o CMP-00124."). */
export function prefixoDaPerguntaDoExtrato(p: Pick<PerguntaDoExtrato, "cmp" | "retomada"> & { passo?: string }, motivo: string): string | null {
  if (motivo !== "vigia" || !p.retomada) return null;
  return p.passo === "banco_quem" ? `Ainda falta saber quem pagou o ${p.cmp.codigo}.` : `Ainda falta ligar o ${p.cmp.codigo} ao extrato.`;
}

/** "à linha de 08/10 do C6 - Conta PJ HBR (R$ 50,98)" (do CmpResumo.banco.linha). */
function linhaLigada(c: CmpResumo): string {
  const l = c.banco?.linha;
  if (!l) return "à linha do extrato";
  const dia = diaMes(l.data ?? null);
  const conta = descricaoCurta(l.conta);
  const valor = reaisDaLinha(l.valor ?? null);
  return `à linha${dia ? ` de ${dia}` : ""}${conta ? ` do ${conta}` : ""}${valor ? ` (${valor})` : ""}`;
}

/**
 * "CMP-00124 ligado à linha de 08/10 do C6 - Conta PJ HBR (R$ 50,98): lancei no Extrato como …." + as
 * mensagens da rota. `aprovacao` (ajustes do dono): o sim aprovou a linha, falhou agora (tento de novo
 * na próxima rodada) ou a proposta ainda não estava na fila.
 */
export function textoDoLigado(c: CmpResumo, ligacao: Efeito | null | undefined, aprovacao: Aprovacao | null = null): string {
  const como = String(ligacao?.como ?? c.banco?.linha?.como ?? "");
  let frase: string;
  switch (como) {
    case "anexou": {
      const campos = preenchidosNoLancamento(ligacao?.corrigido);
      frase = campos.length
        ? `a linha já estava lançada: anexei e preenchi ${campos.join(" e ")}, que estava${campos.length > 1 ? "m" : ""} vazi${campos.length > 1 ? "as" : "a"}`
        : "a linha já estava lançada: anexei";
      break;
    }
    case "casou": {
      const conta = ligacao?.conta_aberta && typeof ligacao.conta_aberta === "object" ? ligacao.conta_aberta as { descricao?: string } : null;
      const desc = descricaoCurta(conta?.descricao ?? (typeof ligacao?.descricao === "string" ? ligacao.descricao : null))?.replace(/"/g, "'");
      frase = `dei baixa na conta a pagar${desc ? ` "${desc}"` : ""}`;
      break;
    }
    case "aguardando":
      frase = "lanço no Extrato assim que a compra entrar na fila (aprovada no seu sim)";
      break;
    default: {
      const a = lancadaNoExtrato(c, ligacao ?? null, aprovacao);
      frase = a.lancada
        ? `lancei no Extrato ${comoClassifica(c, false)}`
        : a.falha
        ? `classifiquei a linha ${comoClassifica(c, false)}, mas não consegui aprovar agora (${a.falha}): tento de novo na próxima rodada do Extrato`
        : `classifiquei ${comoClassifica(c, false)} (lanço no Extrato na próxima rodada)`;
    }
  }
  const daRota = ligacao?.mensagens;
  const mensagens = (Array.isArray(daRota) ? daRota as unknown[] : [])
    .filter((m): m is string => typeof m === "string" && m.trim() !== "")
    .map((m) => m.trim().slice(0, 300));
  return cortar([`${c.codigo} ligado ${linhaLigada(c)}: ${frase}.`, ...mensagens].join("\n"));
}

/** O dono disse que não é (verde) ou nenhuma destas (azul): a linha não volta a ser oferecida. */
export function textoDoRecusado(codigo: string, ate: string | null | undefined, nenhuma: boolean): string {
  const dia = diaMes(ate ?? null);
  return `${nenhuma ? "Ok, nenhuma destas." : "Ok, não é essa."} O ${codigo} continua esperando a linha certa no extrato${dia ? ` (até ${dia})` : ""}.`;
}

/** O extrato mudou entre a pergunta e a resposta: a pergunta nova, ou o CMP continua esperando. */
export function textoDoMudou(codigo: string, ate: string | null | undefined, nova: PerguntaDoExtrato | null): string {
  if (nova) return cortar(`As linhas do extrato mudaram desde a pergunta.\n\n${textoDaPerguntaDoExtrato(nova)}`);
  const dia = diaMes(ate ?? null);
  return `As linhas do extrato mudaram desde a pergunta. Não há mais linha que sirva: o ${codigo} continua esperando o extrato${dia ? ` (até ${dia})` : ""}.`;
}

// ---------------------------------------------------------------------------------------------
// Regra E (ajustes do dono): os resultados do "quem pagou?"
// ---------------------------------------------------------------------------------------------

/** O estado do CMP (no cartão e nos pendentes) que espera o "quem pagou?" da regra E. */
export function ehEstadoDoQuemPagou(estado: string | null | undefined): boolean {
  return estado === "banco_quem" || estado === "quem_pagou";
}

/** "a empresa pagou": "Ok: o CMP-00124 continua esperando o extrato (até 09/11)." */
export function textoDoQuemEsperando(codigo: string, ate: string | null | undefined): string {
  const dia = diaMes(ate ?? null);
  return `Ok: o ${codigo} continua esperando o extrato${dia ? ` (até ${dia})` : ""}.`;
}

/** "pago por você" / "pago pelo Roberto" / "gasto pessoal" (o CMP depois de gravado de novo). */
function quemPagouNoTexto(c: CmpResumo): string {
  if (c.destino === "pessoal") return "gasto pessoal";
  if (c.quem_pagou === "tecnico") return `pago pelo ${c.pagador_nome ?? "técnico"}`;
  if (c.quem_pagou === "socio") return "pago por você";
  return "pago pela empresa";
}

/**
 * Desfez o que estava gravado e gravou de novo com o pagador certo (na mesma transação):
 * "CMP-00124 corrigido: pago pelo Roberto. Feito: <frases da gravação>." + os avisos (o do almoço
 * que já está no extra da diária, por exemplo).
 */
export function textoDoRegravado(c: CmpResumo, gravacao: Gravacao | null | undefined, aprovacao: Aprovacao | null = null): string {
  const frases = frasesDaGravacao(gravacao?.efeitos, c, aprovacao);
  const pasta = gravacao?.pasta ?? pastaNoTexto(c);
  const partes = [`${c.codigo} corrigido: ${quemPagouNoTexto(c)}. Feito: ${frases.join("; ")}.${pasta ? ` Arquivo: ${pasta}.` : ""}`];
  const mensagens = (gravacao?.mensagens ?? []).filter((m) => typeof m === "string" && m.trim()).map((m) => m.trim().slice(0, 300));
  partes.push(...mensagens);
  partes.push(...textosDosAvisos((gravacao?.avisos ?? []).filter((a) => a !== "valor_incerto"), c, gravacao?.efeitos ?? null, true));
  return cortar(partes.join("\n"));
}

/**
 * Não deu para trocar (bloqueio do desfazer ou erro da rota): "Não troquei quem pagou o CMP-00124:
 * <bloqueio e como destravar>. Nada mudou." A mensagem crua do Postgres nunca vai ao dono.
 */
export function textoDoNaoTrocado(
  codigo: string,
  r: Pick<RespostaDoBanco, "motivo" | "bloqueios"> | null,
  numero: number | null = null,
  codigoDoErro: string | null = null,
): string {
  const cmpN = `*cmp ${numero ?? "N"}*`;
  const deNovo = (t: string) => t.replace(/ e cancele de novo\b/g, ` e mande ${cmpN} para responder de novo`);
  const bloqueios = textoDosBloqueios(r?.bloqueios).map(deNovo);
  let porque: string;
  if (bloqueios.length) porque = bloqueios.join("; ");
  else {
    const m = String(r?.motivo ?? "").trim();
    const doBloqueio = textoDoBloqueioDaF3({ motivo: m }) ?? BLOQUEIO_TEXTO[m];
    porque = doBloqueio ? deNovo(doBloqueio) : motivoDoNaoLigado(m, numero, codigoDoErro);
  }
  return cortar(`Não troquei quem pagou o ${codigo}: ${porque}. Nada mudou.`);
}

/** A resposta não serve ao "quem pagou?": o número da opção. */
export function textoInvalidaDoQuemPagou(codigo: string, opcoes: number): string {
  const n = Math.max(1, Math.trunc(Number(opcoes)) || 1);
  return `Para o ${codigo}, responda o número de quem pagou (${n === 1 ? "1" : `1 a ${n}`}).`;
}

/** A resposta não serve à pergunta do extrato (e o "ok"/número no verde): o que responder. */
export function textoInvalidaDoExtrato(codigo: string, azul: boolean, linhas = 3): string {
  if (!azul) return `Responda *sim* se essa linha é do ${codigo}, ou *não*.`;
  const n = Math.max(1, Math.trunc(Number(linhas)) || 1);
  return `Responda o número da linha (${n === 1 ? "1" : `1 a ${n}`}) ou 0 se não for nenhuma.`;
}

/** Os códigos que _comprovante_ligar devolve quando não liga (o comprovante_banco_responder os repassa). */
const MOTIVO_DO_NAO_LIGADO: Record<string, string> = {
  linha_de_outro_cmp: "essa linha do extrato já está ligada a outro comprovante",
  linha_nao_serve: "essa linha não serve mais para ele (o extrato mudou)",
  ja_ligado: "ele já está ligado a essa linha",
  ja_ligado_a_outra: "ele já está ligado a outra linha do extrato",
  cancelado: "ele foi cancelado",
  situacao: "ele não está mais esperando o banco",
  conflito: "a conta a pagar dele continua em aberto e essa linha já virou outro lançamento (o mesmo gasto duas vezes): cancele um dos dois no Financeiro",
};

/**
 * O motivo do "não liguei": o código da ligação em texto fixo; o erro conhecido da rota em texto fixo (o mesmo do não gravado); a frase das
 * nossas rotas (mês fechado, linha já ligada…) até 200; a mensagem crua do Postgres nunca — vira
 * "deu um erro no sistema (código X)".
 */
export function motivoDoNaoLigado(motivo: string | null | undefined, numero: number | null = null, codigoDoErro: string | null = null): string {
  const codigo = String(motivo ?? "").trim();
  if (MOTIVO_DO_NAO_LIGADO[codigo]) return MOTIVO_DO_NAO_LIGADO[codigo];
  const r = motivoDoNaoGravado(motivo, numero);
  if (r.conhecido) return r.texto;
  if (/^[a-z_]{1,40}$/.test(codigo)) return "essa linha não serve mais para ele";
  const m = codigo.replace(/^[0-9A-Z]{5}:\s*/, "").replace(/\s+/g, " ").trim();
  const cru = !m ||
    /violat|constraint|relation|column|syntax|function|null value|duplicate key|permission denied|does not exist|invalid input|operator|\bsql\b|\berror\b/i
      .test(m);
  if (!cru) return m.replace(/[.\s]+$/u, "").slice(0, 200);
  return `deu um erro no sistema${codigoDoErro ? ` (código ${codigoDoErro})` : ""}`;
}

export function textoNaoLigado(codigo: string, motivo: string | null | undefined, numero: number | null = null, codigoDoErro: string | null = null): string {
  return `Não liguei o ${codigo}: ${motivoDoNaoLigado(motivo, numero, codigoDoErro)}. Nada mudou. Responda de novo para tentar outra vez.`;
}

/** O "No extrato: …" do cartão (cmp N), pelo CmpResumo.banco. */
function bancoNoCartao(c: CmpResumo): string | null {
  const b = c.banco;
  if (!b || typeof b !== "object") return null;
  switch (b.estado) {
    case "esperando": {
      const dia = diaMes(b.ate ?? null);
      return `esperando a linha${dia ? ` (até ${dia})` : ""}`;
    }
    case "perguntar":
    case "pergunta_aberta":
      return `pergunta pendente (*cmp ${numeroDoCmp(c) ?? "N"}* para responder)`;
    case "ligado":
      return `ligado ${linhaLigada(c)}`;
    case "abandonado":
      return `não apareceu em ${c.forma === "credito" ? 45 : 30} dias: classifique no Extrato`;
    case "banco_quem":
    case "quem_pagou":
      return `falta saber quem pagou (não apareceu em conta da empresa: *cmp ${numeroDoCmp(c) ?? "N"}* para responder)`;
    default:
      return null;
  }
}
