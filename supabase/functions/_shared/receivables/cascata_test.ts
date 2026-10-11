import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { recalcularOSComCascata } from "./cascata.ts";

// A trilha da cascata do agente ia para "audit_logs" (plural), tabela que não existe — o banco só
// tem public.audit_log. O supabase-js devolve { error } em vez de lançar, então o try/catch nunca
// via a falha: toda redistribuição feita pelo assistente ficou sem trilha, em silêncio
// (30 linhas cascade_update em audit_log, todas da TELA; nenhuma "pelo agente").

// Cliente falso: grava cada .from(tabela).insert(payload) e responde as leituras da cascata.
function fakeSb(opts: { erroNoInsert?: string } = {}) {
  const inserts: { tabela: string; payload: any }[] = [];
  const updates: { tabela: string; payload: any }[] = [];
  const rpcs: string[] = [];
  const leitura = (data: unknown) => {
    const result = { data, error: null };
    const proxy: any = new Proxy({}, {
      get(_t, prop) {
        if (prop === "then") return (resolve: (v: unknown) => void) => resolve(result);
        if (prop === "maybeSingle") return () => Promise.resolve(result);
        return () => proxy;
      },
    });
    return proxy;
  };
  const sb = {
    rpc(nome: string) {
      rpcs.push(nome);
      return Promise.resolve({ data: null, error: null });
    },
    from(tabela: string) {
      if (tabela === "service_orders") return leitura({ grand_total: 1500 });
      if (tabela === "receivables") {
        return {
          select: () => leitura([{ id: "r1", amount: 1000, paid_amount: 0, status: "pending" }]),
          update: (payload: any) => {
            updates.push({ tabela, payload });
            return { eq: () => Promise.resolve({ data: null, error: null }) };
          },
        };
      }
      return {
        insert: (payload: any) => {
          inserts.push({ tabela, payload });
          // Tabela inexistente: o PostgREST responde erro (42P01), não exceção.
          const erro = tabela !== "audit_log"
            ? { message: `relation "public.${tabela}" does not exist` }
            : opts.erroNoInsert ? { message: opts.erroNoInsert } : null;
          return Promise.resolve({ data: null, error: erro });
        },
      };
    },
  };
  return { sb, inserts, updates, rpcs };
}

Deno.test("cascata grava a trilha em audit_log (singular), a tabela que existe", async () => {
  const { sb, inserts, updates } = fakeSb();
  const r = await recalcularOSComCascata(sb, "os-1");
  assertEquals(r.bloqueado, false);
  assertEquals(r.atualizados, 1);
  assertEquals(updates.length, 1);
  const trilhas = inserts.filter((i) => i.payload?.action === "cascade_update");
  assertEquals(trilhas.map((t) => t.tabela), ["audit_log"]);
  assertEquals(trilhas[0].payload.record_id, "r1");
  assertEquals(trilhas[0].payload.triggered_by_id, "os-1");
});

Deno.test("falha da trilha não derruba a cascata nem esconde o recebível atualizado, e fica registrada", async () => {
  const { sb, rpcs } = fakeSb({ erroNoInsert: "permission denied for table audit_log" });
  const r = await recalcularOSComCascata(sb, "os-1");
  assertEquals(r.bloqueado, false);
  assertEquals(r.atualizados, 1);
  // O erro vira linha em app_error_logs (log_app_error), em vez de sumir.
  assertEquals(rpcs.includes("log_app_error"), true);
});
