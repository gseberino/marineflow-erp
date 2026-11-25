import { assert, assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { comQuemPagouOBoleto, linhasDoExtratoNoResumo } from "./extrato.ts";
import { lerComandoDaAgenda } from "../_shared/agenda/comandos.ts";
import { baixasDePe, contasDaBaixaDePe } from "./secretario-boleto.ts";

const moeda = (v: number) => `R$ ${v.toFixed(2).replace(".", ",")}`;

Deno.test("nada a dizer: nenhuma linha, nenhuma ação", () => {
  const r = linhasDoExtratoNoResumo([], [], moeda);
  assertEquals(r.linhas, []);
  assertEquals(r.acoes, []);
});

Deno.test("lançados sozinhos: total, os 3 primeiros, o resto e como desfazer", () => {
  const l = (n: number, automatica = "confianca") => ({
    title: `Despesa: LOJA ${n}`, suggested_amount: 10 * n, suggested_category: "Combustível e deslocamento", automatica,
  });
  const r = linhasDoExtratoNoResumo([l(1, "regra"), l(2), l(3), l(4)], [], moeda);
  assertStringIncludes(r.linhas[0], "*4*");
  assertStringIncludes(r.linhas[0], "R$ 100,00");
  assertStringIncludes(r.linhas[1], "LOJA 1");
  assertStringIncludes(r.linhas[1], "sua regra");
  assert(!r.linhas.some((x) => x.includes("LOJA 4")), "só os 3 primeiros");
  assert(r.linhas.some((x) => x.includes("e mais 1")));
  assert(r.linhas.some((x) => x.includes("*desfazer*")));
  assertEquals(r.acoes.length, 1);
});

Deno.test("baixa pelo boleto (22/11/2026): aparece como conta baixada, não como despesa por confiança", () => {
  const r = linhasDoExtratoNoResumo([{
    title: "Despesa: TSD LOGISTICA", suggested_amount: 785.07, suggested_category: "Mercadorias", automatica: "boleto",
  }], [], moeda);
  assertStringIncludes(r.linhas[1], "R$ 785,07");
  assertStringIncludes(r.linhas[1], "conta baixada (boleto pago no banco)");
  assert(!r.linhas[1].includes("confiança alta"));
  assert(!r.linhas[1].includes("Mercadorias"), "a categoria sugerida da proposta não é a da conta");
});

// ─── Recebimento baixado pelo boleto (24/11/2026) ──────────────────────────────────────────────

const despesa = { title: "Despesa: POSTO IPIRANGA", suggested_amount: 100, suggested_category: "Combustível e deslocamento", automatica: "regra", kind: "create_payable", bank_transaction_id: "t-posto" };
const contaPaga = { title: "Despesa: TSD LOGISTICA", suggested_amount: 785.07, suggested_category: "Mercadorias", automatica: "boleto", kind: "create_payable", bank_transaction_id: "t-tsd" };
const recebido = (linha: string, valor: number, quem?: string) => ({
  title: "Receita: CREDITO DE BOLETO", suggested_amount: valor, suggested_category: null, automatica: "boleto", kind: "create_receivable",
  bank_transaction_id: linha, ...(quem ? { quem } : {}),
});

Deno.test("conta a pagar continua byte a byte: com kind e linha do banco na consulta, o texto é o de antes", () => {
  const antes = linhasDoExtratoNoResumo([
    { title: despesa.title, suggested_amount: 100, suggested_category: despesa.suggested_category, automatica: "regra" },
    { title: contaPaga.title, suggested_amount: 785.07, suggested_category: "Mercadorias", automatica: "boleto" },
  ], [], moeda);
  const agora = linhasDoExtratoNoResumo([despesa, contaPaga], [], moeda);
  assertEquals(agora, antes);
  assertEquals(agora.linhas, [
    "🤖 Lançados sozinhos nas últimas 24h: *2* (R$ 885,07)",
    "   • R$ 100,00 — POSTO IPIRANGA → Combustível e deslocamento (sua regra)",
    "   • R$ 785,07 — TSD LOGISTICA → conta baixada (boleto pago no banco)",
    "   Algo errado? Responda *desfazer* e diga qual — volta para a fila.",
  ]);
});

Deno.test("recebimento baixado pelo boleto: sai com o cliente, com a palavra própria e fora da soma", () => {
  const r = linhasDoExtratoNoResumo([recebido("t-1", 5237.99, "Apolo"), despesa, contaPaga], [], moeda);
  assertEquals(r.linhas, [
    "🤖 Lançados sozinhos nas últimas 24h: *3* (R$ 885,07, sem contar o recebimento baixado)",
    "   • R$ 5237,99 — Apolo → recebimento baixado (o cliente pagou o boleto). Não era? Diga *desfaz a baixa de Apolo*.",
    "   • R$ 100,00 — POSTO IPIRANGA → Combustível e deslocamento (sua regra)",
    "   • R$ 785,07 — TSD LOGISTICA → conta baixada (boleto pago no banco)",
    "   Algo errado? Responda *desfazer* e diga qual — volta para a fila.",
  ]);
  assert(!r.linhas[1].includes("conta baixada"), "recebimento não é conta a pagar");
  assert(!r.linhas[1].includes("CREDITO DE BOLETO"), "o título da fila não diz quem pagou");
  const dois = linhasDoExtratoNoResumo([recebido("t-1", 5237.99, "Apolo"), recebido("t-2", 5238.02, "Apolo"), despesa], [], moeda);
  assertEquals(dois.linhas[0], "🤖 Lançados sozinhos nas últimas 24h: *3* (R$ 100,00, sem contar os 2 recebimentos baixados)");
});

Deno.test("só recebimento baixado: o cabeçalho não inventa uma soma de R$ 0,00; sem o nome a linha diz 'cliente'", () => {
  const um = linhasDoExtratoNoResumo([recebido("t-1", 5237.99)], [], moeda);
  assertEquals(um.linhas[0], "🤖 Lançados sozinhos nas últimas 24h: *1* (recebimento baixado pelo boleto)");
  assertEquals(um.linhas[1], "   • R$ 5237,99 — cliente → recebimento baixado (o cliente pagou o boleto). Não era? Diga *desfaz a baixa* e o valor.");
  const dois = linhasDoExtratoNoResumo([recebido("t-1", 5237.99, "Apolo"), recebido("t-2", 5238.02, "Apolo")], [], moeda);
  assertEquals(dois.linhas[0], "🤖 Lançados sozinhos nas últimas 24h: *2* (recebimentos baixados pelo boleto)");
});

// (24/11/2026, revisão) "Responda *desfazer* e diga qual" + item identificado só pelo cliente = "desfazer Apolo", que é a
// palavra *desfaz <cliente>* da agenda (lida antes do assistente). A linha do recebimento ensina a frase que não colide.
Deno.test("recebimento baixado: a linha ensina 'desfaz a baixa de <nome>', que não é a palavra da agenda", () => {
  assertEquals(lerComandoDaAgenda("desfazer Apolo"), { comando: "desfazer", alvo: "apolo" });
  assertEquals(lerComandoDaAgenda("desfaz a baixa de Apolo"), null);
  assertEquals(lerComandoDaAgenda("*desfaz a baixa de Apolo*"), null);
  assertEquals(lerComandoDaAgenda("desfaz a baixa"), null);
  const r = linhasDoExtratoNoResumo([recebido("t-1", 5237.99, "Apolo")], [], moeda);
  assertEquals(r.linhas[1], "   • R$ 5237,99 — Apolo → recebimento baixado (o cliente pagou o boleto). Não era? Diga *desfaz a baixa de Apolo*.");
  // nunca "desfaz a baixa de cliente": sem o nome, o dono diz o valor
  const semNome = linhasDoExtratoNoResumo([recebido("t-1", 5237.99)], [], moeda);
  assert(!semNome.linhas.some((x) => x.includes("desfaz a baixa de")));
});

Deno.test("rodapé 'Responda *desfazer*': só quando há algo que foi LANÇADO; bloco só de recebimentos não o leva", () => {
  const RODAPE = "   Algo errado? Responda *desfazer* e diga qual — volta para a fila.";
  const soRecebidos = linhasDoExtratoNoResumo([recebido("t-1", 5237.99, "Apolo"), recebido("t-2", 5238.02, "Apolo")], [], moeda);
  assertEquals(soRecebidos.linhas, [
    "🤖 Lançados sozinhos nas últimas 24h: *2* (recebimentos baixados pelo boleto)",
    "   • R$ 5237,99 — Apolo → recebimento baixado (o cliente pagou o boleto). Não era? Diga *desfaz a baixa de Apolo*.",
    "   • R$ 5238,02 — Apolo → recebimento baixado (o cliente pagou o boleto). Não era? Diga *desfaz a baixa de Apolo*.",
  ]);
  assertEquals(soRecebidos.acoes, ["   • *O que foi lançado sozinho?*"]);
  // misto: o rodapé é o de sempre, no fim do bloco
  const misto = linhasDoExtratoNoResumo([recebido("t-1", 5237.99, "Apolo"), despesa], [], moeda);
  assertEquals(misto.linhas[misto.linhas.length - 1], RODAPE);
  // sem recebimento: o bloco de sempre, com o rodapé
  const semRecebido = linhasDoExtratoNoResumo([despesa, contaPaga], [], moeda);
  assertEquals(semRecebido.linhas[semRecebido.linhas.length - 1], RODAPE);
});

Deno.test("comQuemPagouOBoleto: põe o cliente da conta casada; a baixa desfeita (sem conta casada) não aparece", () => {
  const lancados = [recebido("t-1", 5237.99), recebido("t-2", 5238.02), despesa, contaPaga];
  const r = comQuemPagouOBoleto(lancados, [{ bank_transaction_id: "t-1", quem: "Apolo" }]);
  assertEquals(r, [{ ...recebido("t-1", 5237.99), quem: "Apolo" }, despesa, contaPaga]);
  const texto = linhasDoExtratoNoResumo(r, [], moeda).linhas;
  assert(texto.some((x) => x.includes("R$ 5237,99 — Apolo → recebimento baixado")));
  assert(!texto.some((x) => x.includes("5238,02")), "a desfeita não aparece");
  // todas desfeitas: sobram só os lançamentos de sempre, com o texto de sempre
  assertEquals(
    linhasDoExtratoNoResumo(comQuemPagouOBoleto(lancados, []), [], moeda),
    linhasDoExtratoNoResumo([despesa, contaPaga], [], moeda),
  );
  // conta casada sem cliente legível: a baixa aparece, sem o nome
  assertEquals(comQuemPagouOBoleto([recebido("t-1", 10)], [{ bank_transaction_id: "t-1", quem: null }]), [{ ...recebido("t-1", 10), quem: null }]);
});

Deno.test("comQuemPagouOBoleto: a leitura das contas falhou (null) = segue como veio, sem o nome", () => {
  const lancados = [recebido("t-1", 5237.99), despesa];
  assertEquals(comQuemPagouOBoleto(lancados, null), lancados);
  const texto = linhasDoExtratoNoResumo(comQuemPagouOBoleto(lancados, null), [], moeda).linhas;
  assertEquals(texto[1], "   • R$ 5237,99 — cliente → recebimento baixado (o cliente pagou o boleto). Não era? Diga *desfaz a baixa* e o valor.");
  assertEquals(texto[0], "🤖 Lançados sozinhos nas últimas 24h: *2* (R$ 100,00, sem contar o recebimento baixado)");
});

// (24/11/2026, revisão — "a marca que revive") O index.ts só passa em `casadas` a conta que o registro da linha diz ser
// a da baixa automática de pé (contasDaBaixaDePe). Desfeita e casada de novo à mão com outra conta = fora, como a desfeita.
Deno.test("comQuemPagouOBoleto + contasDaBaixaDePe: a linha desfeita e casada à mão com outro cliente não sai como recebimento baixado", () => {
  const lancados = [recebido("t-1", 5237.99), recebido("t-2", 5238.02), despesa, contaPaga];
  const contas = [
    { id: "r-1", bank_transaction_id: "t-1", quem: "Apolo" },
    { id: "r-beta", bank_transaction_id: "t-2", quem: "Estaleiro Beta" }, // o dono desfez a baixa de r-2 e casou t-2 com r-beta
  ];
  const dePe = baixasDePe([
    { bank_transaction_id: "t-1", receivable_id: "r-1", acao: "conciliou", detalhe: "Baixa automática pelo boleto · NF-e 2/25" },
    { bank_transaction_id: "t-2", receivable_id: "r-2", acao: "conciliou", detalhe: "Baixa automática pelo boleto · NF-e 2/25" },
    { bank_transaction_id: "t-2", receivable_id: "r-2", acao: "desconciliou", detalhe: null },
    { bank_transaction_id: "t-2", receivable_id: "r-beta", acao: "conciliou", detalhe: null },
  ]);
  const r = comQuemPagouOBoleto(lancados, contasDaBaixaDePe(contas, dePe));
  assertEquals(r, [{ ...recebido("t-1", 5237.99), quem: "Apolo" }, despesa, contaPaga]);
  const texto = linhasDoExtratoNoResumo(r, [], moeda).linhas;
  assert(!texto.some((x) => x.includes("Estaleiro Beta")), "o casamento à mão não é baixa automática");
  assert(!texto.some((x) => x.includes("5238,02")));
  // a conta a PAGAR baixada pelo boleto não passa pelo registro: continua como estava
  assert(texto.some((x) => x.includes("TSD LOGISTICA → conta baixada (boleto pago no banco)")));
});

Deno.test("comQuemPagouOBoleto: conta a PAGAR baixada pelo boleto e linha sem kind não passam pelo filtro", () => {
  const semKind = { title: "Receita: CREDITO DE BOLETO", suggested_amount: 50, suggested_category: null, automatica: "boleto" };
  assertEquals(comQuemPagouOBoleto([contaPaga, semKind], []), [contaPaga, semKind]);
});

Deno.test("débito sem loja: pergunta com data e valor, o mais recente de exemplo", () => {
  const r = linhasDoExtratoNoResumo([], [
    { suggested_amount: 45, suggested_date: "2026-09-20" },
    { suggested_amount: 8.9, suggested_date: "2026-09-24" },
  ], moeda, { anoAtual: 2026 });
  assertStringIncludes(r.linhas[0], "*2*");
  assertStringIncludes(r.linhas[1], "24/09");
  assertStringIncludes(r.linhas[1], "R$ 8,90");
  assertStringIncludes(r.linhas[2], "20/09");
  // Valor com centavos e data inteira: é o que a anotação precisa para casar.
  assertStringIncludes(r.linhas[3], "o débito de R$ 8,90 de 24/09");
});

Deno.test("débito de outro ano leva o ano; os já respondidos são contados à parte", () => {
  const r = linhasDoExtratoNoResumo([], [{ suggested_amount: 49.95, suggested_date: "2025-08-30" }], moeda,
    { anoAtual: 2026, anotadosEsperando: 2 });
  assertStringIncludes(r.linhas[1], "30/08/2025");
  assertStringIncludes(r.linhas[2], "o débito de R$ 49,95 de 30/08/2025");
  assertStringIncludes(r.linhas[3], "2 que você já respondeu");
});

Deno.test("anotação que a varredura cancelou aparece com o motivo", () => {
  const r = linhasDoExtratoNoResumo([], [], moeda, { naoAplicadas: [
    { valor: 700, quem: "TSD", motivo: "chegaram 2 transações do mesmo valor; diga qual pela tela" },
  ] });
  assertStringIncludes(r.linhas[0], "não pude aplicar: *1*");
  assertStringIncludes(r.linhas[1], "R$ 700,00 · TSD — chegaram 2 transações");
});
