// O caminho do PDF de uma ordem, de dentro de uma Edge Function: montar → renderizar →
// guardar por minutos → entregar a URL a quem envia → apagar.
//
// Nasceu dentro da tool send_document_pdf_to_self (25/09/2026). Saiu de lá em 26/09/2026
// porque o assistente passou a mandar o PDF também ao CLIENTE (send_service_order_link,
// formato 'pdf_e_link'), e duas cópias deste caminho é como uma delas fica para trás: o
// cliente receberia um documento diferente do que o dono recebe e do que o Baixar gera.
//
// As peças continuam as da tela, nada reescrito:
//   montagem dos dados   → dados.ts      (a mesma do Baixar e do portal)
//   desenho do documento → documento.ts  (o mesmo do Baixar)
//   HTML → PDF           → renderizar.ts (/api/pdf no Vercel, o mesmo Chromium do Baixar)
//
// O que NÃO mora aqui: para quem vai, com que legenda e com que `context`. Isso é decisão de
// cada tool — a para si nunca marca o orçamento como enviado; a para o cliente marca.

import { carregarPDFData, type LeitorDoBanco } from "./dados.ts";
import { documentTypeFor, type OrderDocumentType } from "./document-type.ts";
import {
  buildOrderHTML,
  buildPDFFilename,
  esc,
  fmtCurrency,
  type PDFOptions,
  resolvePdfOptions,
  tituloParaImpressao,
} from "./documento.ts";
import { renderizarPdf } from "./renderizar.ts";
import { hashCurto } from "../whatsapp/idempotencia.ts";
import { VALIDADE_PADRAO_DE_RESERVA } from "../ai/validade-orcamento.ts";

/** Bucket privado, sem policy nenhuma: só a chave de serviço lê e escreve. */
export const BUCKET_DO_PDF = "pdf-agente";
/**
 * A Evolution baixa o arquivo DENTRO da chamada de envio (que a tool corta aos 25 s), e o
 * objeto é apagado logo depois. A URL só precisa sobreviver a isso. Curta de propósito: o
 * whatsapp-send grava a URL no audit_log, que qualquer usuário logado lê.
 */
export const VALIDADE_DA_URL_S = 180;
/** O whatsapp-send recusa nome de arquivo acima de 120 caracteres (zod). */
const NOME_MAXIMO = 120;

/** Corta o nome para caber no limite do whatsapp-send, sem perder o ".pdf". */
export function limitarNomeDoArquivo(nome: string): string {
  if (nome.length <= NOME_MAXIMO) return nome;
  return `${nome.slice(0, NOME_MAXIMO - 4).replace(/[-_]+$/, "")}.pdf`;
}

/** O documento pronto para virar PDF, e o que as legendas precisam dizer dele. */
export type DocumentoDaOrdem = {
  html: string;
  nomeDoArquivo: string;
  tipoDoc: OrderDocumentType;
  rotulo: "Orçamento" | "Ordem de Serviço";
  numero: string;
  cliente: string;
  embarcacao: string | null;
  /** Já formatado em reais ("R$ 18.450,50"). */
  total: string;
};

/**
 * Monta o HTML exatamente como o Baixar do formulário.
 *
 * Sempre a via do CLIENTE, com valores (decisão do dono): a via de execução do técnico é
 * escolha por documento, nunca padrão — mas se um dia um padrão gravado a trouxer, sairia
 * uma OS sem preço com a legenda dizendo o total.
 */
export async function montarDocumentoDaOrdem(
  admin: LeitorDoBanco,
  ordem: { id: string; status: string | null },
  settings: Record<string, string>,
): Promise<{ ok: true; doc: DocumentoDaOrdem } | { ok: false; motivo: string }> {
  let dados;
  try {
    dados = await carregarPDFData(ordem.id, admin);
  } catch (e) {
    return { ok: false, motivo: `não consegui ler os dados do documento (${e instanceof Error ? e.message : String(e)})` };
  }
  const tipoDoc = documentTypeFor(ordem.status);
  dados.documentType = tipoDoc;
  // Validade: a do próprio orçamento; sem ela, o padrão da empresa — a mesma conta do
  // formulário (ServiceOrderForm: form.quote_validity_days || defaultQuoteValidityDays). A
  // reserva é a de validade-orcamento.ts, não um número daqui ("três fontes", 24/09/2026).
  const padraoDaEmpresa = Number(settings.quote_validity_days ?? VALIDADE_PADRAO_DE_RESERVA) || VALIDADE_PADRAO_DE_RESERVA;
  const opcoes: PDFOptions = {
    ...resolvePdfOptions(settings, tipoDoc),
    hideFinancials: false,
    ...(tipoDoc === "quote"
      ? { validity: { mode: "days" as const, days: Number(dados.serviceOrder.quote_validity_days) || padraoDaEmpresa } }
      : {}),
  };
  const html = buildOrderHTML(dados, opcoes).replace(
    /<title>[^<]*<\/title>/,
    `<title>${esc(tituloParaImpressao(dados, opcoes))}</title>`,
  );
  return {
    ok: true,
    doc: {
      html,
      nomeDoArquivo: limitarNomeDoArquivo(buildPDFFilename(dados, opcoes)),
      tipoDoc,
      rotulo: tipoDoc === "quote" ? "Orçamento" : "Ordem de Serviço",
      numero: dados.serviceOrder.service_order_number,
      cliente: dados.client?.name || "—",
      embarcacao: dados.vessel?.name || null,
      total: fmtCurrency(Number(dados.serviceOrder.grand_total) || 0),
    },
  };
}

/**
 * Impressão digital do CONTEÚDO do documento — para a chave anti-duplicado.
 *
 * O rodapé do documento traz "Emitido em dd/mm/aaaa, hh:mm:ss" com o relógio de agora: o
 * hash do HTML cru muda a cada segundo, e a chave nunca repetiria — o laço do agente que
 * repetisse a tool depois de um tempo esgotado mandaria o mesmo orçamento duas vezes ao
 * cliente. Tirando o carimbo, sobra o que o cliente lê: itens, valores, validade, condições.
 * Mudou qualquer um deles, a chave muda e o envio passa.
 */
export function impressaoDigitalDoDocumento(html: string): string {
  return hashCurto(html.replace(/Emitido em [^<]*/g, "Emitido em"));
}

/**
 * Renderiza, guarda num bucket PRIVADO, entrega a URL assinada a quem envia e apaga.
 *
 * `entregar` recebe a URL (vale VALIDADE_DA_URL_S) e devolve o que a tool precisa saber do
 * envio. Se renderizar, guardar ou assinar falhar, `entregar` NÃO é chamado: nada sai.
 * Sucesso ou falha, o arquivo não fica — o PDF leva preço e dados do cliente, e a cópia que
 * importa já está no WhatsApp.
 */
export async function guardarEEntregar<T>(p: {
  // deno-lint-ignore no-explicit-any
  admin: any;
  doc: Pick<DocumentoDaOrdem, "html" | "nomeDoArquivo">;
  shareToken: string;
  /** app_settings.app_public_url — o endereço do ERP no Vercel. */
  baseUrl: string;
  /** Prefixo do aviso no log quando o arquivo não pôde ser apagado. */
  rotuloDoLog: string;
  entregar: (urlAssinada: string) => Promise<T>;
}): Promise<{ ok: true; valor: T } | { ok: false; motivo: string }> {
  const render = await renderizarPdf({
    baseUrl: p.baseUrl,
    html: p.doc.html,
    filename: p.doc.nomeDoArquivo,
    shareToken: p.shareToken,
  });
  if (!render.ok) return { ok: false, motivo: render.motivo };

  const caminho = `agente/${new Date().getUTCFullYear()}/${crypto.randomUUID()}.pdf`;
  const armazem = p.admin.storage.from(BUCKET_DO_PDF);
  const { error: upErr } = await armazem.upload(caminho, render.pdf, { contentType: "application/pdf", upsert: false });
  if (upErr) return { ok: false, motivo: `não consegui guardar o arquivo (${upErr.message})` };

  try {
    const { data: assinada, error: urlErr } = await armazem.createSignedUrl(caminho, VALIDADE_DA_URL_S);
    if (urlErr || !assinada?.signedUrl) {
      return { ok: false, motivo: `não consegui gerar o endereço do arquivo (${urlErr?.message ?? "sem URL"})` };
    }
    return { ok: true, valor: await p.entregar(assinada.signedUrl) };
  } finally {
    // Falha ao apagar não derruba o envio, mas fica no log (o storage-js devolve { error },
    // não lança).
    const { error: rmErr } = await armazem.remove([caminho]).catch((e: unknown) => ({ error: e }));
    if (rmErr) console.warn(`[${p.rotuloDoLog}] não apaguei ${BUCKET_DO_PDF}/${caminho}:`, rmErr);
  }
}
