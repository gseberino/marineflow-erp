// O lote semanal da papelada (secretário, Passo 5): cada motivo de entrada, cada motivo de ficar fora, a ordem, a
// numeração, a impressão e os minutos — com linhas no formato da fila de produção (16/10/2026).
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  aceitacaoPorCategoria, chavesDoRecebedor, type DecisaoPassada, decidir, escolhasPorRecebedor, impressaoDa, type LinhaDaFila,
  minutosDoLote, montarLote, nomeCurto, tituloDoAviso,
} from "./lote.ts";

let seq = 0;
function linha(p: Partial<LinhaDaFila> & { quem?: string; doc?: string | null; desc?: string }): LinhaDaFila {
  seq += 1;
  const id = `00000000-0000-4000-8000-${String(seq).padStart(12, "0")}`;
  return {
    id, kind: "create_payable", title: `Despesa: ${p.quem ?? "X"}`, suggested_amount: 100, suggested_date: "2026-10-10",
    suggested_category: "Pagamento de fatura de cartão", confidence: 95, applied_rule_id: null, regra_origem: null,
    bank_transaction_id: `10000000-0000-4000-8000-${String(seq).padStart(12, "0")}`,
    tx: { counterparty_name: p.quem ?? "PGTO FAT CARTAO C6", counterparty_document: p.doc ?? null, description: p.desc ?? p.quem ?? "PGTO FAT CARTAO C6", transaction_date: "2026-10-10" },
    tx_lancada: false, fila_da_tx: null, alertas_na_tx: 0,
    ...p,
  };
}

function decisao(sug: string, fin: string, quem = "ALGUEM", em = "2026-09-20T12:00:00Z", doc: string | null = null): DecisaoPassada {
  return { em, sug, fin, kind: "create_payable", counterparty_name: quem, counterparty_document: doc, description: quem };
}

// o histórico medido de produção, resumido: fatura 15/15, juros 7/7, Posto Paulinho trocado 6 vezes
const HISTORICO: DecisaoPassada[] = [
  ...Array.from({ length: 15 }, (_, i) => decisao("Pagamento de fatura de cartão", "Pagamento de fatura de cartão", `BANCO ${i}`)),
  ...Array.from({ length: 7 }, (_, i) => decisao("Juros e encargos", "Juros e encargos", `JUROS ${i}`)),
  ...Array.from({ length: 6 }, (_, i) => decisao("Combustível e deslocamento", "Alimentação de campo", "Posto Paulinho", `2026-09-2${i}T12:00:00Z`)),
  ...Array.from({ length: 5 }, (_, i) => decisao("Pró-labore", i < 2 ? "Pró-labore" : "Retirada de sócio", `SOCIO ${i}`)),
];
const CTX = { limite: 500, historico: HISTORICO };
const medidas = () => ({ aceitacao: aceitacaoPorCategoria(HISTORICO), escolhas: escolhasPorRecebedor(HISTORICO) });

Deno.test("entra: a categoria que o dono nunca troca (15 de 15), com o número na linha", () => {
  const d = decidir(linha({}), CTX, medidas());
  assertEquals(d, { entra: true, codigo: "categoria", motivo: "15 de 15 sem troca" });
});

Deno.test("entra: anotação do dono (vence o histórico do recebedor) e regra DELE; a regra aprendida não basta", () => {
  const anot = linha({
    quem: "Pix enviado para ELIANE APARECIDA UBERTI", doc: "00000000191", suggested_category: "Alimentação de campo", suggested_amount: 493,
    evidencia: { anotacao: { id: "a1" } }, anotacao: { descricao: "Alimentação minha e dos freelancers", criada_em: "2026-10-06T15:00:00Z", categoria: "Alimentação de campo" },
  });
  assertEquals(decidir(anot, CTX, medidas()), { entra: true, codigo: "anotacao", motivo: "você anotou em 06/10" });
  const regra = linha({ quem: "NU PAGAMENTOS", applied_rule_id: "r1", regra_origem: "user", suggested_category: "Peças e materiais" });
  assertEquals(decidir(regra, CTX, medidas()).codigo, "regra");
  const aprendida = linha({ quem: "LOJA NOVA", applied_rule_id: "r2", regra_origem: "ai", suggested_category: "Peças e materiais" });
  assertEquals(decidir(aprendida, CTX, medidas()), { entra: false, codigo: "sem_historico", motivo: "ainda sem histórico para decidir" });
});

Deno.test("fora: contradiz a última escolha do dono para o mesmo recebedor (Posto Paulinho)", () => {
  const posto = linha({ quem: "Posto Paulinho", suggested_category: "Combustível e deslocamento", suggested_amount: 27.98 });
  assertEquals(decidir(posto, CTX, medidas()), { entra: false, codigo: "contradiz", motivo: "nas 6 últimas vezes você lançou como Alimentação de campo" });
});

Deno.test("fora: o limite de lote é o do servidor (500 fica fora, 499,99 entra)", () => {
  assertEquals(decidir(linha({ suggested_amount: 500 }), CTX, medidas()).codigo, "acima_do_limite");
  assertEquals(decidir(linha({ suggested_amount: 499.99 }), CTX, medidas()).codigo, "categoria");
});

Deno.test("fora: conflitos e o que só o dono sabe, cada um com o seu motivo", () => {
  const m = medidas();
  const casos: Array<[Partial<LinhaDaFila> & { quem?: string; doc?: string | null; desc?: string }, string]> = [
    [{ tx_lancada: true }, "ja_lancado"],
    [{ fila_da_tx: "create_payable:approved" }, "ja_lancado"],
    [{ vinculo_sugerido: { principal: { tipo: "payable", rotulo: "Pagamento já lançado: Fatura", jaLancado: true, confianca: 80, diferenca: 0 } as never, alternativas: [] } }, "vinculo"],
    [{ suggested_service_order_id: "os1" }, "os_oc"],
    [{ alertas_na_tx: 1 }, "com_aviso"],
    [{ do_comprovante: true }, "comprovante"],
    [{ quem: "DEBITO DE CARTAO", desc: "DEBITO DE CARTAO", suggested_category: "Outras despesas" }, "sem_loja"],
    [{ quem: "ADRIAN BENJAMIN", doc: "12472109954", suggested_category: "Outras despesas" }, "sem_categoria"],
    [{ quem: "JOSE CARLOS ABEL", doc: "00000000272", suggested_category: "Serviços de terceiros" }, "terceiro"],
    [{ quem: "Pix enviado para Gustavo", doc: "00000000353", suggested_category: "Pró-labore", suggested_amount: 50 }, "sem_historico"],
  ];
  for (const [p, codigo] of casos) assertEquals(decidir(linha(p), CTX, m).codigo, codigo, JSON.stringify(p));
});

Deno.test("entradas: SEMPRE fora — sinal já lançado (o caso dos R$ 10.469,50), sem cliente, com cliente", () => {
  const m = medidas();
  const nelson = linha({
    kind: "create_receivable", quem: "Pix recebido de NELSON A B SOUZA", doc: "24755150078", suggested_amount: 7600, suggested_category: "Outras receitas",
    vinculo_sugerido: { principal: { tipo: "existing_payment", rotulo: "Pagamento já lançado: Sinal — ORÇ-00112", jaLancado: true, confianca: 75, diferenca: 0 } as never, alternativas: [] },
  });
  assertEquals(decidir(nelson, CTX, m), {
    entra: false, codigo: "sinal_ja_lancado", motivo: "parece Sinal — ORÇ-00112 já lançado: é ligar ao extrato, não lançar de novo",
  });
  assertEquals(decidir(linha({ kind: "create_receivable", suggested_category: "Outras receitas" }), CTX, m).codigo, "sem_cliente");
  assertEquals(decidir(linha({ kind: "create_receivable", suggested_client_id: "c1" }), CTX, m).codigo, "entrada");
});

Deno.test("transferência para a própria HBR entra; com confiança baixa, fica fora", () => {
  const m = medidas();
  assertEquals(decidir(linha({ kind: "internal_transfer", quem: "HBR MARINE SOLUTIONS LTDA", confidence: 95 }), CTX, m).codigo, "transferencia");
  assertEquals(decidir(linha({ kind: "internal_transfer", confidence: 60 }), CTX, m).codigo, "sem_historico");
});

Deno.test("avisos: parou e 'já lançado' entram (ciente); duplicidade, Pix ainda na fila e solto ficam fora", () => {
  const m = medidas();
  const aviso = (chave: string, p: Partial<LinhaDaFila> = {}) =>
    linha({ kind: "anomaly", suggested_description: chave, bank_transaction_id: null, related_transaction_id: "t", suggested_category: null, ...p });
  assertEquals(decidir(aviso("vigia:parou:doc:1:2026-10"), CTX, m).codigo, "aviso_parou");
  assertEquals(decidir(aviso("vigia:valor:x", { tx_lancada: true }), CTX, m).codigo, "aviso_lancado");
  assertEquals(decidir(aviso("vigia:dup:a:b", { tx_lancada: true }), CTX, m).codigo, "duplicidade");
  assertEquals(decidir(aviso("vigia:novo:doc:9:2026-10", { fila_da_tx: "create_payable:pending" }), CTX, m).codigo, "aviso_da_fila");
  assertEquals(decidir(aviso("vigia:valor:y"), CTX, m).codigo, "aviso_solto");
});

Deno.test("montarLote: despesas por valor, depois transferência, depois avisos; numeração 1..N; total só de despesas", () => {
  const fila = [
    linha({ kind: "anomaly", suggested_description: "vigia:parou:x", bank_transaction_id: null, suggested_amount: 164.05, suggested_category: null,
      title: "UNIFIQUE TELECOMUNICACOES S/A aparecia todo mês e parou (último em 09/09)" }),
    linha({ suggested_amount: 70 }),
    linha({ kind: "internal_transfer", quem: "HBR MARINE SOLUTIONS LTDA", suggested_amount: 300, suggested_category: "Transferência entre contas" }),
    linha({ suggested_amount: 400 }),
    linha({ quem: "DEBITO DE CARTAO", desc: "DEBITO DE CARTAO", suggested_category: "Outras despesas", suggested_amount: 755 }),
  ];
  const l = montarLote(fila, CTX);
  assertEquals(l.itens.map((i) => [i.n, i.grupo, i.valor]), [[1, "despesa", 400], [2, "despesa", 70], [3, "transferencia", 300], [4, "aviso", 164.05]]);
  assertEquals(l.total, 470);
  assertEquals(l.fora.map((f) => f.codigo), ["sem_loja"]);
  assertEquals(l.itens[3].titulo, "Unifique Telecomunicacoes parou de aparecer (último em 09/09)");
  assertEquals(l.fora[0].titulo, "Débito sem loja de 10/10");
  assertEquals(l.contagens, { despesas: 2, transferencias: 1, avisos: 1, fora: 1, fora_por_grupo: { despesa: 1 }, fora_por_codigo: { sem_loja: 1 } });
  // determinístico
  assertEquals(JSON.stringify(montarLote([...fila].reverse(), CTX).itens), JSON.stringify(l.itens));
});

Deno.test("impressão: o que o 'sim' confere no banco (valor em centavos, data, regra, vínculo)", () => {
  const l = linha({ suggested_amount: 161.84, suggested_date: "2026-09-18", applied_rule_id: "r9" });
  assertEquals(impressaoDa(l), { kind: "create_payable", valor: 161.84, categoria: "Pagamento de fatura de cartão", data: "2026-09-18", regra: "r9", vinculo: false });
});

Deno.test("categoria confiável: precisa de 5 decisões e 90% sem troca", () => {
  const h = (n: number, iguais: number) => Array.from({ length: n }, (_, i) => decisao("Tarifas bancárias", i < iguais ? "Tarifas bancárias" : "Juros e encargos", `T${i}`));
  const tarifa = linha({ suggested_category: "Tarifas bancárias", quem: "TARIFA" });
  const com = (hist: DecisaoPassada[]) => decidir(tarifa, { limite: 500, historico: hist }, { aceitacao: aceitacaoPorCategoria(hist), escolhas: escolhasPorRecebedor(hist) });
  assertEquals(com(h(4, 4)).codigo, "sem_historico");
  assertEquals(com(h(10, 9)).codigo, "categoria");
  assertEquals(com(h(10, 8)).codigo, "sem_historico");
});

Deno.test("nomes: pessoa abreviada pelo CPF, empresa sem sufixo, Mercado Livre com a parcela, aviso curto", () => {
  assertEquals(nomeCurto("ELIANE APARECIDA UBERTI", "00981142982"), "Eliane U.");
  assertEquals(nomeCurto("MERCADO*MERCADOLIVRE 1/2"), "Mercado Livre (2x)");
  assertEquals(nomeCurto("PRIME CONTABILIDADE E ASSESSORIA FINANCEIRA LTDA").length <= 26, true);
  assertEquals(tituloDoAviso("Possível duplicidade: BANCO C6 S.A. — R$ 100,00 em 27/09 e 28/09"), "Banco C6: R$ 100,00 duas vezes (27/09 e 28/09)");
  assert(chavesDoRecebedor({ counterparty_name: "Pix enviado para JOAO", counterparty_document: "130.196.209-02", description: null }).includes("doc:13019620902"));
  assertEquals(chavesDoRecebedor({ counterparty_name: "DEBITO DE CARTAO", counterparty_document: null, description: "DEBITO DE CARTAO" }), []);
});

Deno.test("minutos: 2 para o lote + 20 s por item de fora + 1 min por débito sem loja, em blocos de 5", () => {
  assertEquals(minutosDoLote(0, []), 0);
  assertEquals(minutosDoLote(24, []), 5);
  const fora = Array.from({ length: 44 }, (_, i) => ({ id: String(i), grupo: "despesa" as const, titulo: "x", valor: 1, codigo: i < 6 ? "sem_loja" as const : "sem_categoria" as const, motivo: "" }));
  assertEquals(minutosDoLote(24, fora), 25);
});
