// O prazo do fornecedor no acompanhar-conversas (Agenda de Produção, Fase 4, P4). O que se protege, com um banco e um
// modelo de mentira:
//   · desligado (a RPC devolve a lista vazia) não chama mais nada: nem o parser registra, nem o modelo;
//   · com UMA compra viva, ela é a escolhida (unico) e o modelo NÃO é chamado; com mais, o modelo escolhe (modelo) ou não
//     (nenhum) — e quem manda a data é o banco: o TS passa só a expressão dita;
//   · a mensagem sem prazo não é registrada;
//   · nunca lança: a RPC que falha vira { erro } e app_error_logs (agenda:fornecedor); a mensagem que falha sozinha não
//     derruba as outras; a função ausente (migration não aplicada) é silêncio ({ pulado }).
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { type MensagemDeFornecedor, vigiarPrazosDosFornecedores } from "./fornecedores.ts";
import { escolherCompra } from "../_shared/agenda/casar-fornecedor.ts";
import { ClaudeApiError } from "../_shared/ai/anthropic.ts";

const AGORA = new Date("2026-10-13T21:00:00.000Z"); // ter 13/10, 18:00 em Brasília

interface Chamada { fn: string; args: Record<string, unknown> }

function banco(
  lista: MensagemDeFornecedor[] | { error: { code?: string; message: string } },
  falhaNo?: string,
  // agenda_config.detector_modelo_max (C1 da revisão, R5); { erro } = a leitura falha
  tetoDoModelo: number | { erro: string } = 5,
) {
  const chamadas: Chamada[] = [];
  return {
    chamadas,
    from(tabela: string) {
      return {
        select(colunas: string) {
          return {
            maybeSingle() {
              chamadas.push({ fn: `from:${tabela}`, args: { colunas } });
              return Promise.resolve(typeof tetoDoModelo === "number"
                ? { data: { detector_modelo_max: tetoDoModelo }, error: null }
                : { data: null, error: { message: tetoDoModelo.erro } });
            },
          };
        },
      };
    },
    rpc(fn: string, args: Record<string, unknown>) {
      chamadas.push({ fn, args });
      if (fn === "agenda_mensagens_de_fornecedor") {
        return Promise.resolve(Array.isArray(lista) ? { data: lista, error: null } : { data: null, error: lista.error });
      }
      if (fn === "material_sinal_registrar") {
        if (falhaNo && args.p_msg === falhaNo) return Promise.resolve({ data: null, error: { message: "boom" } });
        return Promise.resolve({ data: { id: "s1" }, error: null });
      }
      return Promise.resolve({ data: null, error: null });
    },
  };
}

const COMPRESSOR = { n: 1, os: "os104", os_material_id: "m104", rotulo: "Flávio: Compressor 12V de… (comprado 13/10)" };
const PAINEL = { n: 2, os: "os112", os_material_id: "m112", rotulo: "Nelson: Painel Touch de… (comprado 15/10)" };
const msg = (id: string, texto: string, compras = [COMPRESSOR], direcao: "recebida" | "enviada" = "recebida"): MensagemDeFornecedor => ({
  msg_id: id, fornecedor_id: "dd04", fornecedor: "Mateus", direcao, texto, em: "2026-10-13T20:19:00.000Z", compras,
});

function deps() {
  const escolhas: string[] = [];
  const logs: Array<Record<string, unknown>> = [];
  return {
    escolhas,
    logs,
    escolher: (trecho: string) => {
      escolhas.push(trecho);
      return Promise.resolve({ n: 2, confianca: 0.8 });
    },
    // deno-lint-ignore no-explicit-any
    log: (_db: any, input: Record<string, unknown>) => {
      logs.push(input);
      return Promise.resolve();
    },
  };
}

Deno.test("desligado (lista vazia): só a leitura, nada registrado, nenhum modelo", async () => {
  const db = banco([]);
  const d = deps();
  const r = await vigiarPrazosDosFornecedores(db, AGORA, d);
  assertEquals(r, { lidas: 0, sinais: 0, modelo: 0 });
  assertEquals(db.chamadas.map((c) => c.fn), ["agenda_mensagens_de_fornecedor"]);
  assertEquals(db.chamadas[0].args, { p_hoje: "2026-10-13", p_agora: AGORA.toISOString() });
  assertEquals(d.escolhas.length, 0);
});

Deno.test("uma compra viva: unico, sem o modelo; a expressão vai crua para o banco", async () => {
  const db = banco([
    msg("w403", "chega aqui amanha se eles retirarem hoje", [COMPRESSOR], "enviada"),
    msg("w405", "Tenho disponivel"),
    msg("w409", "Já foi coletado"),
  ]);
  const d = deps();
  const r = await vigiarPrazosDosFornecedores(db, AGORA, d);
  assertEquals(r, { lidas: 3, sinais: 2, modelo: 0 });
  assertEquals(d.escolhas.length, 0);
  const regs = db.chamadas.filter((c) => c.fn === "material_sinal_registrar").map((c) => c.args);
  assertEquals(regs.map((a) => [a.p_msg, a.p_tipo, a.p_expressao, a.p_condicional, a.p_casou_por, a.p_os_material]), [
    ["w403", "chegada", "amanhã", true, "unico", "m104"],
    ["w409", "despacho", null, false, "unico", "m104"],
  ]);
  assertEquals(regs[1].p_trecho, "Já foi coletado");
  assertEquals(regs[1].p_candidatos, [{ n: 1, os: "os104", os_material_id: "m104", rotulo: COMPRESSOR.rotulo }]);
  assert(!("p_data_ate" in regs[1]) && !("p_data" in regs[1]), "nenhuma data sai do TS");
});

Deno.test("mais de uma compra: o modelo escolhe (modelo); sem compra nenhuma: nenhum", async () => {
  const db = banco([msg("w1", "O painel foi postado hoje", [COMPRESSOR, PAINEL]), msg("w2", "Despachado!", [])]);
  const d = deps();
  const r = await vigiarPrazosDosFornecedores(db, AGORA, d);
  assertEquals(r, { lidas: 2, sinais: 2, modelo: 1 });
  assertEquals(d.escolhas, ["O painel foi postado hoje"]);
  const regs = db.chamadas.filter((c) => c.fn === "material_sinal_registrar").map((c) => c.args);
  assertEquals([regs[0].p_casou_por, regs[0].p_os_material, regs[0].p_confianca], ["modelo", "m112", 0.8]);
  assertEquals([regs[1].p_casou_por, regs[1].p_os_material], ["nenhum", null]);
  // o modelo que não escolhe = nenhum, com a confiança dele
  const db2 = banco([msg("w3", "Coletaram hoje", [COMPRESSOR, PAINEL])]);
  await vigiarPrazosDosFornecedores(db2, AGORA, { ...d, escolher: () => Promise.resolve({ n: null, confianca: 0.3 }) });
  const r2 = db2.chamadas.find((c) => c.fn === "material_sinal_registrar")!.args;
  assertEquals([r2.p_casou_por, r2.p_os_material, r2.p_confianca], ["nenhum", null, 0.3]);
});

// ── C1 da revisão da Fase 4 (25/10/2026) ────────────────────────────────────────────────────────────────────────────
// (item 1) a única linha viva com OUTRA compra viva do fornecedor (outras_vivas: a OC de estoque, a nota sem resposta, o
// Pix aberto) não é unico: a linha vai como dica, nenhum, e o modelo não é chamado. (R5) o modelo pago tem teto por rodada
// (agenda_config.detector_modelo_max): passou dele, a mensagem vai sem o modelo (nenhum); teto 0 = nunca; a leitura do teto
// que falha = nenhum modelo, com log. O teto só é lido quando alguma mensagem precisa do modelo.

Deno.test("C1: uma linha e outra compra viva do fornecedor = nenhum, com a linha de dica e sem o modelo", async () => {
  const db = banco([{ ...msg("w409", "Já foi coletado"), outras_vivas: 1 }, msg("w410", "Chega amanhã")]);
  const d = deps();
  const r = await vigiarPrazosDosFornecedores(db, AGORA, d);
  assertEquals(r, { lidas: 2, sinais: 2, modelo: 0 });
  assertEquals(d.escolhas.length, 0);
  const regs = db.chamadas.filter((c) => c.fn === "material_sinal_registrar").map((c) => c.args);
  assertEquals(regs.map((a) => [a.p_msg, a.p_casou_por, a.p_os_material]), [["w409", "nenhum", "m104"], ["w410", "unico", "m104"]]);
  assert(!db.chamadas.some((c) => c.fn.startsWith("from:")), "sem mensagem de duas compras, o teto nem é lido");
});

Deno.test("C1 (R5): o modelo pago no teto da rodada — passou dele, nenhum; teto 0 = nunca", async () => {
  const lista = [
    msg("w1", "O painel foi postado hoje", [COMPRESSOR, PAINEL]),
    msg("w2", "Coletaram hoje", [COMPRESSOR, PAINEL]),
    msg("w3", "Despachado!", [COMPRESSOR, PAINEL]),
  ];
  const db = banco(lista, undefined, 2);
  const d = deps();
  const r = await vigiarPrazosDosFornecedores(db, AGORA, d);
  assertEquals(r, { lidas: 3, sinais: 3, modelo: 2, sem_modelo_pelo_teto: 1 });
  assertEquals(d.escolhas, ["O painel foi postado hoje", "Coletaram hoje"]);
  const regs = db.chamadas.filter((c) => c.fn === "material_sinal_registrar").map((c) => c.args);
  assertEquals(regs.map((a) => [a.p_msg, a.p_casou_por, a.p_os_material]), [
    ["w1", "modelo", "m112"], ["w2", "modelo", "m112"], ["w3", "nenhum", null],
  ]);
  assertEquals(db.chamadas.filter((c) => c.fn === "from:agenda_config").length, 1, "o teto é lido uma vez por rodada");

  const db0 = banco(lista, undefined, 0);
  const d0 = deps();
  const r0 = await vigiarPrazosDosFornecedores(db0, AGORA, d0);
  assertEquals([r0.modelo, r0.sem_modelo_pelo_teto, r0.sinais], [0, 3, 3]);
  assertEquals(d0.escolhas.length, 0);
});

Deno.test("C1 (R5): a leitura do teto que falha = nenhum modelo nesta rodada, com log; as mensagens seguem", async () => {
  const db = banco([msg("w1", "O painel foi postado hoje", [COMPRESSOR, PAINEL])], undefined, { erro: "caiu" });
  const d = deps();
  const r = await vigiarPrazosDosFornecedores(db, AGORA, d);
  assertEquals(r, { lidas: 1, sinais: 1, modelo: 0, sem_modelo_pelo_teto: 1 });
  assertEquals(d.escolhas.length, 0);
  assertEquals(d.logs.length, 1);
  assertEquals(d.logs[0].action, "agenda:fornecedor");
  assert(String(d.logs[0].message).includes("teto do modelo"), String(d.logs[0].message));
});

// (pacote 1, V2, 24/11/2026) O modelo que falha na escolha da compra era calado. O que se protege: a falha vai a
// app_error_logs com o contexto da rotina e do dia de Brasília (rotina-ia:casar_fornecedor@<dia>), que é o que a manhã lê;
// a mensagem segue como antes (nenhum, a pergunta ao dono lista as compras); e o modelo que só não escolheu não registra.
Deno.test("V2: o modelo que falha na escolha deixa registro de rotina e a mensagem segue como 'nenhum'", async () => {
  const db = banco([msg("w1", "O painel foi postado hoje", [COMPRESSOR, PAINEL])]);
  const d = deps();
  const r = await vigiarPrazosDosFornecedores(db, AGORA, {
    ...d,
    escolher: () => Promise.resolve({ n: null, confianca: 0, falhou: true as const, erro: "HTTP 402 (sem crédito)" }),
  });
  assertEquals(r, { lidas: 1, sinais: 1, modelo: 1 });
  const registros = db.chamadas.filter((c) => c.fn === "log_app_error").map((c) => c.args);
  assertEquals(registros.length, 1);
  // 21:00 UTC de 13/10 = 18:00 de Brasília: o dia do contexto é o de Brasília
  assertEquals([registros[0].p_context, registros[0].p_action, registros[0].p_level], ["rotina-ia:casar_fornecedor@2026-10-13", "casar_fornecedor", "error"]);
  assertEquals(registros[0].p_message, "HTTP 402 (sem crédito)");
  assert(!JSON.stringify(registros[0]).includes("painel"), "a frase do fornecedor não vai ao registro");
  // o registro vem antes de gravar o sinal, e o sinal sai como antes
  const ordem = db.chamadas.map((c) => c.fn).filter((f) => f === "log_app_error" || f === "material_sinal_registrar");
  assertEquals(ordem, ["log_app_error", "material_sinal_registrar"]);
  const sinal = db.chamadas.find((c) => c.fn === "material_sinal_registrar")!.args;
  assertEquals([sinal.p_casou_por, sinal.p_os_material, sinal.p_confianca], ["nenhum", null, 0]);
  assertEquals(d.logs.length, 0, "não é erro do passo: só o registro da rotina");

  // sem o texto do erro, o registro sai com a frase padrão
  const dbSemTexto = banco([msg("w1", "O painel foi postado hoje", [COMPRESSOR, PAINEL])]);
  await vigiarPrazosDosFornecedores(dbSemTexto, AGORA, { ...deps(), escolher: () => Promise.resolve({ n: null, confianca: 0, falhou: true as const }) });
  assertEquals(dbSemTexto.chamadas.find((c) => c.fn === "log_app_error")!.args.p_message, "falha sem mensagem de erro");
  // (acabamento da leva A, 24/11/2026) texto que não é classe de erro não é gravado: vira frase fixa
  const dbCru = banco([msg("w1", "O painel foi postado hoje", [COMPRESSOR, PAINEL])]);
  await vigiarPrazosDosFornecedores(dbCru, AGORA, {
    ...deps(),
    escolher: () => Promise.resolve({ n: null, confianca: 0, falhou: true as const, erro: "ClaudeApiError: OpenRouter 403: O painel foi postado hoje" }),
  });
  assertEquals(dbCru.chamadas.find((c) => c.fn === "log_app_error")!.args.p_message, "erro não classificado");

  // o modelo que respondeu (escolheu ou não) não é falha de rotina
  for (const escolha of [{ n: 2, confianca: 0.8 }, { n: null, confianca: 0.3 }]) {
    const db2 = banco([msg("w1", "O painel foi postado hoje", [COMPRESSOR, PAINEL])]);
    await vigiarPrazosDosFornecedores(db2, AGORA, { ...deps(), escolher: () => Promise.resolve(escolha) });
    assert(!db2.chamadas.some((c) => c.fn === "log_app_error"), JSON.stringify(escolha));
  }
});

// (acabamento da leva A do pacote 1, 24/11/2026) O erro do provedor carrega o corpo da resposta, que pode devolver o que
// foi enviado: a frase do fornecedor e os rótulos das compras. O que se protege, de ponta a ponta e com o escolherCompra
// de verdade (só a chamada do modelo é de mentira): nada disso chega a app_error_logs; vai só a classe do erro.
Deno.test("o erro do provedor que devolve a frase do fornecedor não leva nada dela para o registro em app_error_logs", async () => {
  const frase = "O painel foi postado hoje pela Rodomar, rastreio BR88123";
  const trechos = ["painel", "postado", "Rodomar", "BR88123", "Flávio", "Compressor", "Nelson", "Painel Touch"];
  const casos: Array<[(enviado: string) => unknown, string]> = [
    [(enviado) => new ClaudeApiError(403, `OpenRouter 403: ${JSON.stringify({ error: { code: 403, metadata: { flagged_input: enviado } } })}`), "HTTP 403 (recusado pelo provedor)"],
    [(enviado) => new ClaudeApiError(400, `OpenRouter 400: ${enviado}`), "HTTP 400 (pedido recusado)"],
    [(enviado) => new Error(enviado), "erro do tipo Error"],
    [(enviado) => enviado, "erro não classificado"],
  ];
  for (const [erroCom, classe] of casos) {
    const db = banco([msg("w1", frase, [COMPRESSOR, PAINEL])]);
    let visto = "";
    await vigiarPrazosDosFornecedores(db, AGORA, {
      ...deps(),
      escolher: (trecho, candidatos) =>
        escolherCompra(trecho, candidatos, {
          chamar: (p) => {
            visto = JSON.stringify(p.messages);
            return Promise.reject(erroCom(visto));
          },
        }),
    });
    // o exemplo vale: o que foi ao modelo trazia a frase e os rótulos
    for (const trecho of trechos) assert(visto.includes(trecho), `o exemplo perdeu "${trecho}"`);
    const registros = db.chamadas.filter((c) => c.fn === "log_app_error").map((c) => c.args);
    assertEquals(registros, [{
      p_source: "edge", p_message: classe, p_context: "rotina-ia:casar_fornecedor@2026-10-13", p_action: "casar_fornecedor", p_level: "error", p_details: {},
    }], classe);
    for (const trecho of trechos) assert(!JSON.stringify(registros).includes(trecho), `"${trecho}" foi para o registro (${classe})`);
  }
});

Deno.test("nunca lança: a leitura que falha, a mensagem que falha sozinha, a função ausente", async () => {
  const d = deps();
  const r = await vigiarPrazosDosFornecedores(banco({ error: { code: "XX000", message: "caiu" } }), AGORA, d);
  assertEquals(r.erro, "caiu");
  assertEquals(d.logs.length, 1);
  assertEquals([d.logs[0].context, d.logs[0].action], ["acompanhar-conversas", "agenda:fornecedor"]);

  const d2 = deps();
  const db = banco([msg("w1", "Já foi coletado"), msg("w2", "Chega amanhã")], "w1");
  const r2 = await vigiarPrazosDosFornecedores(db, AGORA, d2);
  assertEquals([r2.lidas, r2.sinais, r2.erros], [2, 1, 1]);
  assertEquals(d2.logs.length, 1);
  assertEquals(d2.logs[0].action, "agenda:fornecedor");

  const d3 = deps();
  const r3 = await vigiarPrazosDosFornecedores(banco({ error: { code: "PGRST202", message: "não existe" } }), AGORA, d3);
  assertEquals(r3.pulado, "agenda_mensagens_de_fornecedor ausente");
  assertEquals(d3.logs.length, 0);
});
