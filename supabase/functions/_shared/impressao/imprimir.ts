// O papel que vai à impressora: o MESMO PDF que vai ao WhatsApp, entregue à fila da impressora (fila.ts) em vez de
// ao whatsapp-send. Nada da montagem é reescrito:
//   orçamento / OS (via do cliente) → montarDocumentoDaOrdem + guardarEEntregar (gerar-e-guardar.ts)
//   via do técnico                  → carregarDadosDaVia + mandarVia (via-do-tecnico-envio.ts), com o "enviar" trocado
// Usado pela tool send_document_pdf_to_self (destino='impressora') e pelo pedido do técnico no whatsapp-webhook.

import { guardarEEntregar, impressaoDigitalDoDocumento, montarDocumentoDaOrdem } from "../pdf/gerar-e-guardar.ts";
import { carregarDadosDaVia, type OrdemDaVia } from "../pdf/via-do-tecnico-dados.ts";
import type { DadosDaVia } from "../pdf/via-do-tecnico.ts";
import { type EnviarDocumento, mandarVia } from "../pdf/via-do-tecnico-envio.ts";
import { chaveDeEnvio } from "../whatsapp/idempotencia.ts";
import { imprimirPelaFila, limitarCopias, type PedidoDeImpressao, type ResultadoDaImpressao } from "./fila.ts";

// deno-lint-ignore no-explicit-any
type Admin = any;

export interface OpcoesDeImpressao {
  copias?: unknown;
  colorido?: boolean;
  pedidoPor: PedidoDeImpressao["pedidoPor"];
  /** Para testes e para o webhook (que pode esperar mais). */
  esperarMs?: number;
  /** Troca a fila (testes). */
  fila?: typeof imprimirPelaFila;
}

export interface Impressao {
  /** "o Orçamento ORÇ-00086", "a via do técnico da OS-00136 (Alex)". */
  oque: string;
  resultado: ResultadoDaImpressao;
  copias: number;
  /** A via da pessoa ficaria vazia (os serviços dela estão com outra pessoa): nada foi à fila. */
  semServicoDaPessoa?: boolean;
}

const quem = (o: OpcoesDeImpressao) => o.pedidoPor.usuario || o.pedidoPor.payee || "anonimo";

/** Orçamento ou OS como o cliente recebe (com valores): o PDF do botão Baixar. Nunca lança. */
export async function imprimirOrdem(
  admin: Admin,
  settings: Record<string, string>,
  ordem: { id: string; status: string | null; share_token: string | null; service_order_number: string },
  o: OpcoesDeImpressao,
): Promise<Impressao> {
  const copias = limitarCopias(o.copias);
  const fila = o.fila ?? imprimirPelaFila;
  let oque = `o documento ${ordem.service_order_number}`;
  try {
    if (!ordem.share_token) return { oque, copias, resultado: { ok: false, motivo: "a ordem não tem token de link (o PDF não tem como ser gerado)" } };
    const montado = await montarDocumentoDaOrdem(admin, ordem, settings);
    if (!montado.ok) return { oque, copias, resultado: { ok: false, motivo: montado.motivo } };
    const doc = montado.doc;
    oque = `o ${doc.rotulo} ${doc.numero} (${doc.cliente})`;
    const chave = chaveDeEnvio("imprimir-doc", ordem.id, quem(o), impressaoDigitalDoDocumento(doc.html), copias, o.colorido ? "cor" : "pb");
    const entrega = await guardarEEntregar({
      admin,
      doc,
      shareToken: ordem.share_token,
      baseUrl: settings.app_public_url || "",
      rotuloDoLog: "imprimir",
      entregar: (url) =>
        fila(admin, {
          url, nome: doc.nomeDoArquivo, copias, colorido: o.colorido, descricao: `${doc.rotulo} ${doc.numero}`, pedidoPor: o.pedidoPor, chave,
        }, o.esperarMs ? { esperarMs: o.esperarMs } : {}),
    });
    if (!entrega.ok) return { oque, copias, resultado: { ok: false, motivo: entrega.motivo } };
    return { oque, copias, resultado: entrega.valor };
  } catch (e) {
    return { oque, copias, resultado: { ok: false, motivo: e instanceof Error ? e.message : String(e) } };
  }
}

/**
 * A via do técnico (sem preço): da pessoa (só os serviços dela e os sem responsável) ou da OS inteira. Nunca lança.
 * `pessoa` sem serviço nesta OS = semServicoDaPessoa, sem nada na fila (quem chama decide se imprime a OS inteira).
 */
export async function imprimirVia(
  admin: Admin,
  settings: Record<string, string>,
  aberta: { dados: DadosDaVia; ordem: OrdemDaVia },
  pessoa: { id: string; nome: string } | null,
  dias: string[],
  o: OpcoesDeImpressao,
): Promise<Impressao> {
  const { dados, ordem } = aberta;
  const copias = limitarCopias(o.copias);
  const fila = o.fila ?? imprimirPelaFila;
  const oque = `a via do técnico da ${ordem.numero}${pessoa ? ` (${pessoa.nome})` : ""}`;
  // Caixa (e não "let"): o TypeScript não enxerga a atribuição dentro da função e estreitaria para null.
  const caixa: { r: ResultadoDaImpressao | null } = { r: null };
  // O "enviar" do mandarVia, trocado: em vez do WhatsApp, a fila da impressora. O telefone não é usado.
  const paraAImpressora: EnviarDocumento = async (e) => {
    const resultado = await fila(admin, {
      url: e.url, nome: e.filename, copias, colorido: o.colorido, descricao: `Via do técnico ${ordem.numero}${pessoa ? ` (${pessoa.nome})` : ""}`,
      pedidoPor: o.pedidoPor, chave: e.dedupeKey ?? chaveDeEnvio("imprimir-via", ordem.id, pessoa?.id ?? "os", quem(o)),
    }, o.esperarMs ? { esperarMs: o.esperarMs } : {});
    caixa.r = resultado;
    return resultado.ok ? { ok: true } : { ok: false, error: resultado.motivo };
  };
  const r = await mandarVia({
    admin, settings, jwt: "", dados, ordem, pessoa, telefone: "", contexto: "impressao",
    enviar: paraAImpressora, diasNaAgenda: dias,
    chave: (impressao) => chaveDeEnvio("imprimir-via", ordem.id, pessoa?.id ?? "os", quem(o), impressao, copias, o.colorido ? "cor" : "pb"),
  });
  if (caixa.r) return { oque, copias, resultado: caixa.r };
  if (!r.ok && r.pulado) return { oque, copias, semServicoDaPessoa: true, resultado: { ok: false, motivo: r.motivo } };
  return { oque, copias, resultado: r.ok ? { ok: false, motivo: "a via não chegou à fila" } : { ok: false, motivo: r.motivo } };
}

/** Abre a OS para a via (pelo id). Erro em frase. */
export async function abrirViaPeloId(
  admin: Admin,
  serviceOrderId: string,
  settings: Record<string, string>,
): Promise<{ dados: DadosDaVia; ordem: OrdemDaVia } | { erro: string }> {
  const lida = await carregarDadosDaVia(admin, serviceOrderId, settings);
  if (!lida.ok) return { erro: `não consegui montar a via: ${lida.motivo}` };
  return { dados: lida.dados, ordem: lida.ordem };
}

/** No máximo tantas vias num pedido só ("as vias de hoje"). */
export const VIAS_POR_PEDIDO_MAX = 6;
