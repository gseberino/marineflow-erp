// Retorno F1 (P2.3): o PARAR por extenso do SQL (sinal parar_largo de _retorno_sinais, migration
// 20261116100300_retorno_f1_sinais.sql) contra a regra LARGA de opt-out de classificarResposta
// (_shared/ai/comms/reply-router.ts:31, congelado: aqui só se lê, num teste que não é publicado; por isso este
// arquivo fica fora de _shared/retorno/).
//
// Lê o fixture único supabase/tests/retorno_f1_frases.json (o mesmo que retorno_f1_sinais.sql confere no banco)
// e prova:
//  (a) todo caso com esperado.parar_largo === true dá opt_out na regra larga: o parar_largo é SUBCONJUNTO dela;
//  (b) os casos marcados "estreitado" ("nunca mais funcionou o inversor", "me tira uma dúvida", "não me manda o
//      pix ainda") dão opt_out no TypeScript e parar_largo = false no fixture. É a divergência de propósito,
//      escrita: a F0b-5 tirou "nunca mais" e "me tira" solto, e o "não me mand…" ficou só com "mais/mensagem";
//  (c) a única exceção ao subconjunto, marcada "alargado": "me tire dessa lista" (o subjuntivo do mesmo pedido) é
//      parar_largo no SQL — a regra da spec é me tir(a|e) … lista — e a regra larga só conhece "me tira". Errar
//      para esse lado só tira o recibo e leva a mensagem ao dono (não grava opt-out). Fica fora de (a) e é
//      conferida aqui, para a exceção não crescer calada.
// Reverter: apagar este arquivo.

import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { classificarResposta } from "../ai/comms/reply-router.ts";

interface Caso {
  texto: string | null;
  nome: string | null;
  esperado: Record<string, boolean | string | null>;
  estreitado?: boolean;
  alargado?: boolean;
}

const FIXTURE = new URL("../../../tests/retorno_f1_frases.json", import.meta.url);

async function casos(): Promise<Caso[]> {
  return JSON.parse((await Deno.readTextFile(FIXTURE)).replace(/\r\n/g, "\n")) as Caso[];
}

const optOut = (texto: string | null) => classificarResposta(texto ?? "").intencao === "opt_out";

Deno.test("(a) parar_largo do SQL é subconjunto do opt_out de classificarResposta", async () => {
  const lista = (await casos()).filter((c) => c.esperado.parar_largo === true && !c.alargado);
  assert(lista.length >= 5, `só ${lista.length} casos de parar_largo verdadeiro`);
  const fora = lista.filter((c) => !optOut(c.texto)).map((c) => c.texto);
  assertEquals(fora, [], "parar_largo fora da regra larga");
  // Os da spec (P2.2 teste 7 e P2.3) estão lá.
  for (const t of ["pare de me mandar mensagem", "não me mande mais", "me tira dessa lista", "quero sair da lista",
    "não quero mais receber mensagens desse número"]) {
    assert(lista.some((c) => c.texto === t), `falta o caso "${t}"`);
  }
});

Deno.test("(b) estreitado: opt_out na regra larga, parar_largo falso no fixture", async () => {
  const lista = (await casos()).filter((c) => c.estreitado);
  for (const t of ["nunca mais funcionou o inversor", "me tira uma dúvida", "não me manda o pix ainda"]) {
    assert(lista.some((c) => c.texto === t), `falta o caso estreitado "${t}"`);
  }
  for (const c of lista) {
    assert(optOut(c.texto), `"${c.texto}" marcado estreitado, mas não é opt_out na regra larga`);
    assertEquals(c.esperado.parar_largo, false, `"${c.texto}" marcado estreitado, mas parar_largo não é falso`);
  }
});

Deno.test("(c) alargado: só 'me tire dessa lista', parar_largo no SQL e fora da regra larga", async () => {
  const lista = (await casos()).filter((c) => c.alargado);
  assertEquals(lista.map((c) => c.texto), ["me tire dessa lista, por favor"]);
  for (const c of lista) {
    assertEquals(c.esperado.parar_largo, true);
    assertEquals(optOut(c.texto), false, "a regra larga passou a conhecer \"me tire\": tire a marca alargado do caso");
  }
});

Deno.test("PARAR exato não é parar_largo (é parar, tratado à parte)", async () => {
  const parar = (await casos()).find((c) => c.texto === "PARAR");
  assert(parar, "falta o caso PARAR");
  assertEquals(parar.esperado.parar, true);
  assertEquals(parar.esperado.parar_largo, false);
});
