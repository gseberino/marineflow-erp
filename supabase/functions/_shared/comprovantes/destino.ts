// Onde o arquivo do CMP mora depois do "sim", com que nome, e o índice do mês (F2, 11/10/2026 —
// spec-f2.md, seção 4). Peças puras: quem fala com o Dropbox é o fluxo.ts.
//
//   os (barco com pasta)  → <pasta do barco>/1- DOC's/Compras
//   os sem barco/pasta    → COMPROVANTES/AAAA/AAAA-MM   (nunca /HBR-Testes/B2C)
//   estoque/insumo/empresa → COMPROVANTES/AAAA/AAAA-MM
//   pessoal               → COMPROVANTES/PESSOAL/AAAA-MM
//   cancelado             → COMPROVANTES/_CANCELADOS (nome + " CANCELADO")
// Um arquivo físico só por documento: o move_v2 mantém o id. Fornecedor só do cadastro ou da
// Receita (nunca do OCR); CPF nunca.
import { clienteGenerico, PASTA_DAS_COMPRAS } from "../dropbox/nucleo.ts";
import {
  extensaoDoCaminho,
  extensaoDoMime,
  formatarCnpj,
  fornecedorNoNome,
  horaNoNome,
  limparNome,
  PASTA_CANCELADOS,
  PASTA_COMPROVANTES,
  PASTA_PESSOAL,
  SIGLAS,
  TIPO_NO_AVISO,
} from "./nucleo.ts";

/** A forma de comprovante_destino_do_arquivo (RPC 16 da spec). */
export type DestinoDoArquivo = {
  id: string;
  codigo: string;
  situacao: string;
  cancelado: boolean;
  tipo: string | null;
  valor: string | number | null;
  valor_confirmado?: boolean;
  data: string | null;
  hora: string | null;
  fornecedor: string | null;
  destino: string | null;
  os: { numero: string; vessel_id: string | null; client_id: string | null; barco: string | null; cliente: string | null; pasta_registrada: boolean } | null;
  forma: string | null;
  conta: string | null;
  /** Ajustes do dono: no PESSOAL, "empresa" = saiu da conta/cartão da empresa (o nome leva o pagamento). */
  quem_pagou?: string | null;
  mes: string | null;
  dropbox_id: string | null;
  dropbox_caminho: string | null;
  dropbox_pendente: string | null;
  arquivo_path: string | null;
  arquivo_mime: string | null;
};

const PAGAMENTO: Record<string, string> = {
  pix: "PIX", debito: "DEBITO", credito: "CREDITO", dinheiro: "DINHEIRO", boleto: "BOLETO", transferencia: "TRANSF",
  deposito: "DEPOSITO", cheque: "CHEQUE", credito_loja: "CRED-LOJA", outro: "OUTRO",
};

const DESTINO_NO_NOME: Record<string, string> = { estoque: "ESTOQUE", insumo: "INSUMO", empresa: "EMPRESA", pessoal: "PESSOAL" };

const MAX_NOME = 200;

/**
 * O nome sem CPF (revisão de 11/10/2026): a razão social do MEI na Receita traz o CPF do titular
 * ("FULANO DA SILVA 12345678900") ou o CNPJ básico na frente ("12.345.678 FULANO"). O banco já grava
 * sem (comprovante_cnpj_cache, _comprovante_fornecedor); aqui é a defesa do nome do arquivo e do CSV.
 */
export function semCpf(nome: string | null | undefined): string | null {
  if (!nome) return null;
  const s = ` ${nome} `
    .replace(/\s\d{3}\.?\d{3}\.?\d{3}-?\d{2}(?=\s)/g, " ")
    .replace(/^\s*\d{2}\.?\d{3}\.?\d{3}\s+/, "")
    .replace(/\s+/g, " ")
    .trim();
  return s || null;
}

/** "2026-10" (do mes da RPC, senão da data). */
export function mesDoArquivo(d: Pick<DestinoDoArquivo, "mes" | "data">): string | null {
  const m = /^(\d{4}-\d{2})/.exec(String(d.mes ?? "")) ?? /^(\d{4}-\d{2})/.exec(String(d.data ?? ""));
  return m ? m[1] : null;
}

function reaisNoNome(v: string | number | null): string | null {
  const n = Number(v);
  if (v === null || v === "" || !Number.isFinite(n) || n <= 0) return null;
  const [inteiro, centavos] = n.toFixed(2).split(".");
  return `R$ ${inteiro.replace(/\B(?=(\d{3})+(?!\d))/g, ".")},${centavos}`;
}

/**
 * O PESSOAL que saiu da conta/cartão da empresa (ajustes do dono: gasto pessoal do sócio, descontado
 * do pró-labore). `quem_pagou` = "empresa", ou a conta que o banco mandou (do bolso ela é nula).
 */
function pessoalPagoPelaEmpresa(d: DestinoDoArquivo): boolean {
  return d.destino === "pessoal" && (d.quem_pagou === "empresa" || (d.quem_pagou == null && Boolean(d.conta)));
}

/**
 * "AAAA-MM-DD HHhMM CMP-00124 SIGLA R$ 62,00 Fornecedor - DESTINO - PAGAMENTO CONTA.ext".
 * Hora só se lida; fornecedor sem acento, até 40; pessoal sem "PAGAMENTO CONTA" — a não ser o pago
 * pela empresa ("… - PESSOAL - CREDITO EMPRESA"); até 200 caracteres (corta o fornecedor primeiro).
 */
export function nomeFinal(d: DestinoDoArquivo): string {
  const ext = extensaoDoCaminho(d.arquivo_path) ?? extensaoDoMime(d.arquivo_mime ?? "") ?? extensaoDoCaminho(d.dropbox_caminho) ?? "bin";
  const dia = /^\d{4}-\d{2}-\d{2}$/.test(String(d.data ?? "")) ? String(d.data) : `${mesDoArquivo(d) ?? "0000-00"}-01`;
  const inicio = [dia, horaNoNome(d.hora), limparNome(d.codigo || "CMP"), SIGLAS[d.tipo ?? ""] ?? "DOC", reaisNoNome(d.valor)]
    .filter((x): x is string => Boolean(x))
    .join(" ");

  let destino: string | null = null;
  if (d.destino === "os" && d.os) destino = limparNome(`${d.os.numero} ${d.os.barco || d.os.cliente || ""}`);
  else if (d.destino) destino = DESTINO_NO_NOME[d.destino] ?? null;
  const conta = d.conta ? limparNome(d.conta).toUpperCase() : pessoalPagoPelaEmpresa(d) ? "EMPRESA" : null;
  const pagamento = d.destino === "pessoal" && !pessoalPagoPelaEmpresa(d)
    ? null
    : [PAGAMENTO[d.forma ?? ""] ?? null, conta].filter(Boolean).join(" ") || null;
  const fim = [destino, pagamento].filter(Boolean).map((s) => ` - ${s}`).join("");

  let fornecedor = fornecedorNoNome(semCpf(d.fornecedor));
  const montar = () => limparNome(`${inicio}${fornecedor ? ` ${fornecedor}` : ""}${fim}`);
  let nome = montar();
  while (nome.length + ext.length + 1 > MAX_NOME && fornecedor) {
    fornecedor = fornecedor.length > 5 ? fornecedor.slice(0, fornecedor.length - 5).trim() : null;
    nome = montar();
  }
  if (nome.length + ext.length + 1 > MAX_NOME) nome = nome.slice(0, MAX_NOME - ext.length - 1).trim();
  return `${nome}.${ext}`;
}

/** O nome atual com " CANCELADO" antes da extensão (uma vez só). */
export function nomeCancelado(nomeAtual: string): string {
  const nome = String(nomeAtual ?? "").trim() || "CMP";
  const i = nome.lastIndexOf(".");
  const base = i > 0 ? nome.slice(0, i) : nome;
  const ext = i > 0 ? nome.slice(i) : "";
  if (/ CANCELADO$/.test(base)) return nome;
  return `${base} CANCELADO${ext}`;
}

/** O nome do arquivo no fim de um caminho do Dropbox. */
export function nomeDoCaminho(caminho: string | null | undefined): string | null {
  const s = String(caminho ?? "");
  const i = s.lastIndexOf("/");
  const nome = i >= 0 ? s.slice(i + 1) : s;
  return nome || null;
}

/**
 * A pasta do barco vale para o CMP de OS com barco, cliente que não é genérico (Cliente Final,
 * Teste) e pasta registrada — ou a pasta-base configurada para criar uma nova.
 */
export function usaPastaDoBarco(d: DestinoDoArquivo, temPastaBase: boolean): boolean {
  if (d.destino !== "os" || !d.os?.vessel_id || !d.os.client_id) return false;
  if (clienteGenerico(d.os.cliente)) return false;
  return d.os.pasta_registrada === true || temPastaBase;
}

/** A pasta final (sem o nome do arquivo). `pastaDoBarco` = a raiz do barco, quando usaPastaDoBarco. */
export function pastaFinal(d: DestinoDoArquivo, pastaDoBarco: string | null): string {
  if (d.cancelado || d.situacao === "cancelado" || d.dropbox_pendente === "cancelar") return PASTA_CANCELADOS;
  const mes = mesDoArquivo(d) ?? "0000-00";
  if (d.destino === "pessoal") return `${PASTA_PESSOAL}/${mes}`;
  if (d.destino === "os" && pastaDoBarco) return `${pastaDoBarco.replace(/\/+$/, "")}/${PASTA_DAS_COMPRAS}`;
  return `${PASTA_COMPROVANTES}/${mes.slice(0, 4)}/${mes}`;
}

/** "/MANAGEMENT/FINANCIALS/COMPROVANTES/2026/2026-10/_INDICE 2026-10.csv" (aceita "2026-10" ou "2026-10-01"). */
export function caminhoDoIndice(mes: string): string {
  const m = /^(\d{4})-(\d{2})/.exec(String(mes ?? ""));
  if (!m) throw new Error("mes_invalido");
  return `${PASTA_COMPROVANTES}/${m[1]}/${m[1]}-${m[2]}/_INDICE ${m[1]}-${m[2]}.csv`;
}

/**
 * F3 (padrão do dono, spec-f3.md 2.10): o índice da contadora não lista os PESSOAIS; a pasta PESSOAL
 * tem o próprio — "/MANAGEMENT/FINANCIALS/COMPROVANTES/PESSOAL/2026-10/_INDICE PESSOAL 2026-10.csv".
 */
export function caminhoDoIndicePessoal(mes: string): string {
  const m = /^(\d{4})-(\d{2})/.exec(String(mes ?? ""));
  if (!m) throw new Error("mes_invalido");
  return `${PASTA_PESSOAL}/${m[1]}-${m[2]}/_INDICE PESSOAL ${m[1]}-${m[2]}.csv`;
}

// ---------------------------------------------------------------------------------------------
// O índice do mês (CSV para a contadora): UTF-8 com BOM, ";", CRLF, decimal com vírgula
// ---------------------------------------------------------------------------------------------

/**
 * Uma linha de comprovantes_indice_do_mes (RPC 19). O banco manda `os` (o número) e, desde os ajustes
 * do dono (11/10/2026), `na_os` ('peca' | 'despesa' | 'ja_lancado'): o comprovante da OS só comprova
 * a peça ou o lançamento que já estava nela, ou é custo interno — nunca cobrança do cliente.
 */
export type LinhaDoIndice = {
  codigo: string;
  numero?: number | null;
  data?: string | null;
  hora?: string | null;
  tipo?: string | null;
  valor?: string | number | null;
  fornecedor?: string | null;
  cnpj?: string | null;
  destino?: string | null;
  os?: string | null;
  os_numero?: string | null;
  barco?: string | null;
  na_os?: "peca" | "despesa" | "ja_lancado" | string | null;
  quem_pagou?: string | null;
  forma?: string | null;
  situacao?: string | null;
  pendencias?: string[] | null;
  arquivo?: string | null;
};

export const COLUNAS_DO_INDICE = [
  "Código", "Data", "Hora", "Tipo", "Valor", "Fornecedor", "CNPJ", "Destino", "OS", "Barco", "Na OS", "Quem pagou",
  "Forma", "Situação", "Pendências", "Arquivo",
] as const;

/** O que o comprovante é na OS (nunca aparece para o cliente). */
const NA_OS_NO_INDICE: Record<string, string> = {
  peca: "peça (só comprova)", despesa: "despesa interna", ja_lancado: "já lançado na OS (só comprova)",
};

const DESTINO_NO_INDICE: Record<string, string> = { os: "OS", estoque: "Estoque", insumo: "Insumo", empresa: "Empresa", pessoal: "Pessoal" };
const QUEM_NO_INDICE: Record<string, string> = { empresa: "empresa", socio: "sócio", tecnico: "técnico", cliente: "cliente" };
const FORMA_NO_INDICE: Record<string, string> = {
  pix: "Pix", debito: "débito", credito: "crédito", dinheiro: "dinheiro", boleto: "boleto", transferencia: "transferência",
  deposito: "depósito", cheque: "cheque", credito_loja: "crédito na loja", outro: "outra",
};
const SITUACAO_NO_INDICE: Record<string, string> = {
  gravado: "gravado", aguardando_xml: "esperando a nota", cancelado: "cancelado", aguardando_vez: "em conferência",
  perguntando: "em conferência", aguardando_sim: "em conferência", lido: "a conferir", falhou: "a conferir",
  // F3: gravado e esperando/ligado à linha do extrato, ou sem linha depois do prazo
  aguardando_banco: "esperando o banco", conciliado: "ligado ao extrato", abandonado: "sem linha no extrato",
};
const PENDENCIA_NO_INDICE: Record<string, string> = {
  dar_entrada: "dar entrada no estoque", incluir_na_os: "lançar a peça na OS",
  acerto_tecnico: "acerto do técnico", classificar_no_extrato: "classificar no Extrato",
};

/** Campo do CSV: aspas quando tem ; " CR ou LF; fórmula ("=", "+", "-", "@") neutralizada com apóstrofo. */
export function campoCsv(v: string): string {
  let s = String(v ?? "");
  if (/^[=+\-@\t\r]/.test(s)) s = `'${s}`;
  return /[;"\r\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
}

function dataBr(d: string | null | undefined): string {
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(String(d ?? ""));
  return m ? `${m[3]}/${m[2]}/${m[1]}` : "";
}

function valorBr(v: string | number | null | undefined): string {
  const n = Number(v);
  if (v === null || v === undefined || v === "" || !Number.isFinite(n)) return "";
  return n.toFixed(2).replace(".", ",");
}


/** O CSV inteiro do mês (BOM + cabeçalho + uma linha por CMP, por número; CRLF no fim de cada linha). */
export function csvDoIndice(linhas: LinhaDoIndice[]): string {
  const ordenadas = [...(Array.isArray(linhas) ? linhas : [])].sort((a, b) =>
    (Number(a.numero ?? 0) - Number(b.numero ?? 0)) || String(a.codigo).localeCompare(String(b.codigo))
  );
  const corpo = ordenadas.map((l) => {
    const cnpj = /^\d{14}$/.test(String(l.cnpj ?? "")) ? formatarCnpj(l.cnpj) ?? "" : ""; // CPF (11) nunca
    const hora = /^(\d{2}):(\d{2})/.exec(String(l.hora ?? ""));
    return [
      l.codigo,
      dataBr(l.data),
      hora ? `${hora[1]}:${hora[2]}` : "",
      TIPO_NO_AVISO[l.tipo ?? ""] ?? (l.tipo ? "documento" : ""),
      valorBr(l.valor),
      semCpf(l.fornecedor) ?? "",
      cnpj,
      DESTINO_NO_INDICE[l.destino ?? ""] ?? "",
      l.os_numero ?? l.os ?? "",
      l.barco ?? "",
      NA_OS_NO_INDICE[l.na_os ?? ""] ?? "",
      QUEM_NO_INDICE[l.quem_pagou ?? ""] ?? "",
      FORMA_NO_INDICE[l.forma ?? ""] ?? "",
      SITUACAO_NO_INDICE[l.situacao ?? ""] ?? (l.situacao ?? ""),
      (l.pendencias ?? []).map((p) => PENDENCIA_NO_INDICE[p] ?? p).join(", "),
      l.arquivo ?? "",
    ].map(campoCsv).join(";");
  });
  return `﻿${[COLUNAS_DO_INDICE.join(";"), ...corpo].join("\r\n")}\r\n`;
}
