import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { chaveTelefone, mesmoTelefone, padraoLikeTelefone, somenteDigitos } from "./phone.ts";

// O caso que originou esta regra: mensagem entregue a 554799159654 enquanto o cadastro
// dizia 5547999159654 (nono dígito). Os 8 dígitos finais casam nas duas formas.

Deno.test("somenteDigitos limpa formatação brasileira", () => {
  assertEquals(somenteDigitos("+55 (47) 99915-9654"), "5547999159654");
  assertEquals(somenteDigitos(null), "");
  assertEquals(somenteDigitos(undefined), "");
});

Deno.test("chaveTelefone usa os últimos 8 dígitos", () => {
  assertEquals(chaveTelefone("5547999159654"), "99159654");
  assertEquals(chaveTelefone("+55 (47) 99915-9654"), "99159654");
});

Deno.test("CASO REAL: com e sem o nono dígito geram a MESMA chave", () => {
  const comNove = "5547999159654";
  const semNove = "554799159654";
  assertEquals(chaveTelefone(comNove), chaveTelefone(semNove));
  assertEquals(mesmoTelefone(comNove, semNove), true);
});

Deno.test("número curto demais não gera chave (evita casar errado)", () => {
  assertEquals(chaveTelefone("1234567"), null);
  assertEquals(chaveTelefone(""), null);
  assertEquals(chaveTelefone(null), null);
  assertEquals(padraoLikeTelefone("123"), null);
});

Deno.test("padraoLikeTelefone monta o sufixo para o LIKE", () => {
  assertEquals(padraoLikeTelefone("5547999159654"), "%99159654");
});

Deno.test("telefones diferentes não casam", () => {
  assertEquals(mesmoTelefone("5547999159654", "5511987654321"), false);
  assertEquals(mesmoTelefone(null, null), false); // sem número não é "igual"
  assertEquals(mesmoTelefone("123", "123"), false); // curto demais
});
