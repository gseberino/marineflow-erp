// Passo do motor de 15 min: a conferência do material da Agenda de Produção (Fase 1, P2 — 24/10/2026).
//
// Roda ANTES das regras (index.ts), para a R16 já ler a conta com o material em dia. Chama
// os_material_sincronizar_carteira (migration 20261024160300), que guarda em os_material uma linha por
// item de compra de cada OS da carteira: o que o estoque cobre fica "na mão", o que tem OC fica "a
// caminho", o resto "falta" — e o que o dono disse fica. A conta de compra (get_os_purchase_needs) só usa
// o que o dono informou; esta passada é o que deixa o fato dele pronto para ser guardado e o que percebe a
// OC que chegou ou foi cancelada.
//
// Nunca derruba o motor: erro vira linha em app_error_logs (context task-automations, action
// agenda:material) e `{ erro }` no resumo da rodada. A OS que falhou sozinha também vai para lá, numa
// linha por rodada. Com agenda_config.modo_leitura = 'desligado' não faz nada.
import { diaBR } from "../_shared/agenda-dia.ts";
import { logEdgeError } from "../_shared/log-error.ts";

// deno-lint-ignore no-explicit-any
type Db = any;

export interface ResultadoDoMaterial {
  /** Por que não rodou (modo desligado). */
  pulado?: string;
  oss?: number;
  criadas?: number;
  atualizadas?: number;
  /** Quantas OS falharam sozinhas (o detalhe vai para app_error_logs). */
  erros?: number;
  /** A passada inteira falhou. */
  erro?: string;
}

export async function sincronizarMaterialDaAgenda(db: Db, agora: number = Date.now()): Promise<ResultadoDoMaterial> {
  try {
    // O interruptor mora em agenda_config (uma linha). Sem a linha, ou com erro, a passada falha e
    // registra — nunca roda "por padrão".
    const { data: cfg, error: cfgErr } = await db.from("agenda_config").select("modo_leitura").maybeSingle();
    if (cfgErr) throw cfgErr;
    if (!cfg) throw new Error("agenda_config sem a linha de parâmetros");
    if (cfg.modo_leitura === "desligado") return { pulado: "modo_leitura desligado" };

    const { data, error } = await db.rpc("os_material_sincronizar_carteira", { p_hoje: diaBR(agora) });
    if (error) throw error;
    const r = (data ?? {}) as { oss?: number; criadas?: number; atualizadas?: number; erros?: unknown };
    const erros = Array.isArray(r.erros) ? (r.erros as Array<{ os?: string; msg?: string }>) : [];
    if (erros.length) {
      await logEdgeError(db, {
        context: "task-automations",
        action: "agenda:material",
        message: `material da agenda: ${erros.length} OS com erro (` +
          erros.slice(0, 5).map((e) => `${e.os ?? "?"}: ${e.msg ?? "?"}`).join("; ") + ")",
        details: { erros },
      });
    }
    return { oss: r.oss ?? 0, criadas: r.criadas ?? 0, atualizadas: r.atualizadas ?? 0, erros: erros.length };
  } catch (e) {
    // deno-lint-ignore no-explicit-any
    const msg = String((e as any)?.message ?? e);
    console.error("agenda:material failed:", e);
    await logEdgeError(db, {
      context: "task-automations",
      action: "agenda:material",
      message: `material da agenda: ${msg}`,
      // deno-lint-ignore no-explicit-any
      details: { code: (e as any)?.code ?? null },
      error: e,
    });
    return { erro: msg };
  }
}
