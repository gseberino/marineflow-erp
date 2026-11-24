// Pacote 1 do assistente, S1 (24/11/2026): citaValorDataOuPromessa, a função que empresta as listas do validador do
// retorno (dinheiro, data/hora, promessa) ao PIN da mensagem de texto livre do assistente.
//
// O que se fixa: ela usa as MESMAS listas de validarSaida (o que reprova lá como dinheiro, data_fora, hora_fora ou
// promessa acusa aqui), sem contexto (nada é "permitido": "hoje" e "amanhã" contam), não olha tamanho, emoji nem eco, e
// nunca lança. O validador continua sem import (isolamento_test.ts) e validarSaida não muda (validador_test.ts).
// Rodar com:
//   deno test --allow-all --no-check --node-modules-dir=none supabase/functions/_shared/retorno/validador_cita_test.ts
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { citaValorDataOuPromessa, type ContextoDoValidador, validarSaida } from "./validador.ts";

const NADA = { valor: false, data: false, promessa: false };

Deno.test("S1 cita: valor pelas listas de dinheiro do validador", () => {
  for (const t of ["R$ 350", "350,00", "10% à vista", "pago em reais", "manda o pix", "qual o preço?", "valor de 80", "segue o boleto", "sem custo"]) {
    assertEquals(citaValorDataOuPromessa(t), { ...NADA, valor: true }, t);
  }
});

Deno.test("S1 cita: data e hora pelas listas do validador, sem nada permitido", () => {
  for (const t of ["dia 12/12", "amanhã cedo", "hoje", "na sexta", "em março", "às 10h", "21:40", "em 30 min", "ao meio-dia", "2026-11-30"]) {
    assertEquals(citaValorDataOuPromessa(t), { ...NADA, data: true }, t);
  }
  // "marco" sem cedilha é de marcar, não o mês (a mesma regra do validador).
  assertEquals(citaValorDataOuPromessa("marco a visita depois"), NADA);
});

Deno.test("S1 cita: promessa pela lista do validador", () => {
  for (const t of ["garanto que resolve", "pode deixar", "com certeza", "prometo ver isso"]) {
    assertEquals(citaValorDataOuPromessa(t), { ...NADA, promessa: true }, t);
  }
  assertEquals(citaValorDataOuPromessa("fica pronto sexta"), { valor: false, data: true, promessa: true });
});

Deno.test("S1 cita: texto neutro não acusa nada, nem longo, nem com emoji (tamanho e emoji não são assunto daqui)", () => {
  assertEquals(citaValorDataOuPromessa("Bom dia, tudo bem? Pode me mandar a foto da peça?"), NADA);
  assertEquals(citaValorDataOuPromessa("Recebido, obrigado! 👍 ".repeat(60)), NADA);
  assertEquals(citaValorDataOuPromessa(""), NADA);
});

Deno.test("S1 cita: acentos, maiúsculas e letra estilizada não escondem (a mesma normalização do validador)", () => {
  assertEquals(citaValorDataOuPromessa("AMANHÃ").data, true);
  assertEquals(citaValorDataOuPromessa("Preço").valor, true);
  assertEquals(citaValorDataOuPromessa("ｐｉｘ").valor, true, "largura cheia");
  assertEquals(citaValorDataOuPromessa("Terça").data, true);
});

Deno.test("S1 cita: é a mesma régua de validarSaida (o que ela reprova por dinheiro, data, hora ou promessa, esta acusa)", () => {
  const ctx: ContextoDoValidador = {
    audiencia: "cliente", datas_permitidas: [], horas_permitidas: [], nome_permitido: null, nomes_de_outros: [], os_permitidas: [],
    textos_do_cliente: [], trechos_do_modelo: [], marcas: { tem_proposta: false, tem_topo: false, cliente_ouviu: false, conferida: false },
  };
  const textos = [
    "Bom dia, tudo bem?", "Fica R$ 350", "Te vejo amanhã", "Passo aí às 10h", "Pode deixar", "O total é 350,00", "Na sexta eu aviso",
    "Recebido, obrigado.", "Fica pronto hoje", "Sem custo", "Em novembro", "Chego em 30 min",
  ];
  for (const t of textos) {
    const v = validarSaida(t, ctx);
    const regras = v.ok ? [] : v.regras;
    const c = citaValorDataOuPromessa(t);
    assertEquals(c.valor, regras.includes("dinheiro"), `valor: ${t}`);
    assertEquals(c.data, regras.includes("data_fora") || regras.includes("hora_fora"), `data: ${t}`);
    assertEquals(c.promessa, regras.includes("promessa"), `promessa: ${t}`);
  }
});

Deno.test("S1 cita: nunca lança; o que não é texto vira texto, e o que explode vale tudo (na dúvida, cita)", () => {
  // deno-lint-ignore no-explicit-any
  const torto = (v: unknown) => citaValorDataOuPromessa(v as any);
  assertEquals(torto(undefined), NADA);
  assertEquals(torto(null), NADA);
  assertEquals(torto(42), NADA);
  assertEquals(torto({ toString() { throw new Error("texto que explode"); } }), { valor: true, data: true, promessa: true });
});
