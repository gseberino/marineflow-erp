import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  contradicaoSemReceita, entradaLigadaAOS, entradaSemCliente, FRASE_SEM_RECEITA_COM_OS, FRASE_SEM_RECEITA_COM_VINCULO,
  motivoDaEntradaSemCliente, saiSemReceita,
} from "./entrada-sem-cliente.ts";

Deno.test("entrada sem cliente: transferência entre contas e aporte de sócio dispensam cliente", () => {
  assertEquals(entradaSemCliente("Transferência entre contas")?.marca, "transferencia");
  assertEquals(entradaSemCliente(" Aporte de sócio ")?.marca, "aporte_socio");
  // Receita de verdade continua pedindo cliente.
  assertEquals(entradaSemCliente("Serviços prestados"), null);
  assertEquals(entradaSemCliente("Outras receitas"), null);
  assertEquals(entradaSemCliente(null), null);
  assertEquals(entradaSemCliente(""), null);
});

Deno.test("entrada sem cliente: o motivo leva a observação e cabe em 300 caracteres", () => {
  const regra = entradaSemCliente("Transferência entre contas")!;
  assertEquals(motivoDaEntradaSemCliente(regra, null), "Transferência entre contas próprias");
  assertEquals(motivoDaEntradaSemCliente(regra, "  do C6 para o   Nubank "), "Transferência entre contas próprias — do C6 para o Nubank");
  assertEquals(motivoDaEntradaSemCliente(regra, "x".repeat(400)).length, 300);
});

Deno.test("sai sem receita: só ENTRADA, pela categoria efetiva", () => {
  assertEquals(saiSemReceita("create_receivable", "Aporte de sócio")?.marca, "aporte_socio");
  assertEquals(saiSemReceita("create_receivable", "Transferência entre contas")?.marca, "transferencia");
  // A SAÍDA "Transferência entre contas" é despesa do plano de saída: segue o caminho dela.
  assertEquals(saiSemReceita("create_payable", "Transferência entre contas"), null);
  // A transferência que o motor reconhece tem caminho próprio (marca as duas pernas).
  assertEquals(saiSemReceita("internal_transfer", "Transferência entre contas"), null);
  assertEquals(saiSemReceita("create_receivable", "Serviços prestados"), null);
  assertEquals(saiSemReceita(null, "Aporte de sócio"), null);
});

Deno.test("entrada ligada a uma OS: o saldo escolhido no vínculo ou a OS respondida", () => {
  // Saldo da OS escolhido no vínculo.
  assertEquals(entradaLigadaAOS("os-60", undefined), true);
  // "Sim, é desta" ou a anotação do dono.
  assertEquals(entradaLigadaAOS(null, "os-60"), true);
  // "Não é desta" (null) e sem resposta (undefined) não ligam.
  assertEquals(entradaLigadaAOS(null, null), false);
  assertEquals(entradaLigadaAOS(null, undefined), false);
  assertEquals(entradaLigadaAOS(undefined, undefined), false);
  assertEquals(entradaLigadaAOS("", ""), false);
});

Deno.test("contradição de quem sai sem receita: casar, sinal, saldo de OS ou 'é desta OS'", () => {
  // Casar com o que já está lançado ou registrar sinal: é recebimento de cliente.
  assertEquals(contradicaoSemReceita({ tipo: "receivable" }, undefined), FRASE_SEM_RECEITA_COM_VINCULO);
  assertEquals(contradicaoSemReceita({ tipo: "existing_payment" }, undefined), FRASE_SEM_RECEITA_COM_VINCULO);
  assertEquals(contradicaoSemReceita({ tipo: "quote_deposit" }, undefined), FRASE_SEM_RECEITA_COM_VINCULO);
  // Saldo de OS escolhido, ou a OS respondida/anotada: é pagamento do serviço.
  assertEquals(contradicaoSemReceita({ tipo: "service_order_balance" }, undefined), FRASE_SEM_RECEITA_COM_OS);
  assertEquals(contradicaoSemReceita(null, "os-60"), FRASE_SEM_RECEITA_COM_OS);
  // "Nenhum destes" e "não é desta OS": sai sem receita.
  assertEquals(contradicaoSemReceita(null, null), null);
  assertEquals(contradicaoSemReceita(undefined, undefined), null);
});
