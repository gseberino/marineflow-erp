// O comando do lote da papelada (secretário, Passo 5): o que é lido e o que NÃO pode colidir com a confirmação
// (1/2/sim/não), com os comprovantes ("lote antigo" é deles), com a pergunta ativa nem com as letras da manhã.
// Spec: spec-secretario-papelada.md §3.6–3.7.
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { lerComandoDoSecretario } from "./comandos.ts";
import { parseConfirmationReply, parseOptionReply } from "../ai/whatsapp-channel.ts";
import { lerComando } from "../comprovantes/respostas.ts";
import { lerNumero, lerSimNao, normalizarResposta, pareceRespostaCurta } from "../whatsapp/pergunta-ativa.ts";

const P = (sem: number[] = [], semGrupos: string[] = [], soGrupos: string[] | null = null) => ({ comando: "papelada", sem, semGrupos, soGrupos });

const COMANDOS: Array<[string, unknown]> = [
  ["lote", P()],
  ["*Lote*", P()],
  ["lote.", P()],
  ["ver o lote", P()],
  ["lote da semana", P()],
  ["lote sem 3, 7", P([3, 7])],
  ["lote sem 3 e 7", P([3, 7])],
  ["lote tira 3", P([3])],
  ["Lote tirando 18, 19 e 20", P([18, 19, 20])],
  ["lote sem avisos", P([], ["aviso"])],
  ["lote sem alertas e transferência", P([], ["aviso", "transferencia"])],
  ["lote sem os avisos e o 3", P([3], ["aviso"])],
  ["lote só despesas", P([], [], ["despesa"])],
  ["lote somente despesas e transferências", P([], [], ["despesa", "transferencia"])],
];

const NAO_SAO_COMANDO = [
  // dos comprovantes
  "lote antigo", "lotes antigos",
  // frases e números soltos
  "lote de peças chegou", "o lote do fornecedor", "lote sem", "lote sem nada", "lote só 3", "lote sem 0", "lote sem 3 cobras",
  "3", "sem 3", "tira 3", "loteamento",
  // confirmação
  "sim", "não", "1", "2", "ok",
];

Deno.test("lerComandoDoSecretario (Passo 5): o lote e os recortes", () => {
  for (const [texto, esperado] of COMANDOS) assertEquals(lerComandoDoSecretario(texto), esperado, texto);
});

Deno.test("lerComandoDoSecretario (Passo 5): o que não é o comando do lote", () => {
  for (const t of NAO_SAO_COMANDO) {
    const c = lerComandoDoSecretario(t);
    assertEquals(c?.comando === "papelada" ? c : null, null, t);
  }
  // "lote antigo" continua dos comprovantes
  assertEquals(lerComando("lote antigo"), { comando: "lote_antigo" });
});

Deno.test("nenhum comando do lote é confirmação, opção de menu, comando dos comprovantes nem resposta curta", () => {
  for (const [texto] of COMANDOS) {
    assertEquals(parseConfirmationReply(texto), null, `confirmação: ${texto}`);
    assertEquals(parseOptionReply(texto, 99), null, `opção: ${texto}`);
    assertEquals(lerComando(texto), null, `comprovantes: ${texto}`);
    const n = normalizarResposta(texto);
    assertEquals(lerSimNao(n), null, `sim/não/ok: ${texto}`);
    assertEquals(lerNumero(n, 99), null, `número: ${texto}`);
    assertEquals(pareceRespostaCurta(texto), false, `resposta curta: ${texto}`);
  }
});

Deno.test("as letras da manhã e a revisão continuam como antes ('tira B', 'C semana, B tira', 'L' sozinho)", () => {
  assertEquals(lerComandoDoSecretario("tira B"), { comando: "acao", letra: "B", acao: "tirado" });
  assertEquals(lerComandoDoSecretario("l"), { comando: "abrir", letra: "L" });
  assertEquals(lerComandoDoSecretario("C semana, B tira")?.comando, "lote");
});
