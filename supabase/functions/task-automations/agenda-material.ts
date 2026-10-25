// Passo do motor de 15 min: a vigia do material da Agenda de Produção (Fase 4, P5 — 25/10/2026).
//
// Roda logo DEPOIS da conferência do material (material-da-agenda.ts: as linhas de os_material em dia) e ANTES da rotina
// e da vigia (index.ts: a vigia lê a previsão já atualizada no mesmo tique). Chama agenda_material_vigiar (migration
// 20261027100500), que faz tudo no banco, passo a passo, cada um com o seu modo: a nota do e-mail e o Pix (modo_material),
// a conversa do fornecedor já lida pelo acompanhar-conversas (modo_detector), a pergunta ao fornecedor nos terços de um
// prazo longo (modo_fornecedor) e as perguntas de cadastro. TUDO o que vai ao fornecedor é decidido no banco (o modo, a
// janela de segunda a sexta, o teto, só a quem conversou com a HBR, o telefone dele) e entra na fila de sempre (source
// agenda-fornecedor), com a trava do gatilho da fila e a do worker; aqui nada é enviado.
//
// Os três modos desligados (produção hoje): nem chama o banco. A leitura dos modos que falha = desligado (o lado seguro);
// se a falha não é a Fase 4 ausente (a coluna que ainda não existe), vai a app_error_logs. O passo que falha no banco já
// vai a app_error_logs lá (context agenda, action material:<passo>) e os outros passos rodam.
//
// Nunca lança: erro vira `{ erro }` no resumo da rodada e uma linha em app_error_logs (task-automations,
// agenda:material-vigia).
import { diaBR } from "../_shared/agenda-dia.ts";
import { logEdgeError } from "../_shared/log-error.ts";
import { leituraSemAFase4, lerModosDoMaterial } from "./agenda-modos.ts";

// deno-lint-ignore no-explicit-any
type Db = any;

export interface ResultadoDaVigiaDoMaterial {
  /** Por que não chamou o banco (os modos desligados; os modos que não se leem). */
  pulado?: string;
  rodou?: boolean;
  modos?: { material?: string; detector?: string; fornecedor?: string };
  contagens?: Record<string, unknown>;
  /** Quantos passos falharam no banco (o detalhe já está em app_error_logs, action material:<passo>). */
  erros?: number;
  falhas?: unknown[];
  /** O passo inteiro falhou. */
  erro?: string;
}

/** O passo da vigia do material no motor. Nunca lança. */
export async function vigiarMaterialDaAgenda(db: Db, agora: Date = new Date()): Promise<ResultadoDaVigiaDoMaterial> {
  try {
    const modos = await lerModosDoMaterial(db);
    if (modos.erro !== undefined) {
      if (!leituraSemAFase4(modos)) {
        await logEdgeError(db, {
          context: "task-automations",
          action: "agenda:material-vigia",
          level: "warn",
          message: `vigia do material: não li os modos (${modos.codigo ?? "?"}): ${modos.erro}`,
          details: { codigo: modos.codigo ?? null },
        });
      }
      return { pulado: `não li os modos do material: ${modos.erro}` };
    }
    if (modos.material === "desligado" && modos.detector === "desligado" && modos.fornecedor === "desligado") {
      return { pulado: "modo_material, modo_detector e modo_fornecedor desligados" };
    }

    const { data, error } = await db.rpc("agenda_material_vigiar", { p_hoje: diaBR(agora.getTime()), p_agora: agora.toISOString() });
    if (error) throw error;
    const v = (data ?? {}) as Record<string, unknown>;
    return {
      rodou: v.rodou === true,
      modos: (v.modos ?? undefined) as ResultadoDaVigiaDoMaterial["modos"],
      contagens: (v.contagens ?? undefined) as Record<string, unknown> | undefined,
      erros: typeof v.erros === "number" ? v.erros : 0,
      falhas: Array.isArray(v.falhas) ? v.falhas : [],
    };
  } catch (e) {
    const msg = String((e as { message?: unknown })?.message ?? e);
    console.error("agenda:material-vigia failed:", e);
    await logEdgeError(db, {
      context: "task-automations",
      action: "agenda:material-vigia",
      message: `vigia do material: ${msg}`,
      details: { code: (e as { code?: unknown })?.code ?? null },
      error: e,
    });
    return { erro: msg };
  }
}
