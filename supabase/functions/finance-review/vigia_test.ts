// O vigilante de despesas sem o "parou" falso (frente B, 21/10/2026).
// As linhas do Gustavo, da COREMMA e da UNIFIQUE são do extrato real (SELECT de 21/10/2026, só as colunas
// que o vigilante lê); os dois casos montados dizem no nome que são montados.
// Rodar com:
//   deno test --allow-all --no-check --node-modules-dir=none supabase/functions/finance-review/vigia_test.ts
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { alertasDoVigia, type LinhaDoVigia } from "./vigia.ts";

let seq = 0;
function linha(o: Partial<LinhaDoVigia> & { transaction_date: string; amount: number }): LinhaDoVigia {
  seq += 1;
  return {
    id: `tx-${String(seq).padStart(4, "0")}`,
    description: null, counterparty_name: null, counterparty_document: null, merchant_name: null, merchant_document: null,
    dismissed_kind: null, installment_label: null, source_type: "bank",
    ...o,
  };
}
const ordenar = (l: LinhaDoVigia[]) => [...l].sort((a, b) => a.transaction_date.localeCompare(b.transaction_date) || a.id.localeCompare(b.id));
const paradas = (l: LinhaDoVigia[], hoje: string) =>
  alertasDoVigia(ordenar(l), new Date(`${hoje}T12:00:00Z`)).filter((a) => a.tipo === "parou");

// ── Gustavo: o CPF 104.162.949-44 e o cartão com o nome inteiro, sem documento ─────────────────────────
const CPF_GUSTAVO = "10416294944";
const pix = (data: string, valor: number) => linha({
  transaction_date: data, amount: valor, description: "Pix enviado para Gustavo Seberino da Silva", counterparty_document: CPF_GUSTAVO,
});
const cartaoGustavo = (data: string, valor: number) => linha({
  transaction_date: data, amount: valor, description: "Gustavo Seberino da Silva", counterparty_name: "Gustavo Seberino da Silva",
  source_type: "credit_card",
});
const GUSTAVO = [
  cartaoGustavo("2026-06-09", 56.04),
  linha({ transaction_date: "2026-06-09", amount: 50, description: "Transferência enviada|Gustavo Seberino da Silva",
    counterparty_name: "GUSTAVO SEBERINO", counterparty_document: CPF_GUSTAVO }),
  cartaoGustavo("2026-06-28", 52.38),
  cartaoGustavo("2026-07-26", 84.56),
  pix("2026-08-04", 200), pix("2026-08-08", 100), pix("2026-08-10", 150),
  cartaoGustavo("2026-08-15", 329.37),
  pix("2026-08-16", 300), pix("2026-09-22", 200), pix("2026-09-27", 200), pix("2026-09-27", 300), pix("2026-09-30", 50),
];

Deno.test("Gustavo: o nome do cartão é o mesmo nome do Pix com CPF — não 'parou' (aviso de 01/10)", () => {
  // O aviso real d82e026d: "Gustavo Seberino da Silva aparecia todo mês e parou (último em 15/08)" — com Pix
  // para o mesmo CPF em 22/09, 27/09 (dois) e 30/09.
  assertEquals(paradas(GUSTAVO, "2026-10-01"), []);
});

Deno.test("nome parecido não junta: 'GUSTAVO SEBERINO' sem documento não é o 'Gustavo Seberino da Silva' do CPF", () => {
  // 16 letras não é corte do banco (o Pix corta em ~30): é outro nome, e o vigilante não liga nomes diferentes.
  const cartaoCurto = (data: string) => linha({ transaction_date: data, amount: 60, counterparty_name: "GUSTAVO SEBERINO", source_type: "credit_card" });
  const l = [cartaoCurto("2026-06-10"), cartaoCurto("2026-07-10"), cartaoCurto("2026-08-10"), pix("2026-09-22", 200), pix("2026-09-30", 50)];
  const p = paradas(l, "2026-10-01");
  assertEquals(p.length, 1);
  assertEquals(p[0].chave, "vigia:parou:nome:gustavo seberino:2026-10");
});

Deno.test("nome com dois documentos que não se confirmam não junta com nenhum (montado)", () => {
  const cartao = (data: string) => linha({ transaction_date: data, amount: 80, counterparty_name: "MARIA SOUZA", source_type: "credit_card" });
  const l = [
    cartao("2026-06-12"), cartao("2026-07-12"), cartao("2026-08-12"),
    linha({ transaction_date: "2026-09-20", amount: 300, counterparty_name: "MARIA SOUZA", counterparty_document: "11111111111" }),
    linha({ transaction_date: "2026-09-25", amount: 300, counterparty_name: "MARIA SOUZA", counterparty_document: "22222222222" }),
  ];
  const p = paradas(l, "2026-10-01");
  assertEquals(p.map((a) => a.chave), ["vigia:parou:nome:maria souza:2026-10"]);
});

Deno.test("nome cortado pelo banco (Pix no limite de 30 letras) é o mesmo do CNPJ (montado)", () => {
  const cortado = (data: string) => linha({ transaction_date: data, amount: 900, counterparty_name: "MARINE EXPRESS COMERCIAL IMPOR" });
  const l = [
    cortado("2026-06-03"), cortado("2026-07-03"), cortado("2026-08-03"),
    linha({ transaction_date: "2026-09-25", amount: 900, counterparty_name: "MARINE EXPRESS COMERCIAL IMPORTADORA LTDA",
      counterparty_document: "68904101000120" }),
  ];
  assertEquals(paradas(l, "2026-10-01"), []);
});

Deno.test("'Compra no débito|POSTO PAULINHO' é o mesmo 'POSTO PAULINHO' do cartão — não 'parou' (revisão de 22/10)", () => {
  // O formato real do Nubank pela Pluggy: o nome da loja depois da barra, sem nome da contraparte (18–19/08/2026).
  const cartao = (data: string) => linha({
    transaction_date: data, amount: 120, description: "POSTO PAULINHO         NAVEGANTES    BRA", counterparty_name: "POSTO PAULINHO",
    source_type: "credit_card",
  });
  const debito = (data: string, loja: string) => linha({ transaction_date: data, amount: 51.68, description: `Compra no débito|${loja}` });
  const cartoes = [cartao("2026-06-05"), cartao("2026-07-05"), cartao("2026-08-05")];
  assertEquals(paradas([...cartoes, debito("2026-09-20", "POSTO PAULINHO")], "2026-10-01"), []);
  // Nome diferente continua outro grupo: "POSTO PAULINHO II" no débito não diz que o do cartão voltou.
  const p = paradas([...cartoes, debito("2026-09-20", "POSTO PAULINHO II")], "2026-10-01");
  assertEquals(p.map((a) => a.chave), ["vigia:parou:nome:posto paulinho:2026-10"]);
});

// ── COREMMA: as parcelas da compra de 13/08 continuam saindo ─────────────────────────────────────────
const coremma = (data: string, valor: number, o: Partial<Omit<LinhaDoVigia, "amount">> = {}) => linha({
  transaction_date: data, amount: valor, description: "COREMMA                BALNEARIO CAM BRA", counterparty_name: "COREMMA",
  source_type: "credit_card", ...o,
});
const COREMMA = [
  coremma("2026-06-05", 27.40),
  coremma("2026-06-25", 102.40, { description: "COREMMA                ITAJAI        BRA", installment_label: "10/10" }),
  coremma("2026-06-26", 98.00, { source_type: "bank" }),
  coremma("2026-06-26", 98.00, { source_type: "bank", dismissed_kind: "duplicata" }),
  coremma("2026-07-28", 309.96, { installment_label: "1/2" }),
  coremma("2026-08-01", 120.50),
  coremma("2026-08-13", 112.30, { description: "Coremma 1/4", counterparty_name: "Coremma 1/4", installment_label: "1/4" }),
  coremma("2026-08-25", 309.95, { installment_label: "2/2", dismissed_kind: "parcela" }),
  coremma("2026-09-03", 112.29, { description: "Coremma 2/4", counterparty_name: "Coremma 2/4", installment_label: "2/4", dismissed_kind: "parcela" }),
  coremma("2026-09-13", 112.29, { description: "Coremma 2/4", counterparty_name: "Coremma 2/4", installment_label: "2/4", dismissed_kind: "parcela" }),
];

Deno.test("COREMMA: a parcela 2/4 saiu em setembro — a loja não 'parou' de aparecer (aviso de 01/10)", () => {
  // O aviso real c2c583cb: "COREMMA aparecia todo mês e parou (último em 01/08)".
  assertEquals(paradas(COREMMA, "2026-10-01"), []);
});

Deno.test("parcelamento que terminou não é recorrência que parou (montado)", () => {
  // Uma compra em 10x: aparece todo mês até a 10/10 e some. É o fim do parcelamento, não um corte.
  const parcela = (data: string, n: number) => linha({
    transaction_date: data, amount: 250, counterparty_name: "NAUTICA DO PORTO", installment_label: `${n}/10`, source_type: "credit_card",
  });
  const l = [parcela("2026-06-05", 6), parcela("2026-07-05", 7), parcela("2026-08-05", 8), parcela("2026-09-05", 9), parcela("2026-10-05", 10)];
  assertEquals(paradas(l, "2026-11-15"), []);
});

Deno.test("parcela escrita no nome ('Coremma 2/4') é a mesma loja; '24/7' no nome não é parcela", () => {
  const loja = (data: string, nome: string) => linha({ transaction_date: data, amount: 40, counterparty_name: nome, source_type: "credit_card" });
  // Três meses de "LOJA 24/7": é o nome da loja, não a parcela 24 de 7. Continua um grupo só, e parou.
  const p = paradas([loja("2026-06-01", "LOJA 24/7"), loja("2026-07-01", "LOJA 24/7"), loja("2026-08-01", "LOJA 24/7")], "2026-10-01");
  assertEquals(p.map((a) => a.chave), ["vigia:parou:nome:loja 24 7:2026-10"]);
});

// ── UNIFIQUE: mensal pelo CNPJ, e o último pagamento foi em 09/09 ─────────────────────────────────────
const unifique = (data: string, valor: number, o: Partial<Omit<LinhaDoVigia, "amount">> = {}) => linha({
  transaction_date: data, amount: valor, description: "UNIFIQUE TELECOMUNICACOES S/A", counterparty_name: "UNIFIQUE TELECOMUNICACOES S/A",
  counterparty_document: "02255187000108", ...o,
});
const UNIFIQUE = [
  unifique("2026-04-22", 163.09), unifique("2026-05-21", 163.04),
  unifique("2026-05-21", 163.04, { counterparty_document: null, dismissed_kind: "duplicata" }),
  unifique("2026-06-23", 163.14), unifique("2026-07-20", 159.80),
  unifique("2026-09-09", 164.05, { description: "Transferência enviada|UNIFIQUE TELECOMUNICACOES S/" }),
];

Deno.test("mensalidade que parou de verdade continua avisando, com a mesma chave (aviso de 15/10)", () => {
  // O aviso real 30b31f9f tem a chave vigia:parou:doc:02255187000108:2026-10 — a mesma, para o "já avisado" valer.
  const p = paradas(UNIFIQUE, "2026-10-15");
  assertEquals(p.map((a) => a.chave), ["vigia:parou:doc:02255187000108:2026-10"]);
  assert(p[0].titulo.includes("último em 09/09"));
});

Deno.test("os outros olhares não mudam para quem já era um grupo só (valor fora do padrão pelo CPF)", () => {
  // Roberto: Pix pelo CPF, 3 anteriores de ~R$ 66 e um de R$ 390 — o aviso de valor continua saindo igual.
  const roberto = (data: string, valor: number) => linha({
    transaction_date: data, amount: valor, description: "Pix enviado para Roberto Daniel Rodrigues Corrêa", counterparty_document: "12345678909",
  });
  const a = alertasDoVigia(ordenar([roberto("2026-07-01", 60), roberto("2026-08-01", 66), roberto("2026-09-01", 70), roberto("2026-10-06", 390)]),
    new Date("2026-10-08T12:00:00Z"));
  const valor = a.filter((x) => x.tipo === "valor");
  assertEquals(valor.length, 1);
  assert(valor[0].chave.startsWith("vigia:valor:"));
});

// ── Segunda revisão (22/10/2026) ─────────────────────────────────────────────────────────────────────

Deno.test("parcelamento interrompido no meio (6/10 e nada mais) continua avisando — só o que chegou ao n/n é fim (montado)", () => {
  // Estorno, cancelamento, cartão bloqueado: faltavam 4 parcelas e elas não vieram. O vigia antigo avisava.
  const parcela = (data: string, n: number) => linha({
    transaction_date: data, amount: 250, counterparty_name: "NAUTICA DO PORTO", installment_label: `${n}/10`, source_type: "credit_card",
  });
  const l = [parcela("2026-05-05", 3), parcela("2026-06-05", 4), parcela("2026-07-05", 5), parcela("2026-08-05", 6)];
  assertEquals(paradas(l, "2026-10-21").map((a) => a.chave), ["vigia:parou:nome:nautica do porto:2026-10"]);
});

Deno.test("parcela explicada de OUTRA compra não esconde a mensalidade que parou (montado)", () => {
  // A mensalidade de R$ 99,90 parou em 10/08; as parcelas 2/4 e 3/4 que seguem são de uma compra que não
  // está entre os pagamentos que contaram (a 1/4 não aparece).
  const mensal = ["2026-05-10", "2026-06-10", "2026-07-10", "2026-08-10"].map((d) => linha({
    transaction_date: d, amount: 99.9, counterparty_name: "MARINA SOFT", counterparty_document: "11222333000181",
  }));
  const explicada = (data: string, n: number) => linha({
    transaction_date: data, amount: 300, counterparty_name: `MARINA SOFT ${n}/4`, installment_label: `${n}/4`, dismissed_kind: "parcela",
    source_type: "credit_card",
  });
  const p = paradas([...mensal, explicada("2026-09-12", 2), explicada("2026-10-12", 3)], "2026-10-21");
  assertEquals(p.map((a) => a.chave), ["vigia:parou:doc:11222333000181:2026-10"]);
  // Quando a compra É um dos pagamentos que contaram (a 1/4 em agosto), as parcelas dela dizem que o dinheiro
  // continua indo para o mesmo recebedor: não "parou" (o caso da COREMMA).
  const inicio = linha({
    transaction_date: "2026-08-12", amount: 300, counterparty_name: "MARINA SOFT 1/4", installment_label: "1/4", source_type: "credit_card",
  });
  assertEquals(paradas([...mensal, inicio, explicada("2026-09-12", 2), explicada("2026-10-12", 3)], "2026-10-21"), []);
});

Deno.test("Google One 'parou', mas há cobrança do mesmo valor com outro nome: o aviso pergunta, não junta (extrato real)", () => {
  // SELECT de 22/10/2026: Google One R$ 96,99 em 01/06 e 20/07 (CNPJ 06990590000123) e 21/08 (sem documento);
  // nada em setembro; "Google G1ai101m" R$ 96,99 em 14/10. Nome diferente nunca identifica: os grupos não se
  // juntam, e a chave do aviso continua a mesma — mas o dono fica sabendo que parece a mesma cobrança.
  const comDoc = (data: string) => linha({
    transaction_date: data, amount: 96.99, description: "Google One", counterparty_name: "Google One", counterparty_document: "06990590000123",
    merchant_name: "GOOGLE BRASIL INTERNET LTDA.", merchant_document: "06990590000123", source_type: "credit_card",
  });
  const l = [
    comDoc("2026-06-01"), comDoc("2026-07-20"),
    linha({ transaction_date: "2026-08-21", amount: 96.99, description: "Google One", counterparty_name: "Google One", source_type: "credit_card" }),
    linha({ transaction_date: "2026-10-14", amount: 96.99, description: "Google G1ai101m", counterparty_name: "Google G1ai101m", source_type: "credit_card" }),
  ];
  const p = paradas(l, "2026-10-22");
  assertEquals(p.map((a) => a.chave), ["vigia:parou:doc:06990590000123:2026-10"]);
  assert(p[0].motivo.includes("Parece ser a mesma cobrança com outro nome (Google G1ai101m, 14/10): confira."), p[0].motivo);
  // As três condições da pista, cada uma barrando um caso (o extrato de 01/03 a 22/10/2026 tinha os três):
  const semPista = (l: LinhaDoVigia[], chave: string) => {
    const q = paradas(l, "2026-10-22");
    assertEquals(q.map((a) => a.chave), [chave]);
    assert(!q[0].motivo.includes("Parece ser"), q[0].motivo);
  };
  const pix = (data: string, valor: number, nome: string, cpf: string) => linha({
    transaction_date: data, amount: valor, description: `Pix enviado para ${nome}`, counterparty_document: cpf,
  });
  // 1. Valor que não está em todos os meses que contaram não é cobrança fixa.
  const oficina = (data: string, valor: number) => linha({ transaction_date: data, amount: valor, counterparty_name: "OFICINA DO CAIS", source_type: "credit_card" });
  semPista([oficina("2026-06-03", 180.5), oficina("2026-07-09", 95.3), oficina("2026-08-14", 200.4),
    pix("2026-10-10", 200.4, "Maria Souza", "11111111111")], "vigia:parou:nome:oficina do cais:2026-10");
  // 2. Valor redondo é o valor de qualquer um: o R$ 100 do posto todo mês e o Pix de R$ 100 a um freelancer novo
  //    (POSTO THIAVAN × freelancers de julho–agosto/2026, no extrato real).
  const posto = (data: string) => linha({ transaction_date: data, amount: 100, counterparty_name: "POSTO THIAVAN", source_type: "credit_card" });
  semPista([posto("2026-06-10"), posto("2026-07-10"), posto("2026-08-10"), pix("2026-10-10", 100, "Milenna Silva Padilha", "22222222222")],
    "vigia:parou:nome:posto thiavan:2026-10");
  // 3. O outro nome tem de ser NOVO: quem já recebia antes do último pagamento é outra pessoa de sempre.
  const tv = (data: string) => linha({ transaction_date: data, amount: 89.9, counterparty_name: "TV DO CAIS", source_type: "credit_card" });
  semPista([pix("2026-05-20", 89.9, "Maria Souza", "11111111111"), tv("2026-06-10"), tv("2026-07-10"), tv("2026-08-10"),
    pix("2026-10-10", 89.9, "Maria Souza", "11111111111")], "vigia:parou:nome:tv do cais:2026-10");
});

Deno.test("nome igual é o nome INTEIRO: dois nomes que só diferem depois da 40ª letra não se juntam (montado)", () => {
  // Pai e filho: o cartão sem documento do NETO não é o Pix com CPF do FILHO.
  const neto = (data: string) => linha({
    transaction_date: data, amount: 500, counterparty_name: "JOAO CARLOS DOS SANTOS PEREIRA DA SILVA NETO", source_type: "credit_card",
  });
  const l = [neto("2026-06-03"), neto("2026-07-03"), neto("2026-08-03"),
    linha({ transaction_date: "2026-10-10", amount: 500, counterparty_name: "JOAO CARLOS DOS SANTOS PEREIRA DA SILVA FILHO", counterparty_document: "12345678909" })];
  const p = paradas(l, "2026-10-21");
  assertEquals(p.length, 1);
  assert(p[0].chave.startsWith("vigia:parou:nome:joao carlos dos santos pereira da silva"), p[0].chave);
  // O mesmo nome inteiro, com documento numa linha e sem na outra, continua junto (o caso do Gustavo).
  const filhoSemDoc = (data: string) => linha({
    transaction_date: data, amount: 500, counterparty_name: "JOAO CARLOS DOS SANTOS PEREIRA DA SILVA FILHO", source_type: "credit_card",
  });
  assertEquals(paradas([filhoSemDoc("2026-06-03"), filhoSemDoc("2026-07-03"), filhoSemDoc("2026-08-03"), l[3]], "2026-10-21"), []);
});
