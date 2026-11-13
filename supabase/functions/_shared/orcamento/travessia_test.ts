// Retorno rápido, F5 (P14): a metade da travessia que roda na CI. A outra metade, com banco, é
// supabase/tests/retorno_f5_travessia.sql (bancada, grupo 8, onda 9). Três portões:
//  1. as palavras do dono que a travessia usa, na ordem das camadas do ai-agent (orçamento → parceiro → retorno), contra os
//     leitores reais que ficam fora de _shared/ai/: a do orçamento é lida só pelo leitor da F5; as letras, o *não N*, o *ver N*
//     e o *sim <PIN>* passam reto pelas camadas do orçamento e do parceiro e chegam à do retorno; o que não é de ninguém não é
//     de nenhuma das três. Os leitores de _shared/ai/ (confirmação, opção, PDF, reply-router) ficam em
//     _shared/whatsapp/orcamento-comandos_test.ts: esta pasta não importa _shared/ai/, nem nos testes;
//  2. a camada do orçamento nunca chama o modelo: só a RPC orcamento_dito, uma vez por palavra; o que não é palavra do orçamento
//     segue sem banco e sem perguntar o dono; erro, exceção e função ausente dão a frase fixa (nunca null: null mandaria a
//     palavra ao modelo); e o código da camada e do leitor não tem cliente de modelo nem chamada de rede;
//  3. nenhum .ts de _shared/orcamento/ importa _shared/ai/ (o portão 1 do isolamento_test.ts, só desta pasta, testes inclusive).
// Frases e números inventados (os ORÇ-999xx da travessia SQL); o 7391 também é inventado.
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { dirname, fromFileUrl, join, resolve } from "https://deno.land/std@0.224.0/path/mod.ts";
import { camadaDoOrcamento, type DependenciasDoOrcamento, R_ORCAMENTO } from "./camada.ts";
import { lerComandoDoOrcamento } from "./comandos.ts";
import { lerComandoDoRetorno } from "../retorno/comandos.ts";
import { lerComandoDoParceiro } from "../parceiro/comandos.ts";
import { lerComandoDaAgenda } from "../agenda/comandos.ts";
import { lerComandoDoSecretario } from "../secretario/comandos.ts";
import { lerComando } from "../comprovantes/respostas.ts";
import { ehPedidoDeParar } from "../whatsapp/parar.ts";

/** As palavras do orçamento da travessia (cenários 3 e 6) e o comando que vai ao banco. */
const DO_ORCAMENTO: Array<[string, Record<string, unknown>]> = [
  ["segura 99907", { comando: "segura", numero: 99907 }],
  ["*Segura ORÇ-99907*", { comando: "segura", numero: 99907 }],
  ["solta 99907", { comando: "solta", numero: 99907 }],
  ["motivo 99904 B", { comando: "motivo", numero: 99904, letra: "B" }],
  ["motivo 99904 outra empresa", { comando: "motivo", numero: 99904, letra: "B" }],
  ["segura orçamentos", { comando: "segura_todos" }],
  ["solta orcamentos", { comando: "solta_todos" }],
];

/** O que a travessia manda ao cartão (cenários 1, 7, 15 e 16): é do retorno (F2), nunca do orçamento nem do parceiro. */
const DO_RETORNO: Array<[string, string]> = [
  ["1 b", "escolher"],
  ["1 B sim 7391", "escolher"],
  ["1 c", "escolher"],
  ["2 a", "escolher"],
  ["nao 1", "tirar"],
  ["ver 1", "ver"],
  ["resolvido 1", "resolvido"],
  ["errado z", "errado"],
];

/** Não é de nenhuma das três camadas (a matriz 7.2: "segura 1", "segura", "motivo N e", "enviado 1"). */
const DE_NINGUEM = ["segura 1", "segura", "motivo 99904 e", "enviado 1", "segura 99907?"];

Deno.test("P14: as palavras do orçamento da travessia são lidas só pelo leitor da F5", () => {
  for (const [frase, comando] of DO_ORCAMENTO) {
    assertEquals(lerComandoDoOrcamento(frase), comando, frase);
    assertEquals(lerComandoDoParceiro(frase), null, `parceiro: ${frase}`);
    assertEquals(lerComandoDoRetorno(frase), null, `retorno: ${frase}`);
    assertEquals(lerComandoDaAgenda(frase), null, `agenda: ${frase}`);
    assertEquals(lerComandoDoSecretario(frase), null, `secretário: ${frase}`);
    assertEquals(lerComando(frase), null, `comprovantes: ${frase}`);
    assertEquals(ehPedidoDeParar(frase), false, `parar: ${frase}`);
  }
});

Deno.test("P14: a letra, o *não N*, o *ver N* e o *sim <PIN>* do cartão passam pelo orçamento e pelo parceiro e chegam ao retorno", () => {
  for (const [frase, comando] of DO_RETORNO) {
    assertEquals(lerComandoDoOrcamento(frase), null, `orçamento: ${frase}`);
    assertEquals(lerComandoDoParceiro(frase), null, `parceiro: ${frase}`);
    assertEquals(lerComandoDoRetorno(frase)?.comando, comando, `retorno: ${frase}`);
  }
});

Deno.test("P14: o que não é de ninguém não é de nenhuma das três camadas", () => {
  for (const frase of DE_NINGUEM) {
    assertEquals(lerComandoDoOrcamento(frase), null, `orçamento: ${frase}`);
    assertEquals(lerComandoDoParceiro(frase), null, `parceiro: ${frase}`);
    assertEquals(lerComandoDoRetorno(frase), null, `retorno: ${frase}`);
  }
});

type Registro = { rpcs: Array<{ fn: string; args: Record<string, unknown> }>; donos: number };

function deps(rpc?: DependenciasDoOrcamento["rpc"]): { d: DependenciasDoOrcamento; reg: Registro } {
  const reg: Registro = { rpcs: [], donos: 0 };
  return {
    reg,
    d: {
      autor: "dono-da-travessia",
      ehDoDono: () => {
        reg.donos++;
        return Promise.resolve(true);
      },
      rpc: rpc ?? ((fn, args) => {
        reg.rpcs.push({ fn, args });
        return Promise.resolve({ data: { ok: true, texto: "Feito (texto de teste)." }, error: null });
      }),
    },
  };
}

Deno.test("P14: a camada do orçamento só chama orcamento_dito, uma vez por palavra, e o resto segue sem banco", async () => {
  for (const [frase, comando] of DO_ORCAMENTO) {
    const { d, reg } = deps();
    const r = await camadaDoOrcamento(frase, d);
    assertEquals(reg.rpcs, [{ fn: "orcamento_dito", args: { p_comando: comando, p_autor: "dono-da-travessia" } }], frase);
    assertEquals(r?.texto, "Feito (texto de teste).", frase);
    assertEquals(r?.noHistorico, null, frase);
  }
  for (const frase of [...DO_RETORNO.map(([f]) => f), ...DE_NINGUEM]) {
    const { d, reg } = deps();
    assertEquals(await camadaDoOrcamento(frase, d), null, frase);
    assertEquals(reg.rpcs.length, 0, frase);
    assertEquals(reg.donos, 0, frase);
  }
});

Deno.test("P14: erro, exceção e função ausente dão a frase fixa — a palavra do orçamento nunca vai ao modelo", async () => {
  const falhas: Array<DependenciasDoOrcamento["rpc"]> = [
    () => Promise.resolve({ data: null, error: { code: "PGRST202" } }),
    () => Promise.resolve({ data: null, error: { code: "42883" } }),
    () => Promise.reject(new Error("rede fora")),
    () => Promise.resolve({ data: { ok: true }, error: null }),
  ];
  for (const rpc of falhas) {
    for (const [frase] of DO_ORCAMENTO) {
      const { d } = deps(rpc);
      const r = await camadaDoOrcamento(frase, d);
      assert(r !== null, `null mandaria ao modelo: ${frase}`);
      assertEquals(r.texto, R_ORCAMENTO, frase);
    }
  }
});

const AQUI = dirname(fromFileUrl(import.meta.url)); // supabase/functions/_shared/orcamento
const AI = resolve(AQUI, "..", "ai").replaceAll("\\", "/").toLowerCase();

/** O código sem os comentários (o texto "nada vai ao modelo" dos comentários não conta). */
function semComentarios(fonte: string): string {
  return fonte.replace(/\/\*[\s\S]*?\*\//g, "").split("\n").map((l) => l.replace(/^\s*\/\/.*$/, "")).join("\n");
}

Deno.test("P14: a camada e o leitor do orçamento não têm cliente de modelo nem chamada de rede", async () => {
  for (const arq of ["camada.ts", "comandos.ts"]) {
    const codigo = semComentarios(await Deno.readTextFile(join(AQUI, arq)));
    for (const proibido of [/\bfetch\s*\(/, /anthropic/i, /openai/i, /\/v1\/messages/, /\bai_jobs\b/, /chamarModelo|chamarClaude|callClaude/]) {
      assert(!proibido.test(codigo), `${arq}: ${proibido}`);
    }
    // A única saída da camada é a RPC que chega por parâmetro.
    if (arq === "camada.ts") assert(codigo.includes(`deps.rpc("orcamento_dito"`), "a camada chama só orcamento_dito");
  }
});

Deno.test("P14: nenhum .ts de _shared/orcamento/ importa _shared/ai/ (testes inclusive)", async () => {
  let vistos = 0;
  for await (const e of Deno.readDir(AQUI)) {
    if (!e.isFile || !e.name.endsWith(".ts")) continue;
    vistos++;
    const fonte = await Deno.readTextFile(join(AQUI, e.name));
    for (const m of fonte.matchAll(/\b(?:from|import)\s*\(?\s*["']([^"']+)["']/g)) {
      const esp = m[1];
      const alvo = esp.startsWith(".") ? resolve(AQUI, esp).replaceAll("\\", "/").toLowerCase() : esp.replaceAll("\\", "/").toLowerCase();
      assert(!(alvo === AI || alvo.startsWith(AI + "/") || alvo.includes("_shared/ai/")), `${e.name} importa ${esp}`);
    }
  }
  assert(vistos >= 5, `a varredura achou só ${vistos} arquivos (o filtro quebrou)`);
});
