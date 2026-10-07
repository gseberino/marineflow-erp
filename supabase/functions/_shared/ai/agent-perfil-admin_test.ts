// Perfil enxuto do administrador e a ferramenta_extra (agent.ts, 05/10/2026).
//
// Com app_settings.ai_tool_profile = 'admin_enxuto', o admin vê só PERFIL_ADMIN + ferramenta_extra;
// os outros cargos seguem como em 'operacao'. A ferramenta_extra redespacha pelo caminho da rede:
// descrever não executa, leitura roda direto, gravação vira pendência com o nome REAL.
// Rodar com:
//   deno test --allow-all supabase/functions/_shared/ai/agent-perfil-admin_test.ts
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { executarChamadaDeTool, prepararFerramentasDoTurno, zerarCacheDoPerfilDeTools } from "./agent.ts";
import { PERFIL_ADMIN, PERFIL_OPERACAO } from "./perfil-operacao.ts";
import { allTools, type Role, type ToolDef } from "./tools/index.ts";
import { NOME_DA_FERRAMENTA_EXTRA } from "./ferramenta-extra.ts";

function fakeAdmin(perfil: string) {
  const auditRows: any[] = [];
  const pendingRows: any[] = [];
  const admin = {
    from(table: string) {
      return {
        select() {
          return { in: async () => ({ data: table === "app_settings" ? [{ key: "ai_tool_profile", value: perfil }] : [], error: null }) };
        },
        insert(row: any) {
          if (table === "ai_operator_audit") auditRows.push(row);
          if (table === "ai_operator_pending_actions") pendingRows.push(row);
          return {
            select: () => ({ single: async () => ({ data: { id: "pend-1", title: row.title, summary: row.summary, risk_level: row.risk_level }, error: null }) }),
            then: (resolve: (v: unknown) => void) => resolve({ data: null, error: null }),
          };
        },
      };
    },
  };
  return { admin, auditRows, pendingRows };
}

function params(perfil: string, role: Role, tools: ToolDef[]) {
  const f = fakeAdmin(perfil);
  return {
    ...f,
    p: {
      system: [{ type: "text" as const, text: "teste" }],
      sessionId: "s1",
      channel: "panel" as const,
      tools,
      messages: [{ role: "user" as const, content: [{ type: "text" as const, text: "oi" }] }],
      toolCtx: { sb: {}, admin: f.admin, userId: "u1", userRole: role, jwt: "jwt", appOrigin: "", settings: {} },
    },
  };
}

const porCargo = (role: Role) => allTools.filter((t) => !t.roles || t.roles.includes(role));
const execucoes: string[] = [];
const comExecuteFalso = (t: ToolDef): ToolDef => ({ ...t, execute: async () => { execucoes.push(t.name); return { ok: true }; } });

Deno.test("todo nome de PERFIL_ADMIN é ferramenta de verdade", () => {
  const existe = new Set(allTools.map((t) => t.name));
  assertEquals([...PERFIL_ADMIN].filter((n) => !existe.has(n)), []);
});

Deno.test("admin_enxuto: o admin vê só PERFIL_ADMIN + ferramenta_extra, e a rede alcança o resto", async () => {
  zerarCacheDoPerfilDeTools();
  const { p } = params("admin_enxuto", "admin", porCargo("admin"));
  const r = await prepararFerramentasDoTurno(p as any);
  const visiveis = r.tools.map((t) => t.name);
  assert(visiveis.includes(NOME_DA_FERRAMENTA_EXTRA));
  assertEquals(visiveis.filter((n) => n !== NOME_DA_FERRAMENTA_EXTRA && !PERFIL_ADMIN.has(n)), []);
  // Teto do perfil enxuto. Era < 100 (92 em 05/10); em 06/10 entraram as tools de acerto das
  // Diárias e atualizar_extrato/enviar_relatorio_pdf, pedidas pelo dono para usar no dia a dia → 101.
  // Subir de novo só com motivo: cada tool visível custa tokens em toda mensagem.
  // 07/10/2026 (junção das quatro frentes aprovadas pelo dono): ficaram visíveis só as de uso diário
  // — via do técnico, update_task, anotação de Pix, estorno, criar cobrança/registrar contato e o PDF
  // da nota — e o resto (marina, contatos da embarcação, favorecido, sugestões, compras) foi para a
  // rede → 109. Teto 110.
  assert(visiveis.length <= 110, `admin vê ${visiveis.length}`);
  // A rede é o complemento: nada à vista está na rede, e o que saiu está.
  assertEquals(Object.keys(r.alcancaveisPelaRede).filter((n) => r.toolsByName[n]), []);
  assert(r.alcancaveisPelaRede["list_low_stock"], "list_low_stock devia estar ao alcance da rede");
  const enumDaExtra = (r.toolsByName[NOME_DA_FERRAMENTA_EXTRA].input_schema as any).properties.nome.enum as string[];
  assertEquals(enumDaExtra, Object.keys(r.alcancaveisPelaRede).sort());
});

Deno.test("admin_enxuto: os outros cargos não mudam (perfil de operação, sem ferramenta_extra)", async () => {
  zerarCacheDoPerfilDeTools();
  const { p } = params("admin_enxuto", "financial", porCargo("financial"));
  const r = await prepararFerramentasDoTurno(p as any);
  const visiveis = r.tools.map((t) => t.name);
  assert(!visiveis.includes(NOME_DA_FERRAMENTA_EXTRA));
  assert(visiveis.every((n) => PERFIL_OPERACAO.has(n) || r.toolsByName[n].risk === "high"));
});

Deno.test("operacao: o admin segue como antes (sem ferramenta_extra)", async () => {
  zerarCacheDoPerfilDeTools();
  const { p } = params("operacao", "admin", porCargo("admin"));
  const r = await prepararFerramentasDoTurno(p as any);
  assert(!r.tools.some((t) => t.name === NOME_DA_FERRAMENTA_EXTRA));
  assert(r.tools.length > 100);
});

async function ambienteDoAdmin(trocas: Record<string, (t: ToolDef) => ToolDef> = {}) {
  zerarCacheDoPerfilDeTools();
  const tools = porCargo("admin").map((t) => (trocas[t.name] ? trocas[t.name](t) : t));
  const { p, auditRows, pendingRows } = params("admin_enxuto", "admin", tools);
  const r = await prepararFerramentasDoTurno(p as any);
  return {
    amb: { toolsByName: r.toolsByName, alcancaveisPelaRede: r.alcancaveisPelaRede, toolCtx: p.toolCtx as any, sessionId: "s1", channel: "panel" as const },
    auditRows,
    pendingRows,
  };
}

Deno.test("ferramenta_extra com descrever devolve descrição e esquema sem executar", async () => {
  execucoes.length = 0;
  const { amb } = await ambienteDoAdmin({ list_low_stock: comExecuteFalso });
  const r = await executarChamadaDeTool({ name: NOME_DA_FERRAMENTA_EXTRA, input: { nome: "list_low_stock", descrever: true } }, amb);
  const res = r.toolResult as any;
  assertEquals(res.nome, "list_low_stock");
  assert(res.input_schema);
  assertEquals(execucoes, []);
});

Deno.test("ferramenta_extra: leitura pela rede roda direto e fica marcada na auditoria", async () => {
  execucoes.length = 0;
  const { amb, auditRows } = await ambienteDoAdmin({ list_low_stock: comExecuteFalso });
  const r = await executarChamadaDeTool({ name: NOME_DA_FERRAMENTA_EXTRA, input: { nome: "list_low_stock", argumentos: {} } }, amb);
  assertEquals(r.toolResult, { ok: true });
  assertEquals(execucoes, ["list_low_stock"]);
  assert(auditRows.some((a) => a.event_type === "fora_do_perfil:list_low_stock"));
});

Deno.test("ferramenta_extra: gravação vira pendência com o nome real, sem executar", async () => {
  execucoes.length = 0;
  const { amb, pendingRows } = await ambienteDoAdmin({ check_in_service_order: comExecuteFalso });
  assert(amb.alcancaveisPelaRede["check_in_service_order"], "check_in_service_order devia estar na rede do admin");
  const r = await executarChamadaDeTool({
    name: NOME_DA_FERRAMENTA_EXTRA,
    input: { nome: "check_in_service_order", argumentos: { service_order_id: "00000000-0000-0000-0000-000000000001" } },
  }, amb);
  assertEquals(execucoes, []);
  assertEquals((r.toolResult as any).pending, true);
  assertEquals(pendingRows[0]?.action_name, "check_in_service_order");
});

Deno.test("ferramenta_extra com nome fora do alcance recusa", async () => {
  const { amb } = await ambienteDoAdmin();
  const r = await executarChamadaDeTool({ name: NOME_DA_FERRAMENTA_EXTRA, input: { nome: "nao_existe" } }, amb);
  assert(String((r.toolResult as any).error).includes("não está ao seu alcance"));
});
