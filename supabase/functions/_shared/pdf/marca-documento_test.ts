import { assert, assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { FakeTime } from "https://deno.land/std@0.224.0/testing/time.ts";
import {
  buildOrderHTML,
  comFontesDaMarca,
  DEFAULT_PDF_OPTIONS,
  FIO_DO_CABECALHO,
  FONTE_DO_TEXTO,
  FONTE_DOS_TITULOS,
  SLOGAN_DO_RODAPE,
} from "./documento.ts";
import { AGORA, ORCAMENTO, ORCAMENTO_COM_PARCELAS, OS_COM_PAGAMENTO, VALIDADE_POR_DATA } from "./amostras.ts";
import { cssDasFontesDaMarca, FIO_EM_DEGRADE, FONTE_DO_TEXTO as FONTE_DO_TEXTO_DA_MARCA, FONTE_DOS_TITULOS as FONTE_DOS_TITULOS_DA_MARCA, MARCA, SLOGAN } from "./marca.ts";
import { FAIXAS_DA_OPEN_SANS_DO_SERVIDOR } from "./open-sans-faixas.ts";
import { caracteresForaDaFonteDoServidor, coresDeTextoClarasDemais } from "./marca-documento-regras.ts";

// A marca nos documentos do cliente (26/11/2026, opção 4 aprovada pelo dono): orçamento, OS (e, na tela, fatura,
// recibo e a capa do conjunto — src/lib/pdf-marca.test.ts). O que trava aqui:
//  · as cores e as letras são as de marca.ts (documento.ts repete os valores para não puxar as fontes embutidas);
//  · nenhum texto mais claro que o azul #274A6D — o cinza de antes sumia no modo rascunho da impressora (dono);
//  · nenhum caractere que a Open Sans do servidor não desenhe ("📷" e "↳" saíam como quadradinho);
//  · a Inter do Google saiu (as fontes vão embutidas por comFontesDaMarca).

function documentos(): string[] {
  const tempo = new FakeTime(new Date(AGORA));
  try {
    return [
      buildOrderHTML(ORCAMENTO, { ...DEFAULT_PDF_OPTIONS, validity: { mode: "days", days: 7 }, showDiscount: true }),
      buildOrderHTML(ORCAMENTO_COM_PARCELAS, { ...DEFAULT_PDF_OPTIONS, validity: VALIDADE_POR_DATA }),
      buildOrderHTML(OS_COM_PAGAMENTO, { ...DEFAULT_PDF_OPTIONS }),
      buildOrderHTML(OS_COM_PAGAMENTO, { ...DEFAULT_PDF_OPTIONS, hideFinancials: true }),
    ];
  } finally {
    tempo.restore();
  }
}

Deno.test("documento usa as letras, o fio e o slogan de marca.ts", () => {
  assertEquals(FONTE_DO_TEXTO, FONTE_DO_TEXTO_DA_MARCA);
  assertEquals(FONTE_DOS_TITULOS, FONTE_DOS_TITULOS_DA_MARCA);
  assertEquals(FIO_DO_CABECALHO, FIO_EM_DEGRADE);
  assertEquals(SLOGAN_DO_RODAPE, SLOGAN);
});

Deno.test("documento usa as cores de marca.ts e não a Inter do Google", () => {
  for (const html of documentos()) {
    assertStringIncludes(html, `--pdf-primary: ${MARCA.marinho};`);
    assertStringIncludes(html, `--pdf-primary-light: ${MARCA.azul};`);
    assertStringIncludes(html, `--pdf-secondary: ${MARCA.dourado};`);
    assertStringIncludes(html, `--pdf-text-muted: ${MARCA.azul};`);
    assertStringIncludes(html, `--pdf-border: ${MARCA.pauta};`);
    assertStringIncludes(html, `--pdf-grade: ${MARCA.grade};`);
    assertStringIncludes(html, `--pdf-fundo: ${MARCA.fundo};`);
    assert(!html.includes("fonts.googleapis"), "a Inter vinha do Google pela rede; as fontes agora vão embutidas");
    assert(!html.includes("'Inter'"), "sobrou Inter numa pilha de fonte");
    assertStringIncludes(html, `content: "${SLOGAN}"`);
    assertStringIncludes(html, 'class="doc-numero"');
    assertStringIncludes(html, '<div class="fio"></div>');
  }
});

Deno.test("nenhum texto do documento é mais claro que o azul da marca", () => {
  for (const html of documentos()) assertEquals(coresDeTextoClarasDemais(html), []);
});

Deno.test("nenhum caractere do documento cai fora da Open Sans do servidor", () => {
  const [orcamento, , os] = documentos();
  // As amostras têm o que fazia o quadradinho: resposta com foto, desconto por percentual (linha de detalhe) e
  // pagamento registrado ("Pago em").
  assertStringIncludes(orcamento, 'aria-label="com foto"');
  assertStringIncludes(orcamento, "Desconto em serviços");
  assertStringIncludes(os, "Pago em 20/09/2026");
  for (const html of documentos()) assertEquals(caracteresForaDaFonteDoServidor(html, FAIXAS_DA_OPEN_SANS_DO_SERVIDOR), []);
});

Deno.test("comFontesDaMarca põe as fontes no <head>; sem CSS, o documento fica como está", () => {
  const [html] = documentos();
  const comFontes = comFontesDaMarca(html, cssDasFontesDaMarca());
  const head = comFontes.slice(0, comFontes.indexOf("</head>"));
  assertStringIncludes(head, 'font-family: "Archivo"');
  assertStringIncludes(head, 'font-family: "Hanken Grotesk"');
  assertEquals(comFontesDaMarca(html, ""), html);
});
