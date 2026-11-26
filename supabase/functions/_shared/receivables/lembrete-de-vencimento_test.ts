// O lembrete ANTES do vencimento (dono, 26/11/2026: "2. A" — passa a pedir o "sim" dele). O que se protege aqui: o texto ao
// cliente é o MESMO que a rotina mandava; as travas (conta paga, sinal, vencida, já lembrada, sem cliente, genérico, piso,
// entrada esperando no Extrato, opt-out, sem telefone); o cartão do "sim" mostra quem, o número, a conta e a mensagem
// exata; o retrato pega o que mudou até o "sim" (mas não a contagem de dias que muda sozinha); a chave é a de antes.
import { assert, assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  cartaoDoLembreteDeVencimento,
  chaveDoLembreteDeVencimento,
  descricaoDaCobranca,
  diasEntre,
  type LembreteDeVencimento,
  lembreteRecusado,
  montarLembreteDeVencimento,
  oQueMudouNoLembreteDeVencimento,
  relogioDoLembreteDeVencimento,
  resumirLembreteDeVencimento,
  retratoDoLembreteDeVencimento,
  somarDias,
  textoDoPrazo,
} from "./lembrete-de-vencimento.ts";
import { ambiente, conta, CONTA, flavio, FLAVIO, type Linha } from "./lembrete-de-vencimento-banco_test.ts";

const semNbsp = (x: unknown) => String(x ?? "").replace(/ /g, " ");

// 26/11/2026 ao meio-dia em Brasília
relogioDoLembreteDeVencimento.agora = () => new Date("2026-11-26T15:00:00Z");

const TEXTO_PADRAO =
  "Olá Flávio! 👋 Lembramos que o pagamento de *R$ 3.292,00* referente a *Saldo — OS-00134* vence em *3 dias* (*29/11/2026*). " +
  "Em caso de dúvidas, entre em contato. — *HBR Marine Solutions*";

async function montar(db: unknown, args: Linha = { receivable_id: CONTA }): Promise<LembreteDeVencimento> {
  const l = await montarLembreteDeVencimento(db, db, args);
  assert(!lembreteRecusado(l), JSON.stringify(l));
  return l as LembreteDeVencimento;
}

Deno.test("o texto ao cliente é o MESMO que a rotina mandava, com o saldo e o vencimento da conta", async () => {
  const l = await montar(ambiente());
  assertEquals(semNbsp(l.texto), TEXTO_PADRAO);
  assertEquals([l.valor, l.vencimento, l.dias, l.telefone, l.nomeDoCliente], [3292, "2026-11-29", 3, "5547999990001", "Flávio da Igreja"]);
  // parcial: o saldo, não o valor cheio; sem descrição, o número da OS como vem
  const p = await montar(ambiente({ receivables: [conta({ amount: 3292, paid_amount: 1292, balance_amount: 2000, status: "partially_paid", description: "" })] }));
  assertStringIncludes(semNbsp(p.texto), "o pagamento de *R$ 2.000,00* referente a *OS-00134* vence em *3 dias*");
  // vence amanhã / hoje
  assertStringIncludes((await montar(ambiente({ receivables: [conta({ due_date: "2026-11-27" })] }))).texto, "vence *amanhã* (*27/11/2026*)");
  assertStringIncludes((await montar(ambiente({ receivables: [conta({ due_date: "2026-11-26" })] }))).texto, "vence *hoje* (*26/11/2026*)");
});

Deno.test("as travas, cada uma com a frase pronta", async () => {
  const casos: Array<[string, Record<string, Linha[]>, Linha, string]> = [
    ["id torto", {}, { receivable_id: "conta-1" }, "Diga qual conta a receber"],
    ["não existe", { receivables: [] }, { receivable_id: CONTA }, "Conta a receber não encontrada."],
    ["paga", { receivables: [conta({ status: "paid", paid_amount: 3292, balance_amount: 0 })] }, { receivable_id: CONTA }, "já está paga"],
    ["cancelada", { receivables: [conta({ status: "cancelled" })] }, { receivable_id: CONTA }, "já está cancelada"],
    ["sinal", { receivables: [conta({ is_deposit: true })] }, { receivable_id: CONTA }, "é um sinal"],
    ["vencida", { receivables: [conta({ due_date: "2026-11-25" })] }, { receivable_id: CONTA }, "já venceu (25/11/2026): aí é cobrança"],
    ["já lembrada", { receivables: [conta({ reminder_sent_at: "2026-11-20T12:00:00Z" })] }, { receivable_id: CONTA }, "já saiu (ou foi dispensado"],
    ["sem cliente", { receivables: [conta({ client_id: null })] }, { receivable_id: CONTA }, "não está ligada a um cliente do cadastro"],
    ["cadastro sumiu", { clients: [] }, { receivable_id: CONTA }, "O cadastro do cliente desta conta não foi encontrado."],
    ["genérico", { clients: [flavio({ name: "Cliente Final", generico: true })] }, { receivable_id: CONTA }, "O cadastro Cliente Final é genérico"],
    ["piso", { receivables: [conta({ amount: 150, balance_amount: 150 })] }, { receivable_id: CONTA }, "abaixo do piso de R$ 200,00"],
    ["entrada esperando", { finance_review_queue: [{ suggested_client_id: FLAVIO, suggested_amount: 3292, suggested_date: "2026-11-25", title: "Receita: FLAVIO", status: "pending", kind: "create_receivable" }] }, { receivable_id: CONTA }, "Este cliente tem entrada esperando no Extrato (R$ 3.292,00 de 25/11/2026)"],
    ["opt-out", { clients: [flavio({ opt_out_whatsapp: true })] }, { receivable_id: CONTA }, "opt-out"],
    ["sem telefone", { clients: [flavio({ whatsapp: null, phone: "123" })] }, { receivable_id: CONTA }, "Sem telefone válido no cadastro"],
  ];
  for (const [nome, tabelas, args, trecho] of casos) {
    const l = await montarLembreteDeVencimento(ambiente(tabelas), ambiente(tabelas), args);
    assert(lembreteRecusado(l), nome);
    assertStringIncludes(semNbsp(l.error), trecho, nome);
  }
});

Deno.test("leitura que falha LANÇA (nunca vira 'sem trava')", async () => {
  for (const tabela of ["receivables", "clients", "app_settings", "finance_review_queue"]) {
    const db = ambiente({}, [tabela]);
    let lancou = false;
    try {
      await montarLembreteDeVencimento(db, db, { receivable_id: CONTA });
    } catch {
      lancou = true;
    }
    assert(lancou, tabela);
  }
});

Deno.test("o cartão do 'sim': quem, o número inteiro, a conta e a mensagem exata; fixo e modo de teste avisam", async () => {
  const l = await montar(ambiente());
  const c = semNbsp(cartaoDoLembreteDeVencimento(l));
  assertStringIncludes(c, "Lembrete ANTES do vencimento para *Flávio da Igreja* — WhatsApp +55 (47) 99999-0001");
  assertStringIncludes(c, "Conta: Saldo — OS-00134 · *R$ 3.292,00* · vence 29/11/2026 (em 3 dias)");
  assertStringIncludes(c, `Mensagem que vai ao cliente:\n${TEXTO_PADRAO}`);
  assertEquals(c.includes("FIXO"), false);
  const fixo = await montar(ambiente({ clients: [flavio({ whatsapp: "(47) 3333-4444" })] }));
  assertStringIncludes(cartaoDoLembreteDeVencimento(fixo, { teste: true }), "parece de telefone FIXO");
  assertStringIncludes(cartaoDoLembreteDeVencimento(fixo, { teste: true }), "Modo de teste ligado");
  // a frase do dono vai como está, e o cartão pede para conferir valor e data
  const proprio = await montar(ambiente(), { receivable_id: CONTA, custom_message: "Oi Flávio, lembrando da parcela de sábado." });
  assertEquals(proprio.texto, "Oi Flávio, lembrando da parcela de sábado.");
  assertStringIncludes(semNbsp(cartaoDoLembreteDeVencimento(proprio)), "a frase é sua — confira se o valor (R$ 3.292,00) e a data (29/11/2026)");
  // a recusa vira uma linha "⚠️" (o executor devolve como recusa, sem pendência)
  assertEquals(await resumirLembreteDeVencimento(ambiente({ receivables: [conta({ is_deposit: true })] }), { receivable_id: CONTA }),
    "⚠️ Esta conta é um sinal: o lembrete antes do vencimento não vale para sinal.");
});

Deno.test("o retrato pega o que mudou até o 'sim' — mas não a contagem de dias, que muda sozinha de um dia para o outro", async () => {
  const db = ambiente();
  const retrato = retratoDoLembreteDeVencimento(await montar(db));
  assertEquals(retrato, { conta: CONTA, telefone: "5547999990001", valor: 3292, vencimento: "2026-11-29", texto: (await montar(db)).texto });
  assertEquals(oQueMudouNoLembreteDeVencimento(retrato, await montar(db)), null);
  // pagou um pedaço
  const pago = ambiente({ receivables: [conta({ paid_amount: 1000, balance_amount: 2292, status: "partially_paid" })] });
  assertStringIncludes(semNbsp(oQueMudouNoLembreteDeVencimento(retrato, await montar(pago))), "o valor mudou (era R$ 3.292,00, agora R$ 2.292,00)");
  // vencimento renegociado
  const outro = ambiente({ receivables: [conta({ due_date: "2026-12-05" })] });
  assertStringIncludes(String(oQueMudouNoLembreteDeVencimento(retrato, await montar(outro))), "o vencimento mudou (era 29/11/2026, agora 05/12/2026)");
  // número trocado no cadastro
  const fone = ambiente({ clients: [flavio({ whatsapp: "(47) 98888-0002" })] });
  assertEquals(oQueMudouNoLembreteDeVencimento(retrato, await montar(fone)), "o telefone de destino mudou");
  // o dono respondeu no dia seguinte: "vence em 3 dias" virou "vence em 2 dias" — é o mesmo lembrete
  const antes = relogioDoLembreteDeVencimento.agora;
  relogioDoLembreteDeVencimento.agora = () => new Date("2026-11-27T15:00:00Z");
  try {
    const amanha = await montar(db);
    assertStringIncludes(amanha.texto, "vence em *2 dias*");
    assertEquals(oQueMudouNoLembreteDeVencimento(retrato, amanha), null);
  } finally {
    relogioDoLembreteDeVencimento.agora = antes;
  }
  // a frase do dono trocada é mudança
  const proprio = await montar(db, { receivable_id: CONTA, custom_message: "Outra frase." });
  assertEquals(oQueMudouNoLembreteDeVencimento(retrato, proprio), "o texto da mensagem mudou");
});

Deno.test("a chave é a de antes (o vencimento é o dia-alvo); o teste ganha ':teste'", () => {
  assertEquals(chaveDoLembreteDeVencimento(CONTA, "2026-11-29", false), `lembrete-recebivel:${CONTA}:2026-11-29`);
  assertEquals(chaveDoLembreteDeVencimento(CONTA, "2026-11-29", true), `lembrete-recebivel:${CONTA}:2026-11-29:teste`);
});

// Os ajudantes que moravam em receivable-reminders/enviar.ts (os mesmos testes de antes).
Deno.test("prazo: hoje, amanhã ou N dias, pelo vencimento de verdade", () => {
  assertEquals(textoDoPrazo(diasEntre("2026-11-09", "2026-11-12")), "vence em *3 dias*");
  assertEquals(textoDoPrazo(diasEntre("2026-11-09", "2026-11-11")), "vence em *2 dias*");
  assertEquals(textoDoPrazo(1), "vence *amanhã*");
  assertEquals(textoDoPrazo(0), "vence *hoje*");
  assertEquals(somarDias("2026-12-31", 1), "2027-01-01");
  assertEquals(somarDias("2026-03-01", -1), "2026-02-28");
});

// "OS OS-" (12/10/2026): o número da OS já traz o prefixo ("OS-00060"); nunca "OS OS-00060".
Deno.test("descricaoDaCobranca: a descrição vence; sem ela, o número; sem os dois, 'cobrança pendente'", () => {
  assertEquals(descricaoDaCobranca("Saldo da OS-00060", "OS-00060"), "Saldo da OS-00060");
  assertEquals(descricaoDaCobranca(null, "OS-00060"), "OS-00060");
  assertEquals(descricaoDaCobranca("", "ORÇ-00112"), "ORÇ-00112");
  assertEquals(descricaoDaCobranca(undefined, ""), "cobrança pendente");
  assertEquals(descricaoDaCobranca(null, null), "cobrança pendente");
});
