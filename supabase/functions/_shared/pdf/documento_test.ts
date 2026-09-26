import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { dirname, fromFileUrl, join } from "https://deno.land/std@0.224.0/path/mod.ts";
import { FakeTime } from "https://deno.land/std@0.224.0/testing/time.ts";
import {
  buildOrderHTML,
  DEFAULT_PDF_OPTIONS,
  opcoesPadraoDoDocumento,
  type PDFOptions,
  ultimoDiaDaValidade,
  validadeDoOrcamento,
} from "./documento.ts";
import { AGORA, ORCAMENTO, ORCAMENTO_COM_PARCELAS, OS_COM_PAGAMENTO, VALIDADE_POR_DATA } from "./amostras.ts";

// A metade Deno da paridade (a outra é src/lib/pdf-paridade-fuso.test.ts, no vitest).
//
// O assistente do WhatsApp gera o PDF numa Edge Function. Este teste roda o desenho do
// documento no Deno e compara com as MESMAS referências que o teste do navegador usa: se os
// dois passam, o orçamento que o dono recebe no WhatsApp é o que ele baixaria na tela.
//
// A independência de FUSO é provada do lado do vitest, que troca `process.env.TZ` entre
// quatro fusos (o Node respeita). O Deno no Windows IGNORA a variável TZ — conferido em
// 25/09/2026: `TZ=UTC deno eval` continua em Brasília —, então aqui o que se prova é outra
// coisa: que o motor do Deno (Intl, ICU) formata moeda e data byte a byte como o do Node.
// Num Linux, `TZ=UTC deno test --allow-read supabase/functions/_shared/pdf/` roda no fuso
// da Edge Function de verdade.

// fromFileUrl e não `new URL(...).pathname`: o caminho deste repo tem espaço ("Claude Code").
const REFERENCIA = join(dirname(fromFileUrl(import.meta.url)), "__referencia__");
const ler = (arquivo: string) => Deno.readTextFileSync(join(REFERENCIA, arquivo)).replace(/\r\n/g, "\n");

Deno.test("orçamento no Deno = referência do navegador", () => {
  const tempo = new FakeTime(new Date(AGORA));
  try {
    const html = buildOrderHTML(ORCAMENTO, { ...DEFAULT_PDF_OPTIONS, validity: { mode: "days", days: 7 } });
    assertEquals(html, ler("orcamento.html"));
  } finally {
    tempo.restore();
  }
});

Deno.test("OS com pagamento no Deno = referência do navegador", () => {
  const tempo = new FakeTime(new Date(AGORA));
  try {
    assertEquals(buildOrderHTML(OS_COM_PAGAMENTO, { ...DEFAULT_PDF_OPTIONS }), ler("os-com-pagamento.html"));
  } finally {
    tempo.restore();
  }
});

Deno.test("orçamento com parcelas e validade por data no Deno = referência do navegador", () => {
  const tempo = new FakeTime(new Date(AGORA));
  try {
    const html = buildOrderHTML(ORCAMENTO_COM_PARCELAS, { ...DEFAULT_PDF_OPTIONS, validity: VALIDADE_POR_DATA });
    assertEquals(html, ler("orcamento-parcelas.html"));
  } finally {
    tempo.restore();
  }
});

// A validade tem uma função só (26/09/2026): o envio pela tela e o portal saíam com "Válido
// por 15 dias" fixo porque não passavam validade nenhuma, e o gerador caía no literal.
Deno.test("validadeDoOrcamento: a do orçamento, senão a da empresa, senão 15", () => {
  assertEquals(validadeDoOrcamento(7, { quote_validity_days: "3" }), { mode: "days", days: 7 });
  assertEquals(validadeDoOrcamento(null, { quote_validity_days: "3" }), { mode: "days", days: 3 });
  assertEquals(validadeDoOrcamento(undefined, {}), { mode: "days", days: 15 });
  // sujeira na configuração não vira "Válido por NaN dias"
  assertEquals(validadeDoOrcamento(0, { quote_validity_days: "lixo" }), { mode: "days", days: 15 });
  assertEquals(validadeDoOrcamento(null, null), { mode: "days", days: 15 });
});

Deno.test("o 'até' do PDF é o último dia do aviso de vencimento (R19)", () => {
  const tempo = new FakeTime(new Date(AGORA));
  try {
    // Com a validade vinda da função, o documento é byte a byte a referência ("até 01/10/2026").
    const validity = validadeDoOrcamento(ORCAMENTO.serviceOrder.quote_validity_days, { quote_validity_days: "3" });
    assertEquals(buildOrderHTML(ORCAMENTO, { ...DEFAULT_PDF_OPTIONS, validity }), ler("orcamento.html"));
    // E o último dia que o motor de tarefas usa é o mesmo 01/10 — criado às 23h30 de 24/09.
    assertEquals(ultimoDiaDaValidade(ORCAMENTO.serviceOrder, {}), "2026-10-01");
    assertEquals(ler("orcamento.html").includes("(até 01/10/2026)"), true);
  } finally {
    tempo.restore();
  }
});

/** A linha de validade que o orçamento imprime com esta `validity`. */
const linhaDeValidade = (validity: PDFOptions["validity"], dados = ORCAMENTO) =>
  /Válido[^<]*/.exec(buildOrderHTML(dados, { ...DEFAULT_PDF_OPTIONS, validity }))?.[0];

// A normalização mora DENTRO do gerador (26/09/2026): o diálogo mandava `Number(x) || padrão`
// (-1 e 2.5 passavam), e qualquer caminho novo que esquecesse de normalizar imprimiria lixo.
// ORCAMENTO foi emitido às 23h30 de 24/09 (Brasília).
Deno.test("getValidityText: número inválido nunca vai impresso", () => {
  assertEquals(linhaDeValidade({ mode: "days", days: -1 }), "Válido por 15 dias (até 09/10/2026)");
  assertEquals(linhaDeValidade({ mode: "days", days: 0 }), "Válido por 15 dias (até 09/10/2026)");
  assertEquals(linhaDeValidade({ mode: "days", days: 2.5 }), "Válido por 2 dias (até 26/09/2026)");
  // 1e9 lançava RangeError na soma de datas e derrubava a geração do PDF
  assertEquals(linhaDeValidade({ mode: "days", days: 1e9 }), "Válido por 15 dias (até 09/10/2026)");
  assertEquals(linhaDeValidade({ mode: "days", days: 1 }), "Válido por 1 dia (até 25/09/2026)");
  assertEquals(linhaDeValidade(undefined), "Válido por 15 dias (até 09/10/2026)");
});

Deno.test("getValidityText: data específica vazia ou inexistente usa os dias, não o literal", () => {
  // o diálogo manda {mode:'date', days, date:''} quando se marca "Data específica" e não se
  // escolhe a data: antes saía "Válido por 15 dias." com 7 no campo de dias
  assertEquals(linhaDeValidade({ mode: "date", days: 7, date: "" }), "Válido por 7 dias (até 01/10/2026)");
  assertEquals(linhaDeValidade({ mode: "date", days: 7, date: "2026-02-31" }), "Válido por 7 dias (até 01/10/2026)");
  assertEquals(linhaDeValidade({ mode: "date", date: "2026-10-10" }), "Válido até 10/10/2026");
});

// O PDF ignorava quote_validity_date e a R19 a respeitava: o cliente lia "Válido por 7 dias
// (até 01/10)" e o aviso de vencido saía depois de 10/10. Agora os dois saem de
// validadeDoOrcamento.
Deno.test("data fixa: o PDF imprime a MESMA data que a R19 usa", () => {
  const comDataFixa = {
    ...ORCAMENTO,
    serviceOrder: { ...ORCAMENTO.serviceOrder, quote_validity_days: 7, quote_validity_date: "2026-10-10" },
  };
  const opcoes = opcoesPadraoDoDocumento({ quote_validity_days: "3" }, "quote", comDataFixa.serviceOrder);
  assertEquals(opcoes.validity, { mode: "date", date: "2026-10-10", days: 7 });
  assertEquals(ultimoDiaDaValidade(comDataFixa.serviceOrder, { quote_validity_days: "3" }), "2026-10-10");
  assertEquals(linhaDeValidade(opcoes.validity, comDataFixa), "Válido até 10/10/2026");
});

Deno.test("opcoesPadraoDoDocumento: padrão da EMPRESA (não o de fábrica), via do cliente, validade só no orçamento", () => {
  const ajustes = {
    quote_validity_days: "3",
    pdf_options_quote: JSON.stringify({ showTerms: false, hideFinancials: true }),
    pdf_options_service_order: JSON.stringify({ showTerms: false, hideFinancials: true }),
  };
  const orcamento = opcoesPadraoDoDocumento(ajustes, "quote", { quote_validity_days: 7 });
  assertEquals(orcamento.showTerms, false); // DEFAULT_PDF_OPTIONS diria true
  assertEquals(orcamento.hideFinancials, false); // documento sem diálogo vai para o cliente
  assertEquals(orcamento.validity, { mode: "days", days: 7 });
  // sem a ordem (ou sem validade nela): a da empresa
  assertEquals(opcoesPadraoDoDocumento(ajustes, "quote").validity, { mode: "days", days: 3 });
  const os = opcoesPadraoDoDocumento(ajustes, "service_order", { quote_validity_days: 7 });
  assertEquals(os.showTerms, false);
  assertEquals(os.hideFinancials, false);
  assertEquals(os.validity, undefined);
});
