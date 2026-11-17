// "Imprime o orçamento 86" / "imprime a via do técnico da OS 136" / "imprime as vias de hoje" (17/11/2026).
//
// Não é uma tool nova: é o destino 'impressora' da send_document_pdf_to_self, que já está nos dois perfis, já é
// ensinada pelo prompt e já tem o atalho sem modelo (atalho-pdf.ts). O papel é o MESMO PDF que iria ao WhatsApp
// (_shared/impressao/imprimir.ts); a fila e o PC estão em _shared/impressao/fila.ts.
//
// Quem pede: os mesmos cargos do PDF (admin e financeiro — o orçamento leva preço). Os técnicos pedem pelo WhatsApp
// deles, pelo whatsapp-webhook (_shared/impressao/pedido-da-equipe.ts), e só a via do técnico.

import type { ToolCtx } from "./registry.ts";
import { localizarOrdem } from "./documentos-pdf.ts";
import { acharPessoa } from "./via-do-tecnico.ts";
import { hojeEmBrasilia, pessoasDaOs } from "../../pdf/via-do-tecnico-dados.ts";
import { fraseDoResultado, impressoraNoAr, limitarCopias } from "../../impressao/fila.ts";
import { osDaAgendaDoDia } from "../../impressao/agenda.ts";
import {
  abrirViaPeloId,
  type Impressao,
  imprimirOrdem,
  imprimirVia,
  type OpcoesDeImpressao,
  VIAS_POR_PEDIDO_MAX,
} from "../../impressao/imprimir.ts";

const ehHoje = (s: string) => /^(as |as vias de )?(hoje|vias? de hoje|do dia)$/i.test(s.normalize("NFD").replace(/[̀-ͯ]/g, "").trim());

/** O que a tool devolve ao modelo (e o atalho sem modelo lê `frase`). */
function resposta(impressoes: Impressao[], extra: Record<string, unknown> = {}): Record<string, unknown> {
  const frases = impressoes.map((i) => fraseDoResultado(i.oque, i.resultado, i.copias));
  const algum = impressoes.some((i) => i.resultado.ok);
  return {
    ok: algum,
    impresso: algum,
    documentos: impressoes.map((i) => i.oque),
    frase: frases.join("\n"),
    ...extra,
    orientacao: "Diga exatamente o que a frase diz (o que foi para a impressora e o que não foi, com o motivo). Nunca diga que imprimiu o que não foi.",
  };
}

export async function imprimirParaQuemPediu(args: Record<string, unknown>, ctx: ToolCtx): Promise<Record<string, unknown>> {
  const { admin, settings } = ctx;
  const noAr = await impressoraNoAr(admin);
  if (!noAr.ok) return { error: `Não dá para imprimir agora: ${noAr.motivo}.`, orientacao: "Diga o motivo; o PDF pode ir pelo WhatsApp (sem destino) se ele quiser." };

  const opcoes: OpcoesDeImpressao = {
    copias: limitarCopias(args.copias),
    colorido: args.colorido !== false,
    pedidoPor: { usuario: ctx.userId || null },
  };
  const documento = String(args.documento ?? "").trim();
  const tecnico = args.via === "tecnico" || ehHoje(documento);

  if (!tecnico) {
    const achado = await localizarOrdem(admin, documento, args.tipo as string | undefined);
    if ("erro" in achado) return { error: achado.erro };
    if ("opcoes" in achado) return { error: `Há mais de um documento com esse número: ${achado.opcoes.join(" e ")}. Pergunte qual.`, opcoes: achado.opcoes };
    return resposta([await imprimirOrdem(admin, settings, achado.ordem, opcoes)]);
  }

  // "as vias de hoje": cada OS da agenda de hoje, a via inteira (sem preço).
  if (ehHoje(documento)) {
    let ids: string[];
    try {
      ids = await osDaAgendaDoDia(admin, hojeEmBrasilia());
    } catch (e) {
      return { error: e instanceof Error ? e.message : String(e) };
    }
    if (!ids.length) return { ok: false, frase: "Não há OS na agenda de hoje; nada a imprimir.", orientacao: "Diga isso." };
    const feitas: Impressao[] = [];
    for (const id of ids.slice(0, VIAS_POR_PEDIDO_MAX)) {
      const aberta = await abrirViaPeloId(admin, id, settings);
      if ("erro" in aberta) {
        feitas.push({ oque: "uma via de hoje", copias: 1, resultado: { ok: false, motivo: aberta.erro } });
        continue;
      }
      feitas.push(await imprimirVia(admin, settings, aberta, null, [], opcoes));
    }
    return resposta(feitas, ids.length > VIAS_POR_PEDIDO_MAX ? { aviso: `Imprimi só as ${VIAS_POR_PEDIDO_MAX} primeiras de ${ids.length} OS de hoje.` } : {});
  }

  const achado = await localizarOrdem(admin, documento, "os");
  if ("erro" in achado) return { error: achado.erro };
  if ("opcoes" in achado) return { error: `Há mais de um documento com esse número: ${achado.opcoes.join(" e ")}. Pergunte qual.` };
  const aberta = await abrirViaPeloId(admin, achado.ordem.id, settings);
  if ("erro" in aberta) return { error: `Não consegui imprimir a via: ${aberta.erro}.` };

  let pessoa: { id: string; nome: string } | null = null;
  let dias: string[] = [];
  const nome = String(args.pessoa ?? "").trim();
  if (nome) {
    const daOs = await pessoasDaOs(admin, aberta.dados);
    const achada = await acharPessoa(admin, nome, daOs);
    if ("erro" in achada) return { error: achada.erro };
    pessoa = { id: achada.pessoa.id, nome: achada.pessoa.nome };
    dias = daOs.find((p) => p.id === achada.pessoa.id)?.dias ?? [];
  }
  const feita = await imprimirVia(admin, settings, aberta, pessoa, dias, opcoes);
  if (feita.semServicoDaPessoa) {
    return { error: `A via de ${pessoa?.nome} sairia vazia: ${feita.resultado.ok ? "" : feita.resultado.motivo}. Ofereça imprimir a via da OS inteira.` };
  }
  return resposta([feita]);
}
