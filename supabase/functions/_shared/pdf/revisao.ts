// A revisão do documento (Rev. N), pedida ao banco no momento de GERAR o PDF.
//
// Decisões do dono (17/11/2026, D:/IA-HBR/Trabalho/revisao-documentos/PLANO.md): a revisão só sobe quando muda o que o
// cliente lê, e sobe ao gerar/enviar — por isso ela é pedida aqui, na geração, e nunca ao carregar os dados (a tela
// carrega o PDFData ao ABRIR o formulário; contar ali seria contar visualização).
//
// Quem decide se o conteúdo mudou é o banco (public.documento_revisao_emitir, migration 20270123100000): a tela, o
// portal do cliente e o servidor chegam ao mesmo número, e o cliente do link não consegue inventar revisão.
//
// Falhou (rede, migration ainda não aplicada, sem acesso)? O PDF sai SEM a revisão, como saía antes. Nunca bloqueia.

import type { PDFData, PDFDocumentType } from './documento.ts';
import { dataBR } from './datas.ts';

export type TipoComRevisao = 'quote' | 'service_order' | 'invoice';

export type RevisaoDoDocumento = {
  numero: number;
  /** Código de conferência impresso no rodapé ("7F3A-21C9"). */
  codigo: string;
  /** Instante da emissão (ISO). */
  emitidaEm: string;
  /** A revisão que esta substitui (para "Substitui a Rev. 2 de 15/11/2026"); null na Rev. 1. */
  substitui: { numero: number; emitidaEm: string } | null;
};

/** Quem pede: o cliente do Supabase da tela, do portal ou do servidor. */
export type ChamadorDeRpc = {
  // deno-lint-ignore no-explicit-any
  rpc: (fn: string, args?: Record<string, unknown>) => PromiseLike<{ data: any; error: any }>;
};

/** O recibo não tem revisão: ele nasce de um pagamento, não é um documento que se refaz. */
export function tipoComRevisao(tipo: PDFDocumentType | null | undefined): TipoComRevisao | null {
  return tipo === 'quote' || tipo === 'service_order' || tipo === 'invoice' ? tipo : null;
}

/** Lê o JSON de documento_revisao_emitir; qualquer forma inesperada vira null (o PDF sai sem revisão). */
export function lerRevisao(json: unknown): RevisaoDoDocumento | null {
  // deno-lint-ignore no-explicit-any
  const j = json as any;
  const numero = Number(j?.revisao);
  if (!j || !Number.isInteger(numero) || numero < 1) return null;
  if (typeof j.codigo !== 'string' || !/^[0-9A-F]{4}-[0-9A-F]{4}$/.test(j.codigo)) return null;
  if (typeof j.emitida_em !== 'string') return null;
  const antNum = Number(j.anterior?.revisao);
  const substitui = Number.isInteger(antNum) && antNum >= 1 && typeof j.anterior?.emitida_em === 'string'
    ? { numero: antNum, emitidaEm: j.anterior.emitida_em as string }
    : null;
  return { numero, codigo: j.codigo, emitidaEm: j.emitida_em, substitui };
}

/** Pede a revisão do conteúdo de agora (a mesma, se nada mudou; a próxima, se mudou). Nunca lança. */
export async function emitirRevisao(
  db: ChamadorDeRpc,
  serviceOrderId: string | null | undefined,
  tipo: PDFDocumentType | null | undefined,
): Promise<RevisaoDoDocumento | null> {
  const t = tipoComRevisao(tipo);
  if (!serviceOrderId || !t) return null;
  try {
    const { data, error } = await db.rpc('documento_revisao_emitir', { p_os: serviceOrderId, p_tipo: t });
    if (error) {
      console.warn('[pdf] revisão do documento indisponível; o PDF sai sem ela:', error?.message ?? error);
      return null;
    }
    return lerRevisao(data);
  } catch (e) {
    console.warn('[pdf] revisão do documento indisponível; o PDF sai sem ela:', e);
    return null;
  }
}

/** Falta pedir a revisão? (documento de uma ordem real, de tipo que tem revisão, ainda não carimbado) */
export function precisaDeRevisao(data: Pick<PDFData, 'revisao' | 'documentType' | 'serviceOrder'>): boolean {
  return data.revisao === undefined && !!data.serviceOrder?.id && !!tipoComRevisao(data.documentType);
}

/**
 * O nome de arquivo dado por fora (padrão do cliente no envio pelo WhatsApp, "Orcamento-ORÇ-00100.pdf") com a
 * revisão antes do ".pdf". O nome padrão (buildPDFFilename) já sai com ela; este é para o nome que não sai de lá.
 */
export function nomeComRevisao(nome: string, revisao: RevisaoDoDocumento | null | undefined): string {
  if (!revisao || /(^|[^A-Za-z])Rev\d+/.test(nome)) return nome;
  const base = nome.replace(/\.pdf$/i, '');
  return `${base}_Rev${revisao.numero}.pdf`;
}

/**
 * A linha da legenda do documento no WhatsApp a partir da Rev. 2: "Revisão 3 (substitui a revisão 2, de 15/11/2026)."
 * Na Rev. 1 nada — a primeira emissão não tem o que substituir, e a legenda fica como sempre foi.
 */
export function linhaDaRevisaoNaLegenda(revisao: RevisaoDoDocumento | null | undefined): string {
  if (!revisao?.substitui) return '';
  return `Revisão ${revisao.numero} (substitui a revisão ${revisao.substitui.numero}, de ${dataBR(revisao.substitui.emitidaEm)}).`;
}

/**
 * O PDFData com a revisão carimbada. Já carimbado (mesmo que null: "pedi e não veio") não pede de novo —
 * baixar chama isto e depois gera o blob, que chamaria outra vez.
 */
export async function carimbarRevisao(db: ChamadorDeRpc, data: PDFData): Promise<PDFData> {
  if (data.revisao !== undefined) return data;
  return { ...data, revisao: await emitirRevisao(db, data.serviceOrder?.id, data.documentType) };
}
