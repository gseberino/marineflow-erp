import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { formatOptionsAsNumberedText, parseConfirmationReply, parseOptionReply, resolveOptionAsUserText } from "./whatsapp-channel.ts";

Deno.test("parseConfirmationReply: reconhece aprovação sem PIN", () => {
  assertEquals(parseConfirmationReply("sim"), { decision: "approve", pin: undefined });
  assertEquals(parseConfirmationReply("Sim"), { decision: "approve", pin: undefined });
  assertEquals(parseConfirmationReply("1"), { decision: "approve", pin: undefined });
  assertEquals(parseConfirmationReply("ok"), { decision: "approve", pin: undefined });
});

Deno.test("parseConfirmationReply: reconhece aprovação com PIN", () => {
  assertEquals(parseConfirmationReply("sim 4321"), { decision: "approve", pin: "4321" });
  assertEquals(parseConfirmationReply("SIM 0000"), { decision: "approve", pin: "0000" });
});

Deno.test("parseConfirmationReply: ignora um 2º token que não parece PIN", () => {
  assertEquals(parseConfirmationReply("sim por favor"), { decision: "approve", pin: undefined });
});

Deno.test("parseConfirmationReply: reconhece rejeição", () => {
  assertEquals(parseConfirmationReply("não"), { decision: "reject" });
  assertEquals(parseConfirmationReply("nao"), { decision: "reject" });
  assertEquals(parseConfirmationReply("2"), { decision: "reject" });
  assertEquals(parseConfirmationReply("cancelar"), { decision: "reject" });
});

Deno.test("parseConfirmationReply: texto comum não é confirmação", () => {
  assertEquals(parseConfirmationReply("quantas OS abertas temos?"), null);
  assertEquals(parseConfirmationReply(""), null);
});

Deno.test("parseOptionReply: aceita número dentro do intervalo", () => {
  assertEquals(parseOptionReply("2", 3), 2);
  assertEquals(parseOptionReply(" 1 ", 3), 1);
});

Deno.test("parseOptionReply: rejeita fora do intervalo ou não-numérico", () => {
  assertEquals(parseOptionReply("0", 3), null);
  assertEquals(parseOptionReply("4", 3), null);
  assertEquals(parseOptionReply("abc", 3), null);
  assertEquals(parseOptionReply("1.5", 3), null);
});

Deno.test("formatOptionsAsNumberedText: numera a partir de 1", () => {
  const text = formatOptionsAsNumberedText("Qual cliente?", [
    { label: "João Silva", value: "uuid-1" },
    { label: "Maria Souza", value: "uuid-2" },
  ]);
  assertEquals(text, "Qual cliente?\n1) João Silva\n2) Maria Souza");
});

Deno.test("resolveOptionAsUserText: UUID vira 'label (id: valor)'", () => {
  assertEquals(
    resolveOptionAsUserText({ label: "João Silva — (47) 99999-0000", value: "550e8400-e29b-41d4-a716-446655440000" }),
    "João Silva — (47) 99999-0000 (id: 550e8400-e29b-41d4-a716-446655440000)",
  );
});

Deno.test("resolveOptionAsUserText: __refine__ vira pedido de mais detalhes", () => {
  assertEquals(resolveOptionAsUserText({ label: "🔍 Refinar busca", value: "__refine__" }), "Quero refinar a busca — me peça mais detalhes para encontrar o registro correto.");
});

Deno.test("resolveOptionAsUserText: valor não-UUID vira só o label", () => {
  assertEquals(resolveOptionAsUserText({ label: "Sim", value: "sim" }), "Sim");
});
