import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { dirname, fromFileUrl, join } from "https://deno.land/std@0.224.0/path/mod.ts";
import { FakeTime } from "https://deno.land/std@0.224.0/testing/time.ts";
import { buildOrderHTML, DEFAULT_PDF_OPTIONS, ultimoDiaDaValidade, validadeDoOrcamento } from "./documento.ts";
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
