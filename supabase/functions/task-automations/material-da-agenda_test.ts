// O passo do material da Agenda de Produção no motor de 15 min (Fase 1, P2 — 24/10/2026).
//
// O que estes testes protegem:
//  1. chama os_material_sincronizar_carteira com o dia de BRASÍLIA (às 22 h ainda é hoje);
//  2. modo_leitura 'desligado' não chama nada; sem a linha de agenda_config ou com erro na leitura, falha e registra;
//  3. erro da RPC NUNCA lança: vira { erro } e uma linha em app_error_logs (task-automations / agenda:material);
//  4. a OS que falhou sozinha vai para app_error_logs numa linha só por rodada, e o resto segue;
//  5. index.ts chama o passo ANTES de runRules, com try/catch próprio, e põe o resultado no resumo.
import { assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { sincronizarMaterialDaAgenda } from "./material-da-agenda.ts";

interface Cena {
  cfg?: { data: unknown; error: unknown };
  rpc?: { data: unknown; error: unknown } | "lança";
}

function mkDb(cena: Cena) {
  const rpcs: Array<{ nome: string; args: Record<string, unknown> }> = [];
  const db = {
    from: (tabela: string) => {
      if (tabela !== "agenda_config") throw new Error(`tabela inesperada: ${tabela}`);
      return {
        select: (_c: string) => ({
          maybeSingle: async () => cena.cfg ?? { data: { modo_leitura: "sombra" }, error: null },
        }),
      };
    },
    rpc: (nome: string, args: Record<string, unknown>) => {
      rpcs.push({ nome, args });
      if (nome === "log_app_error") return Promise.resolve({ data: null, error: null });
      if (cena.rpc === "lança") return Promise.reject(new Error("conexão caiu"));
      return Promise.resolve(cena.rpc ?? { data: { oss: 11, criadas: 18, atualizadas: 0, erros: [] }, error: null });
    },
  };
  const logs = () =>
    rpcs.filter((r) => r.nome === "log_app_error").map((r) => r.args as Record<string, unknown>);
  const sincronizacoes = () => rpcs.filter((r) => r.nome === "os_material_sincronizar_carteira");
  return { db, logs, sincronizacoes };
}

// 23/10/2026 22:30 de Brasília = 24/10 01:30 UTC: o dia ainda é 23/10.
const AS_22H30_BR = Date.parse("2026-10-24T01:30:00Z");

Deno.test("material da agenda: chama a carteira com o dia de Brasília e devolve o resumo", async () => {
  const { db, logs, sincronizacoes } = mkDb({});
  const r = await sincronizarMaterialDaAgenda(db, AS_22H30_BR);
  assertEquals(sincronizacoes(), [{ nome: "os_material_sincronizar_carteira", args: { p_hoje: "2026-10-23" } }]);
  assertEquals(r, { oss: 11, criadas: 18, atualizadas: 0, erros: 0 });
  assertEquals(logs(), []);
});

Deno.test("material da agenda: modo_leitura desligado não chama nada", async () => {
  const { db, logs, sincronizacoes } = mkDb({ cfg: { data: { modo_leitura: "desligado" }, error: null } });
  const r = await sincronizarMaterialDaAgenda(db, AS_22H30_BR);
  assertEquals(r, { pulado: "modo_leitura desligado" });
  assertEquals(sincronizacoes(), []);
  assertEquals(logs(), []);
});

Deno.test("material da agenda: 'ligado' e 'sombra' rodam", async () => {
  for (const modo of ["ligado", "sombra"]) {
    const { db, sincronizacoes } = mkDb({ cfg: { data: { modo_leitura: modo }, error: null } });
    await sincronizarMaterialDaAgenda(db, AS_22H30_BR);
    assertEquals(sincronizacoes().length, 1);
  }
});

Deno.test("material da agenda: sem agenda_config (migration não aplicada) falha, registra e não chama a carteira", async () => {
  for (const cfg of [
    { data: null, error: { code: "PGRST205", message: "Could not find the table 'public.agenda_config'" } },
    { data: null, error: null },
  ]) {
    const { db, logs, sincronizacoes } = mkDb({ cfg });
    const r = await sincronizarMaterialDaAgenda(db, AS_22H30_BR);
    assertEquals(typeof r.erro, "string");
    assertEquals(sincronizacoes(), []);
    assertEquals(logs().length, 1);
    assertEquals(logs()[0].p_context, "task-automations");
    assertEquals(logs()[0].p_action, "agenda:material");
  }
});

Deno.test("material da agenda: erro da RPC não lança — vira { erro } e app_error_logs", async () => {
  for (const rpc of [{ data: null, error: { code: "57014", message: "statement timeout" } }, "lança" as const]) {
    const { db, logs } = mkDb({ rpc });
    const r = await sincronizarMaterialDaAgenda(db, AS_22H30_BR);
    assertEquals(typeof r.erro, "string");
    assertEquals(logs().length, 1);
    assertEquals(logs()[0].p_action, "agenda:material");
    assertStringIncludes(String(logs()[0].p_message), "material da agenda:");
  }
});

Deno.test("material da agenda: a OS que falhou sozinha vai para app_error_logs numa linha só", async () => {
  const erros = [{ os: "OS-00104", msg: "falhou" }, { os: "OS-00112", msg: "também" }];
  const { db, logs } = mkDb({ rpc: { data: { oss: 11, criadas: 3, atualizadas: 1, erros }, error: null } });
  const r = await sincronizarMaterialDaAgenda(db, AS_22H30_BR);
  assertEquals(r, { oss: 11, criadas: 3, atualizadas: 1, erros: 2 });
  assertEquals(logs().length, 1);
  assertStringIncludes(String(logs()[0].p_message), "2 OS com erro");
  assertStringIncludes(String(logs()[0].p_message), "OS-00104: falhou");
  assertEquals((logs()[0].p_details as { erros: unknown }).erros, erros);
});

// O motor (index.ts sobe o servidor ao ser importado): pelo texto da fonte.
Deno.test("motor: o passo do material roda antes das regras, com try/catch próprio, e entra no resumo", async () => {
  const fonte = (await Deno.readTextFile(new URL("./index.ts", import.meta.url))).replace(/\r\n/g, "\n");
  const passo = fonte.indexOf("agendaMaterial = await sincronizarMaterialDaAgenda(db);");
  const regras = fonte.indexOf("const rules = await runRules(db, settings);");
  assertEquals(passo > 0 && regras > passo, true);
  const bloco = fonte.slice(fonte.lastIndexOf("let agendaMaterial", passo), regras);
  assertStringIncludes(bloco, "try {");
  assertStringIncludes(bloco, "} catch (e) {");
  assertStringIncludes(fonte, "agenda_material: agendaMaterial");
});
