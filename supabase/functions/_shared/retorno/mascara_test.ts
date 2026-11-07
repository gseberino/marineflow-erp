// Retorno rápido, F2 (P9.5): a máscara dos dados pessoais. Dados inventados.
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { mascararDadosPessoais } from "./mascara.ts";

Deno.test("CPF, CNPJ, telefone, e-mail e placa viram [dado]", () => {
  for (const [dado, frase] of [
    ["123.456.789-09", "meu cpf é 123.456.789-09 ok"],
    ["12345678909", "cpf 12345678909"],
    ["12.345.678/0001-95", "cnpj 12.345.678/0001-95"],
    ["(47) 99999-1234", "me liga no (47) 99999-1234 depois"],
    ["+55 47 99999-1234", "whats +55 47 99999-1234"],
    ["maria.silva@exemplo.com.br", "manda para maria.silva@exemplo.com.br"],
    ["ABC-1234", "a placa é ABC-1234"],
    ["BRA2E19", "placa BRA2E19"],
  ]) {
    const saida = mascararDadosPessoais(frase);
    assertEquals(saida.includes(dado), false, frase);
    assertEquals(saida.includes("[dado]"), true, frase);
  }
});

Deno.test("o resto do texto fica como veio", () => {
  for (const t of ["como tá o motorhome?", "a peça chegou dia 14/12", "são 2 baterias de 200 Ah", "OS-00161", "R$ 3.200"]) {
    assertEquals(mascararDadosPessoais(t), t);
  }
  assertEquals(mascararDadosPessoais(""), "");
});
