import { assert, assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  carimbarRevisao,
  emitirRevisao,
  lerRevisao,
  linhaDaRevisaoNaLegenda,
  nomeComRevisao,
  precisaDeRevisao,
  type RevisaoDoDocumento,
} from "./revisao.ts";
import { buildOrderHTML, buildPDFFilename, DEFAULT_PDF_OPTIONS } from "./documento.ts";
import { ORCAMENTO } from "./amostras.ts";

const DO_BANCO = {
  revisao: 3, codigo: "7F3A-21C9", emitida_em: "2026-11-17T17:32:00+00:00", tipo: "quote",
  anterior: { revisao: 2, codigo: "AB12-CD34", emitida_em: "2026-11-15T13:00:00+00:00" },
};
const REV3: RevisaoDoDocumento = {
  numero: 3, codigo: "7F3A-21C9", emitidaEm: "2026-11-17T17:32:00+00:00",
  substitui: { numero: 2, emitidaEm: "2026-11-15T13:00:00+00:00" },
};

function banco(resposta: { data?: unknown; error?: unknown } | Error) {
  const chamadas: Array<{ fn: string; args?: Record<string, unknown> }> = [];
  return {
    chamadas,
    rpc: (fn: string, args?: Record<string, unknown>) => {
      chamadas.push({ fn, args });
      return resposta instanceof Error ? Promise.reject(resposta) : Promise.resolve({ data: resposta.data ?? null, error: resposta.error ?? null });
    },
  };
}

Deno.test("lerRevisao: a resposta do banco vira a revisão; forma estranha vira null", () => {
  assertEquals(lerRevisao(DO_BANCO), REV3);
  assertEquals(lerRevisao({ ...DO_BANCO, anterior: null }), { ...REV3, substitui: null });
  assertEquals(lerRevisao(null), null);
  assertEquals(lerRevisao({ ...DO_BANCO, revisao: 0 }), null);
  assertEquals(lerRevisao({ ...DO_BANCO, codigo: "<script>" }), null);
});

Deno.test("emitirRevisao: pede pelo id e pelo tipo; nunca lança; recibo e amostra não pedem", async () => {
  const ok = banco({ data: DO_BANCO });
  assertEquals(await emitirRevisao(ok, "os-1", "quote"), REV3);
  assertEquals(ok.chamadas, [{ fn: "documento_revisao_emitir", args: { p_os: "os-1", p_tipo: "quote" } }]);

  assertEquals(await emitirRevisao(banco({ error: { message: "function does not exist" } }), "os-1", "quote"), null);
  assertEquals(await emitirRevisao(banco(new Error("rede")), "os-1", "service_order"), null);

  const nada = banco({ data: DO_BANCO });
  assertEquals(await emitirRevisao(nada, "os-1", "receipt"), null);
  assertEquals(await emitirRevisao(nada, undefined, "quote"), null);
  assertEquals(nada.chamadas.length, 0);
});

Deno.test("carimbarRevisao: carimba uma vez (null = pedi e não veio, não pede de novo)", async () => {
  const b = banco({ data: DO_BANCO });
  const comId = { ...ORCAMENTO, serviceOrder: { ...ORCAMENTO.serviceOrder, id: "os-1" } };
  assert(precisaDeRevisao(comId));
  const carimbado = await carimbarRevisao(b, comId);
  assertEquals(carimbado.revisao, REV3);
  assert(!precisaDeRevisao(carimbado));
  await carimbarRevisao(b, carimbado);
  await carimbarRevisao(b, { ...comId, revisao: null });
  assertEquals(b.chamadas.length, 1);
  // a amostra (sem id) nunca pede
  assert(!precisaDeRevisao(ORCAMENTO));
});

Deno.test("documento com revisão: cabeçalho, 'substitui', rodapé com código e a revisão em toda página", () => {
  const html = buildOrderHTML({ ...ORCAMENTO, revisao: REV3 }, { ...DEFAULT_PDF_OPTIONS });
  assertStringIncludes(html, ">Revisão 3</div>");
  assertStringIncludes(html, "Substitui a Rev. 2 de 15/11/2026");
  assertStringIncludes(html, "Código de conferência 7F3A-21C9");
  assertStringIncludes(html, `${ORCAMENTO.serviceOrder.service_order_number} · Rev. 3 · Emitido em`);
  assertStringIncludes(html, `content: "${ORCAMENTO.serviceOrder.service_order_number} · Rev. 3 · pág. " counter(page) "/" counter(pages)`);
  assert(!html.includes("Documento Digital Autenticado"));
  // Rev. 1: sem "substitui"
  const rev1 = buildOrderHTML({ ...ORCAMENTO, revisao: { ...REV3, numero: 1, substitui: null } }, { ...DEFAULT_PDF_OPTIONS });
  assertStringIncludes(rev1, ">Revisão 1</div>");
  assert(!rev1.includes("Substitui a Rev."));
});

Deno.test("nome do arquivo: Rev depois do número; via reduzida também; sem revisão, o de sempre", () => {
  const com = { ...ORCAMENTO, revisao: REV3 };
  assertStringIncludes(buildPDFFilename(com), "_ORC-00086_Rev3_");
  assertEquals(buildPDFFilename(com, { ...DEFAULT_PDF_OPTIONS, ocultarDadosDoCliente: true }), "Orcamento_ORC-00086_Rev3.pdf");
  assert(!buildPDFFilename(ORCAMENTO).includes("Rev"));
});

Deno.test("nome dado por fora (padrão do cliente no WhatsApp) ganha a revisão antes do .pdf, uma vez só", () => {
  assertEquals(nomeComRevisao("Orcamento-ORÇ-00100.pdf", REV3), "Orcamento-ORÇ-00100_Rev3.pdf");
  assertEquals(nomeComRevisao("Orcamento-ORÇ-00100_Rev3.pdf", REV3), "Orcamento-ORÇ-00100_Rev3.pdf");
  assertEquals(nomeComRevisao("Orcamento-ORÇ-00100.pdf", null), "Orcamento-ORÇ-00100.pdf");
});

Deno.test("legenda: só da Rev. 2 em diante, dizendo qual substitui", () => {
  assertEquals(linhaDaRevisaoNaLegenda(REV3), "Revisão 3 (substitui a revisão 2, de 15/11/2026).");
  assertEquals(linhaDaRevisaoNaLegenda({ ...REV3, numero: 1, substitui: null }), "");
  assertEquals(linhaDaRevisaoNaLegenda(null), "");
});
