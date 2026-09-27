import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { fotoDeQuemUsaOFinanceiro, legendaDaMidia, lerComprovante, mensagemDoComprovante, semODocumentoDaEmpresa } from "./comprovante.ts";

Deno.test("legenda: o marcador e o nome do arquivo não são legenda", () => {
  assertEquals(["[image]", "[document]", "[documento] nota.pdf", "comprovante.pdf", "IMG_2031.JPG", "", null, undefined].map(legendaDaMidia),
    [null, null, null, null, null, null, null, null]);
  assertEquals(legendaDaMidia("  almoço da equipe, OS-60  "), "almoço da equipe, OS-60");
  assertEquals(legendaDaMidia("nota do posto.pdf"), "nota do posto.pdf");
});

Deno.test("comprovante: só a foto de quem usa o financeiro é lida (a do técnico é do serviço)", () => {
  assertEquals(["admin", "financial", "technician", "seller", null, undefined].map((c) => fotoDeQuemUsaOFinanceiro(c)),
    [true, true, false, false, false, false]);
});

Deno.test("comprovante: lê a linha fixa e os itens", () => {
  const c = lerComprovante(`COMPROVANTE | loja: POSTO BR ITAJAI | cnpj: 12.345.678/0001-90 | data: 26/09/2026 | total: 64,80 | pagamento: débito
- Gasolina comum | R$ 64,80`);
  assertEquals(c, {
    loja: "POSTO BR ITAJAI", cnpj: "12345678000190", data: "2026-09-26", total: 64.8, pagamento: "debito",
    itens: ["- Gasolina comum | R$ 64,80"],
  });
});

Deno.test("comprovante: 'não informado' vira null, sem inventar", () => {
  const c = lerComprovante("COMPROVANTE | loja: não informado | cnpj: não informado | data: não informada | total: 1.234,56 | pagamento: não informado");
  assertEquals(c, { loja: null, cnpj: null, data: null, total: 1234.56, pagamento: null, itens: [] });
});

Deno.test("comprovante: data impossível e valor ilegível não passam", () => {
  const c = lerComprovante("COMPROVANTE | loja: X | cnpj: 123 | data: 31/02/2026 | total: sessenta | pagamento: pix");
  assertEquals([c?.data, c?.total, c?.cnpj, c?.pagamento], [null, null, null, "pix"]);
});

Deno.test("comprovante: CPF de quem recebeu o Pix vale (acha o favorecido); o CNPJ da própria empresa sai", () => {
  const pix = lerComprovante("COMPROVANTE | loja: ROBERTO D R CORREA | cnpj: 123.456.789-01 | data: 25/09/2026 | total: 150,00 | pagamento: pix")!;
  assertEquals(pix.cnpj, "12345678901");
  assertEquals(mensagemDoComprovante(pix, null).split("\n")[0].replace(/ /g, " "),
    "📷 Comprovante enviado por foto: R$ 150,00 em ROBERTO D R CORREA (CPF 123.456.789-01), em 25/09/2026, pago por Pix.");
  // O modelo pegou o CNPJ de quem PAGOU (a HBR, raiz 50057049): não identifica ninguém.
  const errado = lerComprovante("COMPROVANTE | loja: LOJA X | cnpj: 50.057.049/0001-10 | data: 25/09/2026 | total: 90,00 | pagamento: pix")!;
  assertEquals(semODocumentoDaEmpresa(errado, "50057049").cnpj, null);
  assertEquals(semODocumentoDaEmpresa(pix, "50057049").cnpj, "12345678901");
  assertEquals(semODocumentoDaEmpresa(errado, null).cnpj, "50057049000110");
});

Deno.test("comprovante: nota a prazo não é pagamento, e a linha dela não se perde no corte de 5 itens", () => {
  const c = lerComprovante(`COMPROVANTE | loja: DISTRIBUIDORA X | cnpj: 12.345.678/0001-90 | data: 20/09/2026 | total: 3.400,00 | pagamento: boleto
- Cabo 16mm | R$ 900,00
- Disjuntor | R$ 500,00
- Barramento | R$ 800,00
- Terminal | R$ 200,00
- Fita | R$ 50,00
- compra a prazo | vencimentos: 20/10/2026, 20/11/2026`)!;
  assertEquals(c.pagamento, null);
  assertEquals(c.itens.length, 5);
  assertEquals(c.itens[0], "- compra a prazo | vencimentos: 20/10/2026, 20/11/2026");
});

Deno.test("comprovante: Pix no crédito é lido à parte (chega na fatura sem nome, como o débito)", () => {
  const c = lerComprovante("COMPROVANTE | loja: FULANO DE TAL | cnpj: 123.456.789-01 | data: 06/04/2026 | total: 395,00 | pagamento: pix no crédito")!;
  assertEquals(c.pagamento, "pix_credito");
  assertEquals(mensagemDoComprovante(c, null).includes("pago por Pix no crédito"), true);
});

Deno.test("comprovante: imagem que não é comprovante não vira nada", () => {
  assertEquals(lerComprovante("- Bateria 105Ah | unitário: R$ 890,00 | prazo: 5 dias"), null);
  assertEquals(lerComprovante(""), null);
});

Deno.test("comprovante: o marcador da imagem na frente não atrapalha", () => {
  assertEquals(lerComprovante("📷 COMPROVANTE | loja: A | cnpj: não informado | data: 01/09/26 | total: 10,00 | pagamento: dinheiro")?.data, "2026-09-01");
});

Deno.test("comprovante: a mensagem para o assistente diz o que a foto diz, com a legenda", () => {
  const c = lerComprovante(`COMPROVANTE | loja: POSTO BR ITAJAI | cnpj: 12345678000190 | data: 26/09/2026 | total: 64,80 | pagamento: débito
- Gasolina comum | R$ 64,80`)!;
  const m = mensagemDoComprovante(c, "abasteci o carro da empresa");
  assertEquals(m.split("\n")[0].replace(/ /g, " "),
    "📷 Comprovante enviado por foto: R$ 64,80 em POSTO BR ITAJAI (CNPJ 12.345.678/0001-90), em 26/09/2026, pago no débito.");
  assertEquals(m.includes("Itens: Gasolina comum | R$ 64,80"), true);
  assertEquals(m.includes("Legenda: abasteci o carro da empresa"), true);
  // Sem legenda de verdade ("[image]", ou o nome do PDF), não repete o marcador.
  assertEquals(mensagemDoComprovante(c, "[image]").includes("Legenda"), false);
  assertEquals(mensagemDoComprovante(c, "comprovante_pix.pdf").includes("Legenda"), false);
});
