// Retorno F4 (P12.3): a ferramenta do cartão do parceiro, só pela pendência, com banco falso. Telefones e nomes inventados.
import { assert, assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { FakeTime } from "https://deno.land/std@0.224.0/testing/time.ts";
import { executarCartaoDoParceiro, NOME_DA_TOOL_DO_CARTAO_PARCEIRO, parceiroSoPelaPendencia } from "./parceiro.ts";
import { allTools, toolsByName, toolsSoPelaPendencia } from "./index.ts";
import type { DepsDoCartao } from "./retorno.ts";
import type { ToolCtx } from "./registry.ts";
import { PERFIL_ADMIN } from "../perfil-operacao.ts";
import { isAutonomyGranted, NEVER_AUTONOMOUS } from "../autonomy-policy.ts";
import { textoDoSim } from "../agent.ts";
import { TITULOS_DA_REDE_DO_ADMIN } from "../rotulos.ts";

type Chamada = { fn: string; args: Record<string, unknown> };

function fluxo(rotas: Record<string, unknown> = {}) {
  const chamadas: Chamada[] = [];
  const admin = {
    rpc: (fn: string, args: Record<string, unknown>) => {
      chamadas.push({ fn, args });
      const v = rotas[fn];
      if (typeof v === "function") return Promise.resolve((v as (a: unknown) => unknown)(args));
      if (v && typeof v === "object" && "__erro" in (v as Record<string, unknown>)) return Promise.resolve({ data: null, error: { message: (v as { __erro: string }).__erro } });
      return Promise.resolve({ data: v === undefined ? { ok: true } : v, error: null });
    },
    from: () => {
      const q: Record<string, unknown> = {
        select: () => q, eq: () => q, maybeSingle: () => Promise.resolve({ data: null, error: null }),
        then: (ok: (v: unknown) => unknown) => Promise.resolve({ data: [], error: null }).then(ok),
      };
      return q;
    },
  };
  const c = { admin, sb: admin, userId: "dono", userRole: "admin", jwt: "", appOrigin: "", settings: {} } as unknown as ToolCtx;
  return { c, chamadas, nomes: () => chamadas.map((x) => x.fn) };
}

function depsFalsos(c: { chamadas: Chamada[] }, envio: Record<string, unknown> = { ok: true, destino_chave8: "99994321" }) {
  const enviados: Array<Record<string, unknown>> = [];
  const deps: DepsDoCartao = {
    montarOrcamento: ((args: Record<string, unknown>) => {
      c.chamadas.push({ fn: "montar", args });
      return Promise.resolve({ ok: true, orcamento: "ORÇ-00151", service_order_id: "os-1", total: 8040 });
    }) as DepsDoCartao["montarOrcamento"],
    enviarPdf: (args: Record<string, unknown>) => {
      c.chamadas.push({ fn: "enviar_pdf", args });
      enviados.push(args);
      return Promise.resolve(envio);
    },
  };
  return { deps, enviados };
}

const MEIO_DIA = "2027-01-20T15:00:00.000Z";
async function comRelogio<T>(fn: () => Promise<T>): Promise<T> {
  const t = new FakeTime(MEIO_DIA);
  try {
    return await fn();
  } finally {
    t.restore();
  }
}

const LEGENDA_P16 = {
  texto: "Oi, Carla! Segue o orçamento do motorhome de João, válido até 15/01.",
  contexto: {
    audiencia: "parceiro", datas_permitidas: ["15/01"], horas_permitidas: [], nome_permitido: "Carla", nomes_de_outros: [],
    nomes_da_lista: ["João"], papel_do_parceiro: "contratante", os_permitidas: [], textos_do_cliente: [],
    trechos_do_modelo: ["Oi, ", "! Segue o orçamento do ", " de ", ", válido até ", "."],
    marcas: { tem_proposta: false, tem_topo: false, cliente_ouviu: false, conferida: false },
  },
  validade_data: "2027-01-27",
};
const PRE = {
  ok: true, acao: "orcar", previa_id: "pv-1", abertura_id: "a-1", rotulo: "MP (Carla)", chave8: "12345678", total: 8040, validade_data: "2027-01-27",
  numero: null, parceiro_id: "pa-1", legenda: LEGENDA_P16,
  args: { client_id: "c-1", vessel_id: "v-1", title: "Bateria", items: [{ product_id: "p-1", quantity: 1, unit_price: 8040, keyword: "Bateria" }], labor: [], payment_conditions: null, origem: "retorno_parceiro" },
};
const ORC = (extra: Record<string, unknown> = {}) => ({
  item_id: "pi-1", n: 1, pedido_id: "pe-1", previa_id: "pv-1", acao: "orcar", service_order_id: null, numero: null, destino: "parceiro",
  parceiro_id: "pa-1", sem_enviar: false, rotulo: "MP (Carla)", ...extra,
});

Deno.test("a ferramenta fica fora da lista do modelo e do PERFIL_ADMIN, dentro do mapa de execução, alta e só do admin", () => {
  assertEquals(NOME_DA_TOOL_DO_CARTAO_PARCEIRO, "parceiro_executar_cartao");
  assertEquals(allTools.some((t) => t.name === NOME_DA_TOOL_DO_CARTAO_PARCEIRO), false);
  assertEquals(toolsSoPelaPendencia.some((t) => t.name === NOME_DA_TOOL_DO_CARTAO_PARCEIRO), true);
  assertEquals(toolsByName[NOME_DA_TOOL_DO_CARTAO_PARCEIRO]?.risk, "high");
  assertEquals(toolsByName[NOME_DA_TOOL_DO_CARTAO_PARCEIRO]?.roles, ["admin"]);
  assertEquals(Object.keys(parceiroSoPelaPendencia[0].input_schema.properties as object), ["cartao_id"]);
  assertEquals(PERFIL_ADMIN.has(NOME_DA_TOOL_DO_CARTAO_PARCEIRO), false);
  assertEquals(NEVER_AUTONOMOUS.has(NOME_DA_TOOL_DO_CARTAO_PARCEIRO), true);
  assertEquals(isAutonomyGranted(NOME_DA_TOOL_DO_CARTAO_PARCEIRO, "high", { ai_autonomy_parceiro_executar_cartao: "auto" }), false);
  assertEquals(TITULOS_DA_REDE_DO_ADMIN[NOME_DA_TOOL_DO_CARTAO_PARCEIRO], "Cartão do parceiro");
});

Deno.test("erro do banco, cartão decidido e sem cartão viram erro, sem nada mais", async () => {
  const erro = fluxo({ parceiro_cartao_executar: { __erro: "57014" } });
  assertEquals(await executarCartaoDoParceiro({ cartao_id: "cp-1" }, erro.c), { error: "Não consegui executar o cartão do parceiro agora." });
  const decidido = fluxo({ parceiro_cartao_executar: { ok: false, aviso: "Esse cartão já foi decidido." } });
  assertEquals(await executarCartaoDoParceiro({ cartao_id: "cp-1" }, decidido.c), { error: "Esse cartão já foi decidido." });
  const sem = fluxo();
  assertEquals(await executarCartaoDoParceiro({}, sem.c), { error: "Não consegui executar o cartão do parceiro agora." });
  assertEquals(sem.chamadas.length, 0);
});

Deno.test("só saídas (o SQL já agendou): o aviso do banco volta, e a ferramenta não manda nada", async () => {
  const f = fluxo({ parceiro_cartao_executar: { ok: true, aviso: "o 2: anotado", saidas: ["s-1"], pdfs: [], orcamentos: [] } });
  const d = depsFalsos(f);
  const r = await executarCartaoDoParceiro({ cartao_id: "cp-1" }, f.c, d.deps);
  assertEquals(r, { ok: true, aviso: "o 2: anotado", so_texto: true });
  assertEquals(f.nomes(), ["parceiro_cartao_executar"]);
  assertEquals(f.chamadas[0].args, { p_cartao: "cp-1", p_autor: "dono" });
  assertEquals(textoDoSim("Cartão do parceiro", r), "o 2: anotado");
});

Deno.test("orçamento ao parceiro: o caminho do parceiro, com os cinco nomes e o pedido", async () => {
  await comRelogio(async () => {
    const f = fluxo({
      parceiro_cartao_executar: { ok: true, aviso: "", saidas: [], pdfs: [], orcamentos: [ORC()] },
      parceiro_previa_preparar: PRE,
      parceiro_vinculo_do_pedido: { ok: true, interessado_id: "oi-1", papel: "contratante" },
    });
    const d = depsFalsos(f);
    const r = await executarCartaoDoParceiro({ cartao_id: "cp-1" }, f.c, d.deps);
    assertEquals(f.nomes(), [
      "parceiro_cartao_executar", "parceiro_previa_preparar", "montar", "retorno_previa_orc_criado", "parceiro_vinculo_do_pedido",
      "enviar_pdf", "parceiro_previa_pdf", "parceiro_item_enviado",
    ]);
    assertEquals(f.chamadas[1].args, { p_pedido: "pe-1", p_previa: "pv-1", p_item: "pi-1", p_autor: "dono", p_so: null, p_destino: "parceiro" });
    assertEquals(d.enviados[0].destino, "parceiro");
    assertEquals(d.enviados[0].parceiro_id, "pa-1");
    assertEquals(r.aviso, "Orçamento ORÇ-00151 criado e PDF enviado a MP (Carla).");
  });
});

Deno.test("orçamento ao cliente pelo pedido: o vínculo nasce e o envio é o de sempre, ao cliente", async () => {
  await comRelogio(async () => {
    const f = fluxo({
      parceiro_cartao_executar: { ok: true, orcamentos: [ORC({ destino: "cliente" })] },
      parceiro_previa_preparar: { ...PRE, legenda: { ...LEGENDA_P16, texto: "João, segue o orçamento.", contexto: { ...LEGENDA_P16.contexto, audiencia: "cliente" } } },
      parceiro_vinculo_do_pedido: { ok: true },
    });
    const d = depsFalsos(f);
    await executarCartaoDoParceiro({ cartao_id: "cp-1" }, f.c, d.deps);
    assertEquals(f.chamadas.find((x) => x.fn === "parceiro_vinculo_do_pedido")?.args.p_destino, "cliente");
    assertEquals(f.chamadas.find((x) => x.fn === "parceiro_previa_preparar")?.args.p_destino, "cliente");
  });
});

Deno.test("sem_enviar do parceiro: rascunho, vínculo, frase ao dono e nenhum parceiro_previa_soltar", async () => {
  await comRelogio(async () => {
    const f = fluxo({
      parceiro_cartao_executar: { ok: true, orcamentos: [ORC({ sem_enviar: true })] },
      parceiro_previa_preparar: PRE,
      parceiro_vinculo_do_pedido: { ok: true },
    });
    const d = depsFalsos(f);
    const r = await executarCartaoDoParceiro({ cartao_id: "cp-1" }, f.c, d.deps);
    assertEquals(f.nomes().includes("parceiro_previa_soltar"), false);
    assertEquals(f.nomes().includes("enviar_pdf"), false);
    assertEquals(f.nomes().includes("parceiro_vinculo_do_pedido"), true);
    assertStringIncludes(String(r.aviso), "ficou em rascunho; o PDF ao parceiro só sai depois do aviso e de 24 h; peça de novo depois disso");
  });
});

Deno.test("exceção num orçamento não trava o próximo, e a falha vai ao log", async () => {
  await comRelogio(async () => {
    let n = 0;
    const f = fluxo({
      parceiro_cartao_executar: { ok: true, orcamentos: [ORC(), ORC({ item_id: "pi-2", n: 2 })] },
      parceiro_previa_preparar: () => (++n === 1 ? { data: null, error: { message: "57014" } } : { data: PRE, error: null }),
      parceiro_vinculo_do_pedido: { ok: true },
    });
    const d = depsFalsos(f);
    const r = await executarCartaoDoParceiro({ cartao_id: "cp-1" }, f.c, d.deps);
    assertStringIncludes(String(r.aviso), "o 1: não consegui terminar; confira na tela");
    assertStringIncludes(String(r.aviso), "Orçamento ORÇ-00151 criado");
    assertEquals(f.nomes().includes("log_app_error"), true);
  });
});

Deno.test("o tempo estourado solta o item pelo parceiro, nunca pela F3", async () => {
  const t = new FakeTime(MEIO_DIA);
  try {
    const f = fluxo({
      parceiro_cartao_executar: { ok: true, orcamentos: [ORC(), ORC({ item_id: "pi-2", n: 2 })] },
      parceiro_previa_preparar: PRE,
      parceiro_vinculo_do_pedido: { ok: true },
    });
    const d = depsFalsos(f);
    const original = d.deps.montarOrcamento;
    d.deps.montarOrcamento = ((...a: Parameters<typeof original>) => {
      t.tick(91_000);
      return original(...a);
    }) as typeof original;
    const r = await executarCartaoDoParceiro({ cartao_id: "cp-1" }, f.c, d.deps);
    assertStringIncludes(String(r.aviso), "o 2 ficou para depois: *parceiro*");
    assertEquals(f.chamadas.at(-1), { fn: "parceiro_previa_soltar", args: { p_item: "pi-2" } });
    assert(!f.nomes().some((x) => x === "retorno_previa_soltar" || x === "retorno_item_enviado" || x === "retorno_previa_preparar"));
  } finally {
    t.restore();
  }
});

Deno.test("pdfs (hoje sempre vazio no SQL): se vierem, vão pelo send_service_order_link com o destino, e o item fecha", async () => {
  const f = fluxo({ parceiro_cartao_executar: { ok: true, pdfs: [{ item_id: "pi-9", service_order_id: "os-9", destino: "parceiro", parceiro_id: "pa-1" }] } });
  const d = depsFalsos(f);
  const r = await executarCartaoDoParceiro({ cartao_id: "cp-1" }, f.c, d.deps);
  assertEquals(d.enviados[0].service_order_id, "os-9");
  assertEquals(d.enviados[0].formato, "pdf");
  assertEquals(d.enviados[0].destino, "parceiro");
  assertEquals(f.chamadas.at(-1), { fn: "parceiro_item_enviado", args: { p_item: "pi-9", p_ok: true, p_wa_id: null } });
  assertEquals(r.ok, true);
  const falha = fluxo({ parceiro_cartao_executar: { ok: true, pdfs: [{ item_id: "pi-9", service_order_id: "os-9", destino: "cliente" }] } });
  const df = depsFalsos(falha, { error: "provedor fora" });
  const rf = await executarCartaoDoParceiro({ cartao_id: "cp-1" }, falha.c, df.deps);
  assertEquals("destino" in df.enviados[0], false);
  assertEquals(falha.chamadas.at(-1), { fn: "parceiro_item_enviado", args: { p_item: "pi-9", p_ok: false, p_wa_id: null } });
  assertStringIncludes(String(rf.aviso), "o PDF não saiu");
});

Deno.test("o texto do cartão não vai ao assistente: nenhuma ferramenta do modelo lê o cartão do parceiro", () => {
  for (const t of allTools) {
    assert(!t.name.startsWith("parceiro_"), t.name);
  }
});
