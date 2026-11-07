// O cartão do retorno (F2, P8.6): a ferramenta da pendência, com banco falso. Frases e telefones inventados.
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { type EnviarDitado, executarCartao, NOME_DA_TOOL_DO_CARTAO, retornoSoPelaPendencia } from "./retorno.ts";
import { allTools, toolsByName } from "./index.ts";
import { textoDoSim } from "../agent.ts";
import type { ToolCtx } from "./registry.ts";

type Chamada = { fn: string; args: Record<string, unknown> };

function ctx(resposta: unknown, erro: unknown = null): { c: ToolCtx; chamadas: Chamada[] } {
  const chamadas: Chamada[] = [];
  const admin = {
    rpc: (fn: string, args: Record<string, unknown>) => {
      chamadas.push({ fn, args });
      if (fn === "retorno_cartao_executar") return Promise.resolve({ data: resposta, error: erro });
      return Promise.resolve({ data: { ok: true }, error: null });
    },
  };
  return { c: { admin, sb: admin, userId: "dono", userRole: "admin", jwt: "", appOrigin: "", settings: {} } as unknown as ToolCtx, chamadas };
}

const DITADO = { item_id: "i-1", phone: "5547900009502", texto: "Pode buscar amanhã", dedupe_key: "retorno:c:ditado:h" };

Deno.test("a ferramenta fica fora da lista do modelo e dentro do mapa de execução", () => {
  assertEquals(allTools.some((t) => t.name === NOME_DA_TOOL_DO_CARTAO), false);
  assertEquals(toolsByName[NOME_DA_TOOL_DO_CARTAO]?.risk, "high");
  assertEquals(toolsByName[NOME_DA_TOOL_DO_CARTAO]?.roles, ["admin"]);
  assertEquals(Object.keys(retornoSoPelaPendencia[0].input_schema.properties as object), ["cartao_id"]);
});

Deno.test("um ditado sai pelo telefone do banco, e depois o item é fechado; telefone em args é ignorado", async () => {
  const { c, chamadas } = ctx({ ok: true, aviso: "Vai sair 1: Paulo.", ditados: [DITADO], vai_sair: 1 });
  const enviados: unknown[][] = [];
  const enviar: EnviarDitado = (...a) => {
    enviados.push(a);
    return Promise.resolve({ ok: true, messageId: "wa-1" });
  };
  const r = await executarCartao({ cartao_id: "c-1", to_phone: "5547999999999", phone: "5547999999999" }, c, enviar);
  assertEquals(enviados, [["5547900009502", "Pode buscar amanhã", "", "retorno:c:ditado:h", "dono"]]);
  assertEquals(chamadas.map((x) => x.fn), ["retorno_cartao_executar", "retorno_item_enviado"]);
  assertEquals(chamadas[1].args, { p_item: "i-1", p_ok: true, p_wa_id: "wa-1" });
  assertEquals(r, { ok: true, aviso: "Vai sair 1: Paulo.", so_texto: true });
});

Deno.test("envio que falha aparece no aviso e devolve o item", async () => {
  const { c, chamadas } = ctx({ ok: true, aviso: "Vai sair 1: Paulo.", ditados: [DITADO] });
  const r = await executarCartao({ cartao_id: "c-1" }, c, () => Promise.resolve({ error: "HTTP 500" }));
  assertEquals(r.aviso, "Vai sair 1: Paulo. Um ditado não saiu: responda pelo celular.");
  assertEquals(chamadas[1].args, { p_item: "i-1", p_ok: false, p_wa_id: null });
  const lanca = await executarCartao({ cartao_id: "c-1" }, ctx({ ok: true, ditados: [DITADO] }).c, () => Promise.reject(new Error("rede")));
  assertEquals(lanca.aviso, "Um ditado não saiu: responda pelo celular.");
});

Deno.test("sem ditado, nada é enviado; erro do banco e cartão decidido viram erro, sem envio", async () => {
  let envios = 0;
  const conta: EnviarDitado = () => {
    envios++;
    return Promise.resolve({ ok: true });
  };
  assertEquals((await executarCartao({ cartao_id: "c-1" }, ctx({ ok: true, aviso: "Vai sair 1: Rodrigo.", ditados: [] }).c, conta)).so_texto, true);
  assertEquals(await executarCartao({ cartao_id: "c-1" }, ctx(null, { code: "57014" }).c, conta), { error: "Não consegui executar o cartão agora." });
  assertEquals(await executarCartao({ cartao_id: "c-1" }, ctx({ ok: false, aviso: "Esse cartão já foi decidido." }).c, conta), { error: "Esse cartão já foi decidido." });
  assertEquals(await executarCartao({}, ctx({ ok: true }).c, conta), { error: "Não consegui executar o cartão agora." });
  assertEquals(envios, 0);
});

Deno.test("o sim do cartão não diz executado: traz só o aviso", () => {
  const t = textoDoSim("Cartão do retorno", { ok: true, aviso: "Vai sair 2: Rodrigo, Paulo.", so_texto: true });
  assertEquals(t, "Vai sair 2: Rodrigo, Paulo.");
  assert(!t.includes("executado"));
  assert(textoDoSim("Outra", { ok: true }).includes("executado"));
});
