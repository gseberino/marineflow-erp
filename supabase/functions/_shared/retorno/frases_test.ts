// Retorno F1 (P2.3): a paridade dos sinais de texto entre o TypeScript e o SQL, por um fixture único.
//
// supabase/tests/retorno_f1_frases.json é a ÚNICA fonte dos casos dos dois lados:
//  - aqui, cada caso confere o que tem par em TypeScript: vendedor = pareceVendedor(nome, [texto]);
//    so_agradecimento = pareceSoAgradecimento(texto); encerrou = contatoEncerrou(texto);
//    pede_preco = PEDE_PRECO.test(paraBusca(texto));
//  - em supabase/tests/retorno_f1_sinais.sql, o mesmo fixture (literal, na constante c_frases) confere cada
//    chave de _retorno_sinais(texto, nome) (migration 20261116100300_retorno_f1_sinais.sql);
//  - o 3º teste lê o .sql e confere que o fixture de lá é IGUAL ao JSON: se alguém mudar um lado só, o CI quebra.
// Os casos são todos os de palavras_test.ts, palavras_vendedor_test.ts e contato-encerrou_test.ts (com o
// resultado que aqueles testes esperam), os exemplos C1, C2, C7 e C12 do plano e os sinais novos da P2.
// Só o paraBusca corta em 120 caracteres: por isso os casos com pede_preco têm menos de 120. pareceVendedor e
// contatoEncerrou leem o texto inteiro, e os casos longos de vendedor (Allana e Ketelyn) entram inteiros.
//
// Importa só ../secretario/palavras.ts, ../secretario/base.ts e ../whatsapp/contato-encerrou.ts: nada do
// assistente (isolamento_test.ts confere a pasta inteira).
// Reverter: apagar este arquivo (e o fixture, se a P2 sair junto).

import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { pareceSoAgradecimento, pareceVendedor, PEDE_PRECO } from "../secretario/palavras.ts";
import { paraBusca } from "../secretario/base.ts";
import { contatoEncerrou } from "../whatsapp/contato-encerrou.ts";

type Valor = boolean | string | null;

interface Caso {
  texto: string | null;
  nome: string | null;
  fonte: string;
  esperado: Record<string, Valor>;
  estreitado?: boolean;
  alargado?: boolean;
}

const FIXTURE = new URL("../../../tests/retorno_f1_frases.json", import.meta.url);
const TESTE_SQL = new URL("../../../tests/retorno_f1_sinais.sql", import.meta.url);

/** As chaves que _retorno_sinais devolve (o contrato que o P5 e o replay leem). */
const CHAVES = new Set([
  "servico", "servico_generico", "bem", "bem_palavra", "modelo", "ano", "pede_preco", "pedido", "vendedor",
  "so_agradecimento", "encerrou", "saudacao", "pressa", "urgente", "risco", "quer_dono", "reclamacao", "lgpd",
  "parar", "parar_largo", "site", "audio_pendente", "midia_sem_legenda",
]);
const SO_TEXTO = new Set(["bem_palavra", "modelo", "ano"]);

const leia = async (url: URL) => (await Deno.readTextFile(url)).replace(/\r\n/g, "\n");

async function casos(): Promise<Caso[]> {
  return JSON.parse(await leia(FIXTURE)) as Caso[];
}

/** O que as funções TypeScript dizem de um caso, só nas chaves que têm par em TypeScript. */
function doTypeScript(c: Caso): Record<string, boolean> {
  return {
    vendedor: pareceVendedor(c.nome, [c.texto]),
    so_agradecimento: pareceSoAgradecimento(c.texto),
    encerrou: contatoEncerrou(c.texto),
    pede_preco: PEDE_PRECO.test(paraBusca(c.texto)),
  };
}

Deno.test("fixture: 70 casos ou mais, no formato, e pede_preco só abaixo de 120 caracteres", async () => {
  const lista = await casos();
  assert(Array.isArray(lista), "o fixture não é uma lista");
  assert(lista.length >= 70, `o fixture tem ${lista.length} casos (mínimo 70)`);
  const vistos = new Set<string>();
  for (const [i, c] of lista.entries()) {
    assert(c.texto === null || typeof c.texto === "string", `caso ${i}: texto`);
    assert(c.nome === null || typeof c.nome === "string", `caso ${i}: nome`);
    assert(typeof c.fonte === "string" && c.fonte.length > 0, `caso ${i}: sem fonte`);
    assert(c.esperado && typeof c.esperado === "object" && Object.keys(c.esperado).length > 0, `caso ${i}: sem esperado`);
    for (const [k, v] of Object.entries(c.esperado)) {
      assert(CHAVES.has(k), `caso ${i}: chave ${k} fora do contrato de _retorno_sinais`);
      if (SO_TEXTO.has(k)) assert(v === null || typeof v === "string", `caso ${i}: ${k} não é texto nem nulo`);
      else assert(typeof v === "boolean", `caso ${i}: ${k} não é booleano`);
    }
    if ("pede_preco" in c.esperado) {
      assert(String(c.texto ?? "").length < 120, `caso ${i}: pede_preco com 120 caracteres ou mais (o paraBusca corta)`);
    }
    const chave = JSON.stringify([c.texto, c.nome]);
    assert(!vistos.has(chave), `caso ${i}: repetido (mesmo texto e nome)`);
    vistos.add(chave);
  }
  // As origens que a spec pede (P2.3).
  for (const fonte of ["palavras_test.ts", "palavras_vendedor_test.ts", "contato-encerrou_test.ts", "plano C1", "plano C2",
    "plano C7", "plano C12"]) {
    assert(lista.some((c) => c.fonte.split("; ").includes(fonte)), `nenhum caso de ${fonte}`);
  }
  // Os longos de vendedor entram inteiros (é lá que está a paridade do texto inteiro).
  assert(lista.some((c) => String(c.texto ?? "").length > 300 && c.esperado.vendedor === true), "sem caso longo de vendedor");
});

Deno.test("paridade TS × fixture: vendedor, so_agradecimento, encerrou e pede_preco", async () => {
  const lista = await casos();
  const falhas: string[] = [];
  const conferidas: Record<string, number> = { vendedor: 0, so_agradecimento: 0, encerrou: 0, pede_preco: 0 };
  for (const [i, c] of lista.entries()) {
    const ts = doTypeScript(c);
    for (const k of Object.keys(conferidas)) {
      if (!(k in c.esperado)) continue;
      conferidas[k]++;
      if (ts[k] !== c.esperado[k]) {
        falhas.push(`caso ${i} (${JSON.stringify(c.texto)}): ${k} no TypeScript = ${ts[k]}, no fixture = ${c.esperado[k]}`);
      }
    }
  }
  assertEquals(falhas, []);
  // Cada uma das quatro tem casos dos dois lados (verdadeiro e falso).
  for (const k of Object.keys(conferidas)) {
    assert(conferidas[k] >= 30, `${k}: só ${conferidas[k]} casos`);
    assert(lista.some((c) => c.esperado[k] === true), `${k}: nenhum caso verdadeiro`);
    assert(lista.some((c) => c.esperado[k] === false), `${k}: nenhum caso falso`);
  }
});

Deno.test("o fixture de retorno_f1_sinais.sql é o mesmo de retorno_f1_frases.json", async () => {
  const sql = await leia(TESTE_SQL);
  const marcador = "$" + "frases" + "$";
  assertEquals(sql.split(marcador).length - 1, 2, "o marcador do fixture tem de aparecer exatamente 2 vezes no .sql");
  const inicio = sql.indexOf(marcador) + marcador.length;
  const fim = sql.indexOf(marcador, inicio);
  const doSql = JSON.parse(sql.slice(inicio, fim));
  const doJson = JSON.parse(await leia(FIXTURE));
  assertEquals(doSql, doJson);
});
