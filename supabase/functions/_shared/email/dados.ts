// O que se tira de um e-mail, conferido por CÁLCULO (08/10/2026, etapa 4 do e-mail).
//
// NF-e anexa: chave com dígito verificador, destinada à HBR (CNPJ do destinatário), emitente,
// número e valor — via nfe-identify.ts. Boleto: linha digitável com DV, valor e vencimento — via
// boleto.ts, no texto do e-mail e no PDF anexo. Sem IA: um modelo que "quase acerta" o valor a
// pagar é pior que nenhum. Nada aqui lança conta nem mexe em estoque — só informa.

import { ehEventoNFe, ehParaEmpresa, identificarNFe, pareceNFe } from "./nfe-identify.ts";
import { extractBoletos } from "./boleto.ts";
import { classifyAttachment } from "./normalize.ts";
import type { InboundEmail } from "./types.ts";

export interface NFeDoEmail {
  anexo_indice: number;
  chave: string;
  emitente: string | null;
  emitente_cnpj: string | null;
  numero: string | null;
  serie: string | null;
  valor: number | null;
  data: string | null;
  para_empresa: boolean;
}

export interface BoletoDoEmail {
  linha: string;
  valor: number | null;
  vencimento: string | null;
  vencimento_incerto?: boolean;
  origem: "texto" | "pdf";
}

export interface DadosDoEmail {
  nfes: NFeDoEmail[];
  boletos: BoletoDoEmail[];
}

/** Lê o texto de um PDF (injetado: no servidor é o npm:unpdf; no teste, um dublê). */
export type LerPdf = (bytes: Uint8Array) => Promise<string>;

const MAX_PDF_BYTES = 1_500_000;

function decodificarXml(bytes: Uint8Array): string {
  const cabeca = new TextDecoder("ascii").decode(bytes.slice(0, 200));
  const declarado = /encoding=["']([^"']+)["']/i.exec(cabeca)?.[1] ?? "utf-8";
  return new TextDecoder(/8859|latin/i.test(declarado) ? "iso-8859-1" : "utf-8").decode(bytes);
}

export async function extrairDados(
  email: InboundEmail,
  cnpjEmpresa: string | null,
  lerPdf: LerPdf | null,
): Promise<DadosDoEmail | null> {
  const nfes: NFeDoEmail[] = [];
  const boletos: BoletoDoEmail[] = [];
  const recebido = new Date(email.receivedAt);
  const visto = new Set<string>();
  const somar = (lista: ReturnType<typeof extractBoletos>, origem: BoletoDoEmail["origem"]) => {
    for (const b of lista) {
      if (visto.has(b.linhaDigitavel)) continue;
      visto.add(b.linhaDigitavel);
      boletos.push({
        linha: b.linhaDigitavel,
        valor: b.valor,
        vencimento: b.tipo === "titulo" ? b.vencimento : null,
        ...(b.tipo === "titulo" && b.vencimentoIncerto ? { vencimento_incerto: true } : {}),
        origem,
      });
    }
  };

  somar(extractBoletos(`${email.subject ?? ""}\n${email.text ?? ""}`, recebido), "texto");

  for (const [i, a] of (email.attachments ?? []).entries()) {
    if (!a.content) continue;
    const tipo = classifyAttachment(a);
    if (tipo === "nfe_xml") {
      const xml = decodificarXml(a.content);
      if (!pareceNFe(xml) || ehEventoNFe(xml)) continue;
      const n = identificarNFe(xml);
      if (!n || !n.chaveValida) continue;
      nfes.push({
        anexo_indice: i, chave: n.chave, emitente: n.emitenteNome, emitente_cnpj: n.emitenteCnpj,
        numero: n.numero, serie: n.serie, valor: n.valorTotal, data: n.dataEmissao,
        para_empresa: ehParaEmpresa(n, cnpjEmpresa),
      });
    } else if (lerPdf && (tipo === "boleto_pdf" || (a.mimeType ?? "").includes("pdf")) && a.content.length <= MAX_PDF_BYTES) {
      try {
        somar(extractBoletos(await lerPdf(a.content), recebido), "pdf");
      } catch { /* PDF que não abre não derruba a leitura do e-mail */ }
    }
  }
  return nfes.length || boletos.length ? { nfes, boletos } : null;
}

/** "NF-e 812 · R$ 1.234,00" / "boleto R$ 350,00 vence 15/10" — para o resumo e o assistente. */
export function resumoDosDados(d: DadosDoEmail | null | undefined, reais: (n: number) => string): string | null {
  if (!d) return null;
  const partes: string[] = [];
  for (const n of d.nfes.filter((x) => x.para_empresa).slice(0, 2)) {
    partes.push(`NF-e ${n.numero ?? "?"}${n.valor != null ? ` · ${reais(n.valor)}` : ""}`);
  }
  for (const b of d.boletos.slice(0, 2)) {
    const venc = b.vencimento ? ` vence ${b.vencimento.slice(8, 10)}/${b.vencimento.slice(5, 7)}` : "";
    partes.push(`boleto${b.valor != null ? ` ${reais(b.valor)}` : ""}${venc}`);
  }
  return partes.length ? partes.join(" · ") : null;
}
