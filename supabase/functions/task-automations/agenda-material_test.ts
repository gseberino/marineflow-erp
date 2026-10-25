// A vigia do material da Agenda de Produção no motor de 15 min (Fase 4, P5 — 25/10/2026).
//
// O que estes testes protegem:
//  1. chama agenda_material_vigiar com o dia de BRASÍLIA (às 22 h ainda é hoje) e a hora, e devolve o resumo;
//  2. os três modos desligados (produção hoje) não chamam o banco; os modos são lidos num SELECT à parte (as colunas da
//     Fase 4), e a leitura que falha = desligado — calada quando é a Fase 4 ausente (a coluna que não existe), em
//     app_error_logs quando é outra coisa;
//  3. NUNCA lança: erro da RPC (ou a RPC que lança) vira { erro } e uma linha em app_error_logs (task-automations /
//     agenda:material-vigia); o passo que falhou NO BANCO volta em erros/falhas (o banco já registrou em material:<passo>)
//     e não gera outra linha aqui;
//  4. NADA vai ao fornecedor daqui: o passo não toca em whatsapp_send_queue (só o banco enfileira, com as travas);
//  5. index.ts chama o passo depois do material e antes da rotina e da vigia, com try/catch próprio, e o põe no resumo.
import { assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { vigiarMaterialDaAgenda } from "./agenda-material.ts";
import { leituraSemAFase4, lerModosDoMaterial, MATERIAL_DESLIGADO } from "./agenda-modos.ts";

interface Cena {
  modos?: { data: unknown; error: unknown } | "lança";
  rpc?: { data: unknown; error: unknown } | "lança";
}

function mkDb(cena: Cena) {
  const rpcs: Array<{ nome: string; args: Record<string, unknown> }> = [];
  const selects: string[] = [];
  const db = {
    from: (tabela: string) => {
      // só a leitura dos modos: nada de fila, nada de escrita
      if (tabela !== "agenda_config") throw new Error(`tabela inesperada: ${tabela}`);
      return {
        select: (colunas: string) => {
          selects.push(colunas);
          return {
            maybeSingle: async () => {
              if (cena.modos === "lança") throw new Error("rede caiu");
              return cena.modos ?? { data: { modo_material: "sombra", modo_detector: "sombra", modo_fornecedor: "sombra" }, error: null };
            },
          };
        },
      };
    },
    rpc: (nome: string, args: Record<string, unknown>) => {
      rpcs.push({ nome, args });
      if (nome === "log_app_error") return Promise.resolve({ data: null, error: null });
      if (cena.rpc === "lança") return Promise.reject(new Error("conexão caiu"));
      return Promise.resolve(cena.rpc ?? {
        data: { rodou: true, modos: { material: "sombra", detector: "sombra", fornecedor: "sombra" },
                contagens: { fila: { canceladas: 0 }, tercos: { registradas: 1 } }, erros: 0, falhas: [] },
        error: null,
      });
    },
  };
  const logs = () => rpcs.filter((r) => r.nome === "log_app_error").map((r) => r.args as Record<string, unknown>);
  const vigias = () => rpcs.filter((r) => r.nome === "agenda_material_vigiar").map((r) => r.args);
  return { db, logs, vigias, selects };
}

// ter 03/11/2026 22:30 de Brasília = 04/11 01:30 UTC: o dia ainda é 03/11.
const AS_22H30_BR = new Date("2026-11-04T01:30:00Z");

Deno.test("chama agenda_material_vigiar com o dia de Brasília e a hora, e devolve o resumo", async () => {
  const { db, vigias, logs, selects } = mkDb({});
  const r = await vigiarMaterialDaAgenda(db, AS_22H30_BR);
  assertEquals(vigias(), [{ p_hoje: "2026-11-03", p_agora: "2026-11-04T01:30:00.000Z" }]);
  assertEquals(selects, ["modo_material, modo_detector, modo_fornecedor"]);
  assertEquals(r, {
    rodou: true, modos: { material: "sombra", detector: "sombra", fornecedor: "sombra" },
    contagens: { fila: { canceladas: 0 }, tercos: { registradas: 1 } }, erros: 0, falhas: [],
  });
  assertEquals(logs(), []);
});

Deno.test("os três modos desligados (produção hoje): nem chama o banco; um só ligado já chama", async () => {
  const { db, vigias } = mkDb({ modos: { data: { modo_material: "desligado", modo_detector: "desligado", modo_fornecedor: "desligado" }, error: null } });
  const r = await vigiarMaterialDaAgenda(db, AS_22H30_BR);
  assertEquals(r, { pulado: "modo_material, modo_detector e modo_fornecedor desligados" });
  assertEquals(vigias(), []);
  for (const m of [
    { modo_material: "desligado", modo_detector: "desligado", modo_fornecedor: "sombra" },
    { modo_material: "ligado", modo_detector: "desligado", modo_fornecedor: "desligado" },
    { modo_material: "desligado", modo_detector: " Sombra ", modo_fornecedor: "desligado" },
  ]) {
    const x = mkDb({ modos: { data: m, error: null } });
    await vigiarMaterialDaAgenda(x.db, AS_22H30_BR);
    assertEquals(x.vigias().length, 1, JSON.stringify(m));
  }
});

Deno.test("a leitura dos modos que falha = desligado: a Fase 4 ausente (42703, PGRST204, sem a linha) calada; outra coisa vai a app_error_logs", async () => {
  for (const [modos, registra] of [
    [{ data: null, error: { code: "42703", message: "column agenda_config.modo_material does not exist" } }, false],
    [{ data: null, error: { code: "PGRST204", message: "Could not find the 'modo_material' column" } }, false],
    [{ data: null, error: null }, false],
    [{ data: null, error: { code: "57014", message: "canceling statement due to statement timeout" } }, true],
    ["lança", true],
  ] as Array<[Cena["modos"], boolean]>) {
    const { db, vigias, logs } = mkDb({ modos });
    const r = await vigiarMaterialDaAgenda(db, AS_22H30_BR);
    assertEquals(vigias(), [], JSON.stringify(modos));
    assertStringIncludes(String(r.pulado), "não li os modos do material");
    assertEquals(logs().length, registra ? 1 : 0, JSON.stringify(modos));
    if (registra) {
      assertEquals([logs()[0].p_context, logs()[0].p_action, logs()[0].p_level], ["task-automations", "agenda:material-vigia", "warn"]);
    }
  }
});

Deno.test("NUNCA lança: o erro da RPC (ou a RPC que lança) vira { erro } e uma linha em app_error_logs", async () => {
  for (const rpc of [{ data: null, error: { code: "42883", message: "function agenda_material_vigiar does not exist" } }, "lança"] as const) {
    const { db, logs } = mkDb({ rpc: rpc as Cena["rpc"] });
    const r = await vigiarMaterialDaAgenda(db, AS_22H30_BR);
    assertEquals(typeof r.erro, "string");
    assertEquals(logs().length, 1);
    assertEquals([logs()[0].p_context, logs()[0].p_action], ["task-automations", "agenda:material-vigia"]);
    assertStringIncludes(String(logs()[0].p_message), "vigia do material:");
  }
});

Deno.test("o passo que falhou no banco volta em erros/falhas, sem outra linha em app_error_logs (o banco já registrou)", async () => {
  const falhas = [{ passo: "pix", sqlstate: "XX000", erro: "Pix quebrou" }];
  const { db, logs } = mkDb({ rpc: { data: { rodou: true, modos: {}, contagens: { fila: {} }, erros: 1, falhas }, error: null } });
  const r = await vigiarMaterialDaAgenda(db, AS_22H30_BR);
  assertEquals([r.rodou, r.erros, r.falhas], [true, 1, falhas]);
  assertEquals(logs(), []);
  // {rodou: false} do banco (os três desligados lá, mesmo que a leitura daqui tenha visto outro) passa como veio
  const x = mkDb({ rpc: { data: { rodou: false, modos: {}, fila: { canceladas: 1 }, erros: 0, falhas: [] }, error: null } });
  assertEquals((await vigiarMaterialDaAgenda(x.db, AS_22H30_BR)).rodou, false);
});

Deno.test("lerModosDoMaterial: o SELECT à parte, os valores tolerantes e o lado seguro", async () => {
  const { db } = mkDb({ modos: { data: { modo_material: '"ligado"', modo_detector: "SOMBRA", modo_fornecedor: "talvez" }, error: null } });
  assertEquals(await lerModosDoMaterial(db), { material: "ligado", detector: "sombra", fornecedor: "desligado" });
  const e = await lerModosDoMaterial(mkDb({ modos: { data: null, error: { code: "42703", message: "x" } } }).db);
  assertEquals([e.material, e.detector, e.fornecedor, e.codigo, leituraSemAFase4(e)], ["desligado", "desligado", "desligado", "42703", true]);
  const t = await lerModosDoMaterial(mkDb({ modos: { data: null, error: { code: "57014", message: "timeout" } } }).db);
  assertEquals(leituraSemAFase4(t), false);
  assertEquals(leituraSemAFase4(MATERIAL_DESLIGADO), false);
});

// O motor (index.ts sobe o servidor ao ser importado): pelo texto da fonte.
Deno.test("motor: a vigia do material roda depois do material e antes da rotina e da vigia, com try/catch próprio, e entra no resumo", async () => {
  const fonte = (await Deno.readTextFile(new URL("./index.ts", import.meta.url))).replace(/\r\n/g, "\n");
  const material = fonte.indexOf("agendaMaterial = await sincronizarMaterialDaAgenda(db);");
  const passo = fonte.indexOf("agendaMaterialVigia = await vigiarMaterialDaAgenda(db, new Date());");
  const rotina = fonte.indexOf("agendaRotina = await rodarRotinaDaAgenda(db, new Date());");
  const vigia = fonte.indexOf("agendaVigia = await vigiarAgenda(db, new Date());");
  assertEquals(material > 0 && passo > material && rotina > passo && vigia > rotina, true);
  const bloco = fonte.slice(fonte.lastIndexOf("let agendaMaterialVigia", passo), rotina);
  assertEquals(bloco.includes("try {") && bloco.includes("} catch (e) {"), true);
  assertStringIncludes(fonte, "agenda_material_vigia: agendaMaterialVigia");
  assertStringIncludes(fonte, 'import { vigiarMaterialDaAgenda } from "./agenda-material.ts";');
  // nada daqui vai ao fornecedor: o passo não toca na fila
  const passoTs = await Deno.readTextFile(new URL("./agenda-material.ts", import.meta.url));
  assertEquals(passoTs.includes("whatsapp_send_queue"), false);
  assertEquals(passoTs.includes(".insert("), false);
});
