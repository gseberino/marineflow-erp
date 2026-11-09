// Retorno rápido, F2 (P3.6): a camada, com banco falso. Fica fora de _shared/retorno/ pelo mesmo motivo da matriz.
// Frases e números inventados.
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  c13,
  camadaDoRetorno,
  type CartaoVivo,
  type DependenciasDaCamada,
  DITADO_LONGO,
  ehPalavraDoRetornoLigada,
  PIN_NAO_VALE,
  ponteiroDoCartao,
  R13,
  r14,
  R15,
  SO_CONSULTA,
} from "../retorno/camada.ts";
import { parseConfirmationReply } from "../ai/whatsapp-channel.ts";

const CARTAO: CartaoVivo = { id: "c-1", estado: "vivo", pendencia_id: "p-1", letras: { "1": ["A", "B"], "2": [], "3": ["B", "C"] } };
const LISTA: CartaoVivo = { id: "c-2", estado: "lista", pendencia_id: null, letras: { "1": [], "2": [] } };

type Registro = { rpcs: Array<{ fn: string; args: Record<string, unknown> }>; confirmados: string[] };

function deps(
  o: Partial<DependenciasDaCamada> & { cartao?: CartaoVivo | null; ponteiroAtual?: string | null; resposta?: unknown } = {},
): { d: DependenciasDaCamada; reg: Registro } {
  const reg: Registro = { rpcs: [], confirmados: [] };
  const d: DependenciasDaCamada = {
    ehDoDono: o.ehDoDono ?? (() => Promise.resolve(true)),
    rpc: o.rpc ?? ((fn, args) => {
      reg.rpcs.push({ fn, args });
      return Promise.resolve({ data: o.resposta ?? { ok: true, texto: "feito" }, error: null });
    }),
    cartaoVivo: o.cartaoVivo ?? (() => Promise.resolve(o.cartao === undefined ? CARTAO : o.cartao)),
    ponteiro: o.ponteiro ?? (() => Promise.resolve(o.ponteiroAtual === undefined ? "p-1" : o.ponteiroAtual)),
    tituloDoPonteiro: o.tituloDoPonteiro ?? (() => Promise.resolve("Enviar lembrete")),
    confirmar: o.confirmar ?? ((pin) => {
      reg.confirmados.push(pin);
      return Promise.resolve();
    }),
  };
  return { d, reg };
}

Deno.test("cada palavra chama a RPC certa, uma vez, e nunca com o PIN", async () => {
  const casos: Array<[string, string]> = [
    ["retorno", "retorno_dito"], ["segura tudo", "retorno_dito"], ["solta recibos", "retorno_dito"], ["fora até quarta", "retorno_dito"],
    ["libera Rodrigo", "retorno_dito"], ["errado Z", "retorno_dito"], ["pessoal", "retorno_dito"], ["pessoal não", "retorno_dito"],
    ["pessoal 2", "retorno_dito"], ["ver 1", "retorno_dito"],
    ["1 B", "retorno_decidir_dito"], ["só 3", "retorno_decidir_dito"], ["sim sem 2", "retorno_decidir_dito"], ["não 2", "retorno_decidir_dito"],
    ["dita 2 pode buscar", "retorno_decidir_dito"], ["1 A sim 7391", "retorno_decidir_dito"], ["só 3 sim 7391", "retorno_decidir_dito"],
  ];
  for (const [texto, fn] of casos) {
    const { d, reg } = deps();
    await camadaDoRetorno(texto, d);
    assertEquals(reg.rpcs.length, 1, texto);
    assertEquals(reg.rpcs[0].fn, fn, texto);
    assert(!JSON.stringify(reg.rpcs[0].args).includes("7391"), `PIN na RPC: ${texto}`);
  }
});

Deno.test("quem não é o dono, ou sem saber quem é: null", async () => {
  assertEquals(await camadaDoRetorno("retorno", deps({ ehDoDono: () => Promise.resolve(false) }).d), null);
  assertEquals(await camadaDoRetorno("retorno", deps({ ehDoDono: () => Promise.reject(new Error("x")) }).d), null);
  assertEquals(await camadaDoRetorno("segura tudo", deps({ resposta: { ok: false, motivo: "nao_e_o_dono" } }).d), null);
});

Deno.test("o que não é palavra nem chega ao banco", async () => {
  const { d, reg } = deps();
  for (const t of ["bom dia", "2 baterias", "2 dias", "sim 7391", "não", "1 A 7391"]) assertEquals(await camadaDoRetorno(t, d), null, t);
  assertEquals(reg.rpcs.length, 0);
});

Deno.test("função ausente no banco: null, o ai-agent pode subir antes das migrations", async () => {
  const ausente = { code: "PGRST202" };
  assertEquals(await camadaDoRetorno("retorno", deps({ rpc: () => Promise.resolve({ data: null, error: ausente }) }).d), null);
  assertEquals(await camadaDoRetorno("segura tudo", deps({ rpc: () => Promise.resolve({ data: null, error: { code: "42883" } }) }).d), null);
  assertEquals(await camadaDoRetorno("1 A", deps({ cartaoVivo: () => Promise.reject(ausente) }).d), null);
  assertEquals(await camadaDoRetorno("1 A sim 7391", deps({ cartaoVivo: () => Promise.reject(ausente) }).d), null);
});

Deno.test("comando de cartão sem cartão: null; com PIN, R13 e nunca ao modelo", async () => {
  const sem = { cartao: null };
  for (const t of ["1 B", "só 3", "não 2", "sim sem 2", "ver 1", "pessoal 2", "dita 2 ok"]) {
    assertEquals(await camadaDoRetorno(t, deps(sem).d), null, t);
  }
  for (const t of ["1 A sim 7391", "só 3 sim 7391", "sim 7391 sem 2"]) {
    assertEquals((await camadaDoRetorno(t, deps(sem).d))?.texto, R13, t);
  }
});

Deno.test("letra fora do item: conversa; com PIN, R14", async () => {
  assertEquals(await camadaDoRetorno("2 H", deps().d), null);
  assertEquals(await camadaDoRetorno("1 C", deps().d), null);
  assertEquals((await camadaDoRetorno("1 C sim 7391", deps().d))?.texto, r14(1, "C"));
  const { d, reg } = deps();
  assertEquals((await camadaDoRetorno("3 B", d))?.texto, "feito");
  assertEquals(reg.rpcs[0].args, { p_comando: { comando: "escolher", n: 3, letra: "B", resto: null } });
});

Deno.test("lista: só ver e pessoal", async () => {
  for (const t of ["só 1", "não 1", "dita 1 ok", "sim sem 1"]) {
    assertEquals((await camadaDoRetorno(t, deps({ cartao: LISTA }).d))?.texto, SO_CONSULTA, t);
  }
  for (const t of ["ver 1", "pessoal 1"]) assertEquals((await camadaDoRetorno(t, deps({ cartao: LISTA }).d))?.texto, "feito", t);
});

Deno.test("o 2 B com pendência não chega à confirmação: a camada responde antes", async () => {
  const r = await camadaDoRetorno("2 B", deps({ cartao: { ...CARTAO, letras: { "2": ["B"] } } }).d);
  assertEquals(r?.texto, "feito");
  // e, passando direto, nem a confirmação o lê como recusa
  assertEquals(parseConfirmationReply("2 B"), null);
});

Deno.test("ponteiro em outra pendência: C13, sem confirmar e sem gastar tentativa", async () => {
  const { d, reg } = deps({ ponteiroAtual: "outra" });
  assertEquals((await camadaDoRetorno("só 3 sim 7391", d))?.texto, c13("Enviar lembrete"));
  assertEquals(reg.confirmados, []);
  const precisa = deps({ ponteiroAtual: "outra", resposta: { ok: true, texto: "*sim <PIN>* manda", precisa_pin: true } });
  assertEquals((await camadaDoRetorno("só 3", precisa.d))?.texto, c13("Enviar lembrete"));
  assertEquals(precisa.reg.confirmados, []);
});

Deno.test("PIN com o ponteiro certo vai à confirmação de sempre, e a resposta já foi enviada por ela", async () => {
  const { d, reg } = deps();
  const r = await camadaDoRetorno("só 3 sim 0000", d);
  assertEquals(reg.confirmados, ["0000"]);
  assertEquals(r?.jaEnviado, true);
  assertEquals(reg.rpcs[0].fn, "retorno_decidir_dito");
  const sem = deps({ resposta: { ok: true, texto: "*sim <PIN>* manda", precisa_pin: true } });
  assertEquals((await camadaDoRetorno("só 3", sem.d))?.texto, "*sim <PIN>* manda");
  assertEquals(sem.reg.confirmados, []);
});

Deno.test("erro de RPC: R15, sem ir ao modelo", async () => {
  const erro = { rpc: () => Promise.resolve({ data: null, error: { code: "57014" } }) };
  for (const t of ["segura tudo", "1 A sim 7391", "só 3"]) {
    const r = await camadaDoRetorno(t, deps(erro).d);
    assertEquals(r?.texto, R15, t);
    assertEquals(r?.noHistorico, null, t);
  }
  assertEquals((await camadaDoRetorno("só 3", deps({ cartaoVivo: () => Promise.reject({ code: "57014" }) }).d))?.texto, R15);
  assertEquals((await camadaDoRetorno("retorno", deps({ rpc: () => Promise.reject(new Error("rede")) }).d))?.texto, R15);
  assertEquals((await camadaDoRetorno("retorno", deps({ resposta: { ok: true } }).d))?.texto, R15);
  assertEquals((await camadaDoRetorno("só 3 sim 7391", deps({ confirmar: () => Promise.reject(new Error("x")) }).d))?.texto, R15);
});

Deno.test("seguir_ao_modelo: null", async () => {
  assertEquals(await camadaDoRetorno("libera Carlos", deps({ resposta: { ok: false, seguir_ao_modelo: true } }).d), null);
  assertEquals(await camadaDoRetorno("pessoal", deps({ resposta: { ok: false, seguir_ao_modelo: true } }).d), null);
});

Deno.test("o ditado longo é recusado com o motivo, antes do banco", async () => {
  const { d, reg } = deps();
  assertEquals((await camadaDoRetorno(`dita 2 ${"a".repeat(1050)}`, d))?.texto, DITADO_LONGO);
  assertEquals(reg.rpcs.length, 0);
});

Deno.test("noHistorico vem do banco; o texto ao dono pode ter o pedido do cliente, o histórico não", async () => {
  const historico = { user: "(ver 2)", assistant: "(mostrei o caso 2 ao dono)" };
  const r = await camadaDoRetorno("ver 2", deps({ resposta: { ok: true, texto: "13:00 'FRASE-MARCADA'", historico } }).d);
  assertEquals(r?.noHistorico, historico);
  assert(!JSON.stringify(r?.noHistorico).includes("FRASE-MARCADA"));
  assertEquals((await camadaDoRetorno("retorno", deps({ resposta: { ok: true, texto: "t", cartao_id: "c-9" } }).d))?.cartaoId, "c-9");
});

Deno.test("ponteiroDoCartao: repõe só com o ponteiro vazio, cartão vivo e texto de confirmação", async () => {
  const eh = (t: string) => parseConfirmationReply(t) !== null;
  assertEquals(await ponteiroDoCartao("sim 7391", { a: 1 }, deps().d, eh),
    { a: 1, pending_confirm_action_id: "p-1", pin_attempts: 0, pendencia_herdada: false });
  assertEquals(await ponteiroDoCartao("sim 7391", { pending_confirm_action_id: "outra" }, deps().d, eh), null);
  assertEquals(await ponteiroDoCartao("bom dia", {}, deps().d, eh), null);
  assertEquals(await ponteiroDoCartao("sim 7391", {}, deps({ cartao: LISTA }).d, eh), null);
  assertEquals(await ponteiroDoCartao("sim 7391", {}, deps({ cartao: null }).d, eh), null);
  assertEquals(await ponteiroDoCartao("sim 7391", {}, deps({ ehDoDono: () => Promise.resolve(false) }).d, eh), null);
  assertEquals(await ponteiroDoCartao("sim 7391", {}, deps({ cartaoVivo: () => Promise.reject(new Error("x")) }).d, eh), null);
});

Deno.test("ehPalavraDoRetornoLigada: a de cartão só com cartão vivo; erro = false; nunca lança", async () => {
  const banco = (data: unknown, error: unknown = null) => ({ rpc: () => Promise.resolve({ data, error }) });
  assertEquals(await ehPalavraDoRetornoLigada(banco(CARTAO), "1 b"), true);
  assertEquals(await ehPalavraDoRetornoLigada(banco(null), "1 b"), false);
  assertEquals(await ehPalavraDoRetornoLigada(banco(null), "retorno"), true);
  assertEquals(await ehPalavraDoRetornoLigada(banco(null, { code: "PGRST202" }), "retorno"), false);
  assertEquals(await ehPalavraDoRetornoLigada(banco(null), "bom dia"), false);
  assertEquals(await ehPalavraDoRetornoLigada({ rpc: () => Promise.reject(new Error("x")) }, "retorno"), false);
});


// Revisão da F3: a letra que troca a proposta ou a unidade mostra linhas novas. O PIN na mesma mensagem não vale sobre o que o dono não leu.
Deno.test("1 B sim <PIN> não confirma: devolve as linhas novas e pede o PIN sozinho, sem levar o PIN a lugar nenhum", async () => {
  const linhas = "1. Ana · proposta com base no ORÇ-00071 · R$ 1.800";
  const { d, reg } = deps({ resposta: { ok: true, pin_nao_vale: true, texto: linhas } });
  const r = await camadaDoRetorno("1 B sim 7391", d);
  assertEquals(reg.confirmados, []);
  assertEquals(r?.jaEnviado, undefined);
  assertEquals(r?.texto, `${linhas}\n${PIN_NAO_VALE}`);
  assert(!JSON.stringify(r).includes("7391"));
  assert(!JSON.stringify(reg.rpcs).includes("7391"));
});

Deno.test("1 C sim <PIN> (letra de unidade) e 1 B que não trocou nada: o PIN também não vale", async () => {
  for (const [texto, resposta] of [
    ["3 C sim 7391", { ok: true, pin_nao_vale: true, texto: "3. Ana · Brisa · R$ 500" }],
    ["1 B sim 7391", { ok: true, pin_nao_vale: true, texto: "Não consegui usar esse orçamento: nada mudou." }],
  ] as Array<[string, Record<string, unknown>]>) {
    const { d, reg } = deps({ resposta });
    const r = await camadaDoRetorno(texto, d);
    assertEquals(reg.confirmados, [], texto);
    assert(r?.texto.startsWith(String(resposta.texto)), texto);
    assert(r?.texto.endsWith(PIN_NAO_VALE), texto);
  }
});

Deno.test("sem PIN, a marca não muda nada: o dono só vê as linhas", async () => {
  const { d, reg } = deps({ resposta: { ok: true, pin_nao_vale: true, texto: "as linhas" } });
  assertEquals((await camadaDoRetorno("1 B", d))?.texto, "as linhas");
  assertEquals(reg.confirmados, []);
});

Deno.test("letra de texto fixo, como 1 L sim <PIN>, segue confirmando", async () => {
  const cartao: CartaoVivo = { ...CARTAO, letras: { "1": ["L"] } };
  const { d, reg } = deps({ cartao, resposta: { ok: true, precisa_pin: true, texto: "Vou mandar" } });
  const r = await camadaDoRetorno("1 L sim 7391", d);
  assertEquals(reg.confirmados, ["7391"]);
  assertEquals(r?.jaEnviado, true);
});
