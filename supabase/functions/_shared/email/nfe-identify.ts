// Identificação de NF-e em anexo de e-mail — determinístico, sem LLM.
//
// ESCOPO DELIBERADAMENTE PEQUENO: o parser completo de NF-e já existe em
// supabase/functions/process-nfe-xml (itens, GTIN, impostos, casamento com produto).
// Duplicar aquilo aqui seria criar duas verdades sobre o mesmo XML.
//
// Este módulo responde só três perguntas, que são as que o fluxo de e-mail precisa
// ANTES de acionar a importação:
//   1. esse anexo é mesmo uma NF-e?
//   2. a chave de acesso é matematicamente válida? (dígito verificador)
//   3. o mínimo para mostrar ao usuário e para deduplicar: quem emitiu, número, valor
//
// Com a chave validada dá para deduplicar importação sem depender de nome de arquivo,
// que fornecedor nenhum padroniza.

export interface NFeIdentificada {
  chave: string;               // 44 dígitos
  chaveValida: boolean;        // DV confere
  emitenteCnpj: string | null;
  emitenteNome: string | null;
  destinatarioCnpj: string | null;
  numero: string | null;
  serie: string | null;
  dataEmissao: string | null;  // YYYY-MM-DD
  valorTotal: number | null;
  /** 0 = entrada, 1 = saída (do ponto de vista de quem EMITIU). */
  tipoOperacao: "0" | "1" | null;
  /** true quando o XML é o evento de cancelamento/CC-e, não a nota em si. */
  ehEvento: boolean;
}

/**
 * Dígito verificador da chave de acesso (módulo 11, pesos 2..9 da direita).
 * Regra da SEFAZ: resto 0 ou 1 → DV 0.
 */
export function dvChaveAcesso(chave43: string): number {
  let soma = 0;
  let peso = 2;
  for (let i = chave43.length - 1; i >= 0; i--) {
    soma += Number(chave43[i]) * peso;
    peso = peso === 9 ? 2 : peso + 1;
  }
  const resto = soma % 11;
  return resto === 0 || resto === 1 ? 0 : 11 - resto;
}

/** Valida a chave inteira (44 dígitos, último é o DV). */
export function validarChaveAcesso(chave: string): boolean {
  const d = String(chave ?? "").replace(/\D/g, "");
  if (d.length !== 44) return false;
  return dvChaveAcesso(d.slice(0, 43)) === Number(d[43]);
}

/** Reconhece rapidamente se o conteúdo cheira a NF-e, sem parsear tudo. */
export function pareceNFe(xml: string): boolean {
  const s = String(xml ?? "");
  return /<infNFe[\s>]/i.test(s) || /<NFe[\s>]/i.test(s) || /<nfeProc[\s>]/i.test(s);
}

/** Evento (cancelamento, carta de correção, manifestação) não é nota a importar. */
export function ehEventoNFe(xml: string): boolean {
  return /<procEventoNFe[\s>]|<infEvento[\s>]|<retEvento[\s>]/i.test(String(xml ?? ""));
}

// Mesma abordagem por regex já usada em process-nfe-xml — o schema da NF-e é rígido,
// e manter o mesmo estilo evita duas formas diferentes de ler o mesmo arquivo.
function tag(xml: string, nome: string): string | null {
  const m = xml.match(new RegExp(`<${nome}[^>]*>([\\s\\S]*?)<\\/${nome}>`, "i"));
  return m ? decodeEntidades(m[1].trim()) : null;
}

function decodeEntidades(s: string): string {
  return s
    .replace(/&#x([0-9a-f]+);/gi, (_, h) => String.fromCodePoint(parseInt(h, 16)))
    .replace(/&#(\d+);/g, (_, d) => String.fromCodePoint(Number(d)))
    .replace(/&lt;/gi, "<").replace(/&gt;/gi, ">")
    .replace(/&quot;/gi, '"').replace(/&apos;/gi, "'")
    .replace(/&amp;/gi, "&");
}

/** Bloco de um elemento pai, para não pegar CNPJ do destinatário achando que é do emitente. */
function bloco(xml: string, nome: string): string {
  return xml.match(new RegExp(`<${nome}[^>]*>([\\s\\S]*?)<\\/${nome}>`, "i"))?.[1] ?? "";
}

/**
 * Extrai o mínimo identificável de um XML de NF-e.
 * Devolve null quando o conteúdo não é NF-e — o chamador trata como anexo comum.
 */
export function identificarNFe(xmlText: string): NFeIdentificada | null {
  const xml = String(xmlText ?? "");
  if (!pareceNFe(xml) && !ehEventoNFe(xml)) return null;

  const ehEvento = ehEventoNFe(xml);

  // A chave vem do atributo Id do infNFe ("NFe" + 44 dígitos). Em evento, do infEvento/chNFe.
  const chave =
    xml.match(/<infNFe[^>]*\bId="NFe(\d{44})"/i)?.[1] ??
    xml.match(/<chNFe>(\d{44})<\/chNFe>/i)?.[1] ??
    null;

  if (!chave) return null;

  const emit = bloco(xml, "emit");
  const dest = bloco(xml, "dest");
  const ide = bloco(xml, "ide");
  const total = bloco(xml, "ICMSTot");

  const dhEmi = tag(ide, "dhEmi") ?? tag(ide, "dEmi");
  const dataEmissao = dhEmi ? dhEmi.slice(0, 10) : null;

  const vNF = total ? Number(tag(total, "vNF")) : NaN;
  const tp = tag(ide, "tpNF");

  return {
    chave,
    chaveValida: validarChaveAcesso(chave),
    emitenteCnpj: emit ? (tag(emit, "CNPJ") ?? tag(emit, "CPF")) : null,
    emitenteNome: emit ? (tag(emit, "xNome") ?? tag(emit, "xFant")) : null,
    destinatarioCnpj: dest ? (tag(dest, "CNPJ") ?? tag(dest, "CPF")) : null,
    numero: tag(ide, "nNF"),
    serie: tag(ide, "serie"),
    dataEmissao,
    valorTotal: Number.isFinite(vNF) && vNF > 0 ? vNF : null,
    tipoOperacao: tp === "0" || tp === "1" ? tp : null,
    ehEvento,
  };
}

/**
 * A nota é destinada à HBR? Compara o CNPJ do destinatário com o da empresa.
 * Fornecedor às vezes manda o e-mail para a caixa errada, ou manda a nota de outro
 * cliente por engano — importar isso poluiria o estoque.
 */
export function ehParaEmpresa(nfe: NFeIdentificada, cnpjEmpresa: string | null | undefined): boolean {
  const meu = String(cnpjEmpresa ?? "").replace(/\D/g, "");
  const dele = String(nfe.destinatarioCnpj ?? "").replace(/\D/g, "");
  if (!meu || !dele) return false;
  return meu === dele;
}

/** Linha curta para o resumo diário. Sem inventar dado que não veio no XML. */
export function resumoNFe(nfe: NFeIdentificada): string {
  const quem = nfe.emitenteNome ?? "emitente não identificado";
  const num = nfe.numero ? `NF ${nfe.numero}` : "NF sem número";
  const valor = nfe.valorTotal != null
    ? ` de ${nfe.valorTotal.toLocaleString("pt-BR", { style: "currency", currency: "BRL" })}`
    : "";
  const alerta = nfe.chaveValida ? "" : " ⚠️ chave inválida";
  return `${quem} — ${num}${valor}${alerta}`;
}
