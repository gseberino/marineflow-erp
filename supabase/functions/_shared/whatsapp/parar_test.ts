// Retorno F1 (P13.1): ehPedidoDeParar é o porte exato de _e_pedido_de_parar (F0b, 20261106100100:19-28).
//
// Os casos são os de supabase/tests/retorno_f0b_parar.sql (8 que são pedido de parar, 7 que não são), e um teste lê
// aquele arquivo para provar que a lista daqui é a mesma de lá. Outro lê as migrations: o padrão e o translate dos
// acentos têm de ser os mesmos do banco. Se o SQL mudar, estes testes caem até o TypeScript mudar junto.

import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { ehPedidoDeParar, PEDIDO_DE_PARAR, textoSimples } from "./parar.ts";

/** Seção 1 de retorno_f0b_parar.sql: a mensagem inteira é o pedido de parar. */
const PEDIDOS = [
  "PARAR",
  "Pare!",
  " sair ",
  "STOP",
  "Descadastrar",
  "Não quero mais mensagens",
  "nao quero mais receber mensagem, por favor",
  "Não quero mais mensagens automáticas.",
];

/** Seção 1b de retorno_f0b_parar.sql: frase com a palavra, ou vazia, não é pedido de parar. */
const NAO_PEDIDOS: Array<string | null> = [
  "vou parar o carro aí às 14h",
  "nunca mais faço com vocês",
  "me tira uma dúvida",
  "pode parar o serviço?",
  "",
  null,
  "não quero mais o orçamento",
];

const leia = async (relativo: string) =>
  (await Deno.readTextFile(new URL(relativo, import.meta.url))).replace(/\r\n/g, "\n");

/** Os argumentos de _e_pedido_de_parar(...) num trecho de SQL: o literal sem aspas, ou null. */
function argumentosDoSql(trecho: string): Array<string | null> {
  const saida: Array<string | null> = [];
  for (const m of trecho.matchAll(/_e_pedido_de_parar\((null|'((?:[^']|'')*)')\)/g)) {
    saida.push(m[1] === "null" ? null : m[2].replace(/''/g, "'"));
  }
  return saida;
}

Deno.test("PARAR: os 8 pedidos de retorno_f0b_parar.sql são pedido de parar", () => {
  assertEquals(PEDIDOS.length, 8);
  for (const t of PEDIDOS) assert(ehPedidoDeParar(t), `deveria ser pedido de parar: "${t}"`);
});

Deno.test("PARAR: as 7 frases de retorno_f0b_parar.sql NÃO são pedido de parar", () => {
  assertEquals(NAO_PEDIDOS.length, 7);
  for (const t of NAO_PEDIDOS) assertEquals(ehPedidoDeParar(t), false, `não deveria ser pedido de parar: "${t}"`);
  assertEquals(ehPedidoDeParar(undefined), false);
});

Deno.test("PARAR: os casos daqui são os mesmos do teste SQL da F0b (seções 1 e 1b)", async () => {
  const sql = await leia("../../../tests/retorno_f0b_parar.sql");
  const secao1 = sql.slice(sql.indexOf("-- 1."), sql.indexOf("-- 2."));
  const corte = secao1.indexOf("raise exception '1:");
  assert(corte > 0, "a seção 1 do teste SQL mudou de forma");
  assertEquals(argumentosDoSql(secao1.slice(0, corte)), PEDIDOS);
  assertEquals(argumentosDoSql(secao1.slice(corte)), NAO_PEDIDOS);
});

Deno.test("PARAR: os corpos das seções 2 e 3 do teste SQL (o gatilho) dão o mesmo resultado", () => {
  assert(ehPedidoDeParar("parar"));
  assertEquals(ehPedidoDeParar("vou parar aí amanhã"), false);
});

Deno.test("PARAR: o padrão e a limpeza são os da migration da F0b, letra por letra", async () => {
  const sql = await leia("../../../migrations/20261106100100_retorno_f0b_parar.sql");
  const ini = sql.indexOf("create or replace function public._e_pedido_de_parar(");
  const corpo = sql.slice(ini, sql.indexOf("$$;", ini));
  const padrao = corpo.match(/~ '([^']+)'/)?.[1];
  assertEquals(padrao, PEDIDO_DE_PARAR.source);
  assert(
    corpo.includes(
      "btrim(regexp_replace(regexp_replace(public._texto_simples(p_texto), '[^a-z0-9 ]', ' ', 'g'), '\\s+', ' ', 'g'))",
    ),
    "a limpeza do texto mudou na migration",
  );
});

Deno.test("PARAR: textoSimples troca os mesmos acentos que a última definição de _texto_simples (maiúsculas também)", async () => {
  const pasta = new URL("../../../migrations/", import.meta.url);
  const nomes: string[] = [];
  for await (const e of Deno.readDir(pasta)) if (e.isFile && e.name.endsWith(".sql")) nomes.push(e.name);
  nomes.sort();
  let ultima: string | null = null;
  for (const nome of nomes) {
    const sql = await leia(`../../../migrations/${nome}`);
    const ini = sql.indexOf("function public._texto_simples(p_texto text)");
    if (ini >= 0) ultima = sql.slice(ini, sql.indexOf("$$;", ini));
  }
  assert(ultima, "nenhuma migration define _texto_simples");
  const m = ultima.match(/translate\(lower\(coalesce\(p_texto, ''\)\), '([^']+)', '([^']+)'\)/);
  assert(m, "a forma do translate de _texto_simples mudou");
  const de = [...m[1]];
  const para = [...m[2]];
  assertEquals(de.length, para.length);
  assertEquals(de.length, 23);
  for (let i = 0; i < de.length; i++) {
    assertEquals(textoSimples(de[i]), para[i], `acento ${de[i]}`);
    // o banco é en_US.UTF-8: lower('ÃÉÇÑ') = 'ãéçñ' (conferido em 01/11/2026)
    assertEquals(textoSimples(de[i].toUpperCase()), para[i], `acento maiúsculo ${de[i].toUpperCase()}`);
  }
  // o ñ fica de fora do translate, como no banco: vira espaço na limpeza
  assertEquals(textoSimples("Ñ"), "ñ");
  assertEquals(textoSimples(null), "");
});

Deno.test("PARAR: espaços, quebras de linha e pontuação em volta não mudam o pedido; texto a mais muda", () => {
  assert(ehPedidoDeParar("  PARAR.\n"));
  assert(ehPedidoDeParar("Pare,   por favor!"));
  assert(ehPedidoDeParar("sair pf"));
  assert(ehPedidoDeParar("NÃO QUERO MAIS RECEBER MENSAGENS AUTOMÁTICAS"));
  assertEquals(ehPedidoDeParar("parar parar"), false);
  assertEquals(ehPedidoDeParar("pare de me mandar mensagem"), false, "o PARAR por extenso é do parar_largo (P2), não do opt-out");
  assertEquals(ehPedidoDeParar("me tira dessa lista"), false);
});
