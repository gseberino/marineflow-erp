// O quadro de valores é um só para o PDF e para o resumo em TEXTO do WhatsApp (20/11/2026, dono:
// "Sim, mesma regra do PDF"). Aqui: as linhas visíveis sempre somam o total — tudo visível,
// deslocamento oculto, impostos ocultos, desconto geral oculto — e o texto lista as mesmas linhas,
// na mesma ordem, que o PDF.
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { linhasDoQuadroDeValores, quadroDeValoresEmTexto, somaDoQuadro, type OpcoesDoQuadro } from "./quadro-de-valores.ts";
import { buildQuoteWhatsAppSummary } from "./resumo-whatsapp.ts";
import { DEFAULT_PDF_OPTIONS, linhasDoResumo, type PDFData, type PDFOptions } from "./documento.ts";
import { ORCAMENTO } from "./amostras.ts";

// Total pela fórmula de calc_so_totals: 2.000 + 1.000 + 300 (deslocamento) + 100 (despesas)
// + 200 (terceiros) − 150 (desconto) + 250 (impostos) + 80 (taxa de cartão) = 3.780.
const ORDEM = {
  labor_cost_total: 2000,
  parts_cost_total: 1000,
  travel_cost_total: 300,
  is_travel_billable: true,
  operational_cost_total: 100,
  subcontract_cost_total: 200,
  discount_amount: 150,
  tax_amount: 250,
  card_fee_amount: 80,
  card_installments: 3,
  grand_total: 3780,
};

const TUDO: OpcoesDoQuadro = { servicos: true, pecas: true, deslocamento: true, impostos: true, taxaCartao: true, desconto: true };

const CASOS: Array<[string, Partial<OpcoesDoQuadro>, Partial<PDFOptions>]> = [
  ["tudo visível", {}, {}],
  ["deslocamento oculto", { deslocamento: false }, { showTravelCost: false }],
  ["impostos ocultos", { impostos: false }, { showTax: false }],
  ["taxa de cartão oculta", { taxaCartao: false }, { showCardFee: false }],
  ["desconto geral oculto", { desconto: false }, { showDiscount: false }],
  ["tudo oculto", { deslocamento: false, impostos: false, taxaCartao: false, desconto: false },
    { showTravelCost: false, showTax: false, showCardFee: false, showDiscount: false }],
];

const semNbsp = (t: string) => t.replace(/ /g, " ");
const reais = (v: string) => Number(v.replace(/\./g, "").replace(",", "."));

/** Soma as linhas "• Rótulo: R$ x" / "• Rótulo: −R$ x" do bloco *Valores* e lê o *Total*. */
function somaDoTexto(texto: string): { soma: number; total: number; rotulos: string[] } {
  const linhas = semNbsp(texto).split("\n");
  let soma = 0;
  const rotulos: string[] = [];
  for (const l of linhas) {
    const m = l.match(/^• (.+): (−?)R\$ ([\d.,]+)$/);
    if (!m) continue;
    rotulos.push(m[1]);
    soma += (m[2] ? -1 : 1) * reais(m[3]);
  }
  const t = linhas.find((l) => l.startsWith("*Total: "))!.match(/R\$ ([\d.,]+)/)!;
  return { soma: Math.round(soma * 100) / 100, total: reais(t[1]), rotulos };
}

for (const [nome, opcoes] of CASOS) {
  Deno.test(`quadro: ${nome} — as linhas somam o total`, () => {
    assertEquals(somaDoQuadro(linhasDoQuadroDeValores(ORDEM, { ...TUDO, ...opcoes })), ORDEM.grand_total);
  });
}

Deno.test("quadro: tudo visível — cada parcela na sua linha, impostos e taxa inclusive", () => {
  const rotulos = linhasDoQuadroDeValores(ORDEM, TUDO).map((l) => l.rotulo);
  assertEquals(rotulos, [
    "Serviços", "Peças e materiais", "Deslocamento / logística", "Outras despesas", "Serviços de terceiros",
    "Desconto", "Impostos", "Taxa de cartão (3x)",
  ]);
});

Deno.test("quadro: deslocamento, impostos e taxa ocultos viram UMA linha 'Outros encargos'", () => {
  const l = linhasDoQuadroDeValores(ORDEM, { ...TUDO, deslocamento: false, impostos: false, taxaCartao: false });
  assertEquals(l.map((x) => x.rotulo).includes("Impostos"), false);
  assertEquals(l.filter((x) => x.rotulo === "Outros encargos"), [{ rotulo: "Outros encargos", valor: 630, negativo: false, tipo: "normal" }]);
});

Deno.test("quadro: desconto geral oculto vira 'Ajustes' negativo, não encargo", () => {
  const l = linhasDoQuadroDeValores(ORDEM, { ...TUDO, desconto: false });
  assertEquals(l.at(-1), { rotulo: "Ajustes", valor: 150, negativo: true, tipo: "normal" });
  assertEquals(l.some((x) => x.rotulo.startsWith("Desconto")), false);
});

Deno.test("quadro: deslocamento não faturável não entra em linha nenhuma (não está no total)", () => {
  const l = linhasDoQuadroDeValores({ ...ORDEM, is_travel_billable: false }, { ...TUDO, deslocamento: false });
  assertEquals(somaDoQuadro(l), ORDEM.grand_total - 300);
});

Deno.test("quadro: a quebra do desconto por percentual (↳) não conta na soma", () => {
  const so = { ...ORDEM, discount_services_pct: 5, discount_parts_pct: 5, discount_amount: 150 };
  const l = linhasDoQuadroDeValores(so, { ...TUDO, descontoDosItens: 10 });
  assertEquals(l.filter((x) => x.tipo === "detalhe").map((x) => x.rotulo), [
    "↳ Desconto adicional em serviços (5%)", "↳ Desconto adicional em peças (5%)",
  ]);
  assertEquals(somaDoQuadro(l), ORDEM.grand_total);
  assertEquals(quadroDeValoresEmTexto(l).filter((t) => t.startsWith("   ↳")).length, 2);
});

// ── O resumo em texto do WhatsApp (o espelho do assistente) ───────────────────────────────

const resumo = (opcoes: Partial<PDFOptions>) =>
  buildQuoteWhatsAppSummary({
    numero: "ORÇ-00999",
    clienteNome: "Cliente Teste",
    orcamento: ORDEM,
    parcelas: null,
    opcoes: { ...DEFAULT_PDF_OPTIONS, ...opcoes },
  });

for (const [nome, , opcoes] of CASOS) {
  Deno.test(`texto do WhatsApp: ${nome} — as linhas somam o total`, () => {
    const { soma, total } = somaDoTexto(resumo(opcoes));
    assertEquals(total, 3780);
    assertEquals(soma, total);
  });
}

Deno.test("texto do WhatsApp: impostos visíveis aparecem; ocultos entram em 'Outros encargos'", () => {
  assert(somaDoTexto(resumo({})).rotulos.includes("Impostos"));
  const oculto = semNbsp(resumo({ showTax: false }));
  assert(!oculto.includes("Impostos"));
  assert(oculto.includes("• Outros encargos: R$ 250,00"));
});

Deno.test("texto do WhatsApp: deslocamento oculto → 'Outros encargos', e a soma fecha", () => {
  const t = semNbsp(resumo({ showTravelCost: false }));
  assert(!t.includes("Deslocamento"));
  assert(t.includes("• Outros encargos: R$ 300,00"));
});

Deno.test("texto do WhatsApp: desconto geral oculto → '• Ajustes: −R$ 150,00'", () => {
  const t = semNbsp(resumo({ showDiscount: false }));
  assert(!t.includes("Desconto"));
  assert(t.includes("• Ajustes: −R$ 150,00"));
});

// ── Texto e PDF nunca divergem ─────────────────────────────────────────────────────────────

/** Os rótulos do quadro do PDF, na ordem, tirados do HTML. */
function rotulosDoPdf(data: PDFData, options: PDFOptions): string[] {
  const html = linhasDoResumo(data, options).linhas;
  return [...html.matchAll(/<tr><td style="[^"]*">([^<]+)<\/td>/g)].map((m) => m[1]);
}

for (const [nome, , opcoes] of CASOS) {
  Deno.test(`texto × PDF: ${nome} — as mesmas linhas, na mesma ordem`, () => {
    const data: PDFData = {
      ...ORCAMENTO,
      serviceOrder: { ...ORCAMENTO.serviceOrder, ...ORDEM, discount_services_pct: 0, discount_parts_pct: 0 },
    };
    const options = { ...DEFAULT_PDF_OPTIONS, ...opcoes };
    assertEquals(somaDoTexto(resumo(opcoes)).rotulos, rotulosDoPdf(data, options));
  });
}
