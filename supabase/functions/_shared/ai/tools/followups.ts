// Tools do "Deixar a IA acompanhar" (plans/marineflow-ia-acompanha.md).
//
// A peça central é `followup_send_touch`: é o que o portão de aprovação executa quando o dono
// aprova um toque redigido pelo runner (ai-followup-runner). O texto NÃO vai no payload da
// pendência — o payload é imutável (trigger ai_op_protect_pending_action) e o texto vive no
// evento `draft` da missão, que o dono pode ajustar antes de aprovar. Fase 1 = copiloto: a
// tool está em NEVER_AUTONOMOUS, então nunca roda sem um "sim" humano.
import { blockTechnician, type ToolCtx, type ToolDef } from "./registry.ts";
import { guardaDeEnvio } from "../comms/send-guard.ts";
import { registrarEnvio } from "../comms/send-log.ts";
import { sendWhatsapp } from "./whatsapp.ts";
import { proximoToqueApos, partesBrasilia, proximaJanela } from "../followups/cadencia.ts";

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

async function lerSettings(admin: any, chaves: string[]): Promise<Record<string, string>> {
  const { data } = await admin.from("app_settings").select("key, value").in("key", chaves);
  return Object.fromEntries(((data as any[]) || []).map((r) => [r.key, String(r.value ?? "")]));
}

/** Toques já enviados hoje (dia de Brasília), em todas as missões — teto global do §6. */
export async function toquesEnviadosHoje(admin: any, agora = new Date()): Promise<number> {
  const { dataISO } = partesBrasilia(agora);
  // O dia de Brasília começa às 03:00Z; contar a partir daí evita misturar dois dias.
  const inicio = new Date(`${dataISO}T03:00:00Z`).toISOString();
  const { count } = await admin
    .from("ai_followup_events")
    .select("id", { count: "exact", head: true })
    .eq("tipo", "touch_sent")
    .gte("created_at", inicio);
  return count ?? 0;
}

async function contatoComOptOut(admin: any, tipo: string, id: string | null): Promise<boolean> {
  if (!id) return false;
  const tabela = tipo === "supplier" ? "suppliers" : tipo === "client" ? "clients" : null;
  if (!tabela) return false;
  const { data } = await admin.from(tabela).select("opt_out_whatsapp").eq("id", id).maybeSingle();
  return Boolean((data as any)?.opt_out_whatsapp);
}

export const followupTools: ToolDef[] = [
  {
    name: "followup_send_touch",
    description:
      "Envia ao terceiro (fornecedor/cliente) o toque de acompanhamento já redigido pela IA para uma missão " +
      "('Deixar a IA acompanhar'). Só é executada via aprovação do dono; o texto é o do evento draft indicado.",
    input_schema: {
      type: "object",
      properties: {
        mission_id: { type: "string", description: "id da missão (ai_followup_missions)" },
        event_id: { type: "string", description: "id do evento draft com o texto a enviar" },
      },
      required: ["mission_id", "event_id"],
    },
    risk: "high",
    execute: async (args: { mission_id: string; event_id: string }, ctx: ToolCtx) => {
      const blocked = blockTechnician(ctx);
      if (blocked) return blocked;
      if (!UUID_RE.test(args.mission_id || "") || !UUID_RE.test(args.event_id || "")) {
        return { error: "mission_id e event_id precisam ser UUIDs." };
      }
      const admin = ctx.admin;
      const settings = await lerSettings(admin, ["followup_missions_enabled", "followup_missions_daily_cap"]);
      if ((settings.followup_missions_enabled ?? "true").trim().toLowerCase() === "false") {
        return { error: "O acompanhamento pela IA está desligado nas configurações (followup_missions_enabled)." };
      }

      const { data: missao } = await admin.from("ai_followup_missions").select("*").eq("id", args.mission_id).maybeSingle();
      if (!missao) return { error: "Missão não encontrada." };
      if (missao.status === "waiting_reply") {
        return { error: "O contato respondeu depois deste rascunho — leia a resposta antes de mandar outra mensagem." };
      }
      if (missao.status !== "active") return { error: `A missão está ${missao.status}; nada a enviar.` };

      const { data: evento } = await admin
        .from("ai_followup_events").select("id, tipo, conteudo, meta").eq("id", args.event_id).eq("mission_id", args.mission_id).maybeSingle();
      if (!evento || evento.tipo !== "draft") return { error: "Rascunho não encontrado para esta missão." };
      const texto = String(evento.conteudo || "").trim();
      if (!texto) return { error: "O rascunho está vazio." };

      // O mesmo rascunho não sai duas vezes (aprovação repetida, retry do gateway).
      const { data: jaSaiu } = await admin
        .from("ai_followup_events").select("id").eq("mission_id", args.mission_id).eq("tipo", "touch_sent")
        .contains("meta", { draft_event_id: args.event_id }).limit(1);
      if ((jaSaiu as any[])?.length) return { error: "Este toque já foi enviado." };

      if (await contatoComOptOut(admin, missao.contraparte_tipo, missao.contraparte_id)) {
        await admin.from("ai_followup_missions").update({ status: "cancelled", resolucao: "opt-out do contato", resolvida_em: new Date().toISOString(), proximo_toque_em: null }).eq("id", missao.id);
        await admin.from("ai_followup_events").insert({ mission_id: missao.id, tipo: "cancelled", conteudo: "Contato pediu para não receber mensagens (opt-out); missão encerrada." });
        return { error: "O contato pediu para não receber mensagens (opt-out) — missão encerrada." };
      }

      const audiencia = missao.contraparte_tipo === "supplier" ? "fornecedor" : "cliente";
      const guarda = guardaDeEnvio(texto, {
        tipo: "generico", audiencia, canal: "whatsapp",
        destinatarioIdentificado: Boolean(missao.contraparte_id), texto,
      });
      if (guarda.bloqueado && guarda.codigoBloqueio !== "fora_de_horario") {
        await registrarEnvio(admin, { tipo: "followup", audiencia, entityKind: missao.contraparte_tipo, entityId: missao.contraparte_id, phone: missao.contraparte_phone, preview: texto, status: "blocked", blockCode: guarda.codigoBloqueio });
        return { error: guarda.motivo };
      }

      const cap = parseInt(settings.followup_missions_daily_cap || "10", 10) || 10;
      const hoje = await toquesEnviadosHoje(admin);
      if (hoje >= cap) return { error: `Teto diário de ${cap} toques de acompanhamento já atingido hoje (proteção do número).` };

      const agora = new Date();
      const toque = Number(missao.toques_feitos || 0) + 1;

      // O dono aprova à noite; o terceiro recebe de manhã. Fora do horário a mensagem vai para
      // a fila com hora marcada (próximo dia útil, 9h) — nunca falha, nunca sai fora de hora.
      // A fila não aplica wa_test_mode (o whatsapp-send aplica), então o desvio é feito aqui.
      if (guarda.bloqueado && guarda.codigoBloqueio === "fora_de_horario") {
        const quando = proximaJanela(agora);
        const teste = await lerSettings(admin, ["wa_test_mode", "wa_test_number"]);
        const testMode = (teste.wa_test_mode || "").trim() === "true";
        const testNumber = (teste.wa_test_number || "").replace(/\D/g, "");
        if (testMode && !testNumber) return { error: "Modo de teste do WhatsApp ligado sem número de teste." };
        const { error: erroFila } = await admin.from("whatsapp_send_queue").insert({
          phone_normalized: testMode ? testNumber : missao.contraparte_phone,
          message: texto, source: "ai_followup_mission", source_ref_id: missao.id,
          priority: 4, scheduled_for: quando.toISOString(),
        });
        if (erroFila) return { error: `Não deu para agendar o envio: ${erroFila.message}` };
        const proximo = proximoToqueApos(toque, Number(missao.max_toques || 3), missao.prazo_final, quando);
        await admin.from("ai_followup_events").insert({
          mission_id: missao.id, tipo: "touch_sent", conteudo: texto,
          meta: { draft_event_id: args.event_id, toque, de: missao.max_toques, agendado_para: quando.toISOString(), fila: true, avisos: guarda.avisos },
          created_by: ctx.userId || null,
        });
        await admin.from("ai_followup_missions").update({
          toques_feitos: toque, ultimo_toque_em: quando.toISOString(),
          proximo_toque_em: proximo ? proximo.toISOString() : null, status: "active",
        }).eq("id", missao.id);
        return {
          ok: true, toque, de: missao.max_toques, agendado_para: quando.toISOString(),
          aviso: `Fora do horário comercial: a mensagem foi agendada para ${quando.toLocaleString("pt-BR", { timeZone: "America/Sao_Paulo", day: "2-digit", month: "2-digit", hour: "2-digit", minute: "2-digit" })}.`,
        };
      }

      const envio = await sendWhatsapp(missao.contraparte_phone, texto, ctx.jwt);
      if ((envio as any).error) {
        await registrarEnvio(admin, { tipo: "followup", audiencia, entityKind: missao.contraparte_tipo, entityId: missao.contraparte_id, phone: missao.contraparte_phone, preview: texto, status: "failed" });
        return { error: `Falha no envio: ${(envio as any).error}` };
      }
      await registrarEnvio(admin, { tipo: "followup", audiencia, entityKind: missao.contraparte_tipo, entityId: missao.contraparte_id, phone: missao.contraparte_phone, preview: texto, status: "sent" });

      const proximo = proximoToqueApos(toque, Number(missao.max_toques || 3), missao.prazo_final, agora);
      await admin.from("ai_followup_events").insert({
        mission_id: missao.id, tipo: "touch_sent", conteudo: texto,
        meta: { draft_event_id: args.event_id, toque, de: missao.max_toques, message_id: (envio as any).messageId ?? null, avisos: guarda.avisos },
        created_by: ctx.userId || null,
      });
      await admin.from("ai_followup_missions").update({
        toques_feitos: toque,
        ultimo_toque_em: agora.toISOString(),
        proximo_toque_em: proximo ? proximo.toISOString() : null,
        status: "active",
      }).eq("id", missao.id);

      return {
        ok: true,
        toque, de: missao.max_toques,
        proximo_toque_em: proximo ? proximo.toISOString() : null,
        aviso: proximo ? undefined : "Foi o último toque previsto; sem resposta, a missão volta para o dono.",
      };
    },
  },
  {
    name: "listar_missoes_acompanhamento",
    description:
      "Lista as missões em que a IA está acompanhando um terceiro ('Deixar a IA acompanhar'): objetivo, contraparte, " +
      "toques dados, próximo toque e último evento. Por padrão só as em andamento.",
    input_schema: {
      type: "object",
      properties: {
        status: { type: "string", description: "active | waiting_reply | resolved | escalated | cancelled | expired | todas (padrão: em andamento)" },
        limit: { type: "number" },
      },
    },
    risk: "low",
    execute: async (args: { status?: string; limit?: number }, ctx: ToolCtx) => {
      let q = ctx.sb.from("ai_followup_missions")
        .select("id, objetivo, contraparte_tipo, contraparte_label, contraparte_phone, origem_tipo, status, toques_feitos, max_toques, proximo_toque_em, ultimo_toque_em, prazo_final, resolucao, created_at")
        .order("created_at", { ascending: false })
        .limit(Math.min(Math.max(Number(args.limit) || 30, 1), 100));
      const st = (args.status || "").trim();
      if (!st) q = q.in("status", ["active", "waiting_reply", "escalated"]);
      else if (st !== "todas") q = q.eq("status", st);
      const { data, error } = await q;
      if (error) return { error: error.message };
      const missoes = (data as any[]) || [];
      if (!missoes.length) return { missoes: [], resumo: "Nenhuma missão nesse filtro." };
      const ids = missoes.map((m) => m.id);
      const { data: eventos } = await ctx.sb.from("ai_followup_events")
        .select("mission_id, tipo, conteudo, created_at").in("mission_id", ids).order("created_at", { ascending: false }).limit(ids.length * 4);
      const ultimo = new Map<string, any>();
      for (const e of (eventos as any[]) || []) if (!ultimo.has(e.mission_id)) ultimo.set(e.mission_id, e);
      return {
        missoes: missoes.map((m) => ({
          ...m,
          ultimo_evento: ultimo.get(m.id) ? { tipo: ultimo.get(m.id).tipo, quando: ultimo.get(m.id).created_at, texto: String(ultimo.get(m.id).conteudo || "").slice(0, 200) } : null,
        })),
      };
    },
  },
  {
    name: "criar_missao_acompanhamento",
    description:
      "Cria uma missão 'Deixar a IA acompanhar': a IA passa a cobrar um terceiro (fornecedor ou cliente) sobre um " +
      "compromisso, redigindo cada mensagem para o dono aprovar. Origem: agenda_task (id da tarefa), quote (id do " +
      "orçamento), open_loop (id do fio solto) ou manual (informe contraparte_tipo/contraparte_id ou phone).",
    input_schema: {
      type: "object",
      properties: {
        origem_tipo: { type: "string", description: "agenda_task | quote | open_loop | manual" },
        origem_id: { type: "string" },
        objetivo: { type: "string", description: "O que acompanhar, na frase do dono. Ex.: 'confirmar a entrega das baterias'" },
        prazo_final: { type: "string", description: "ISO 8601; opcional. A cadência é contada para trás dele." },
        contraparte_tipo: { type: "string", description: "client | supplier | lead (opcional quando a origem já diz)" },
        contraparte_id: { type: "string" },
        phone: { type: "string", description: "telefone avulso, quando não há cadastro" },
        label: { type: "string", description: "como chamar a pessoa na mensagem" },
      },
      required: ["origem_tipo", "objetivo"],
    },
    risk: "medium",
    execute: async (args: any, ctx: ToolCtx) => {
      const blocked = blockTechnician(ctx);
      if (blocked) return blocked;
      const { data, error } = await ctx.sb.rpc("create_followup_mission", {
        p_origem_tipo: args.origem_tipo,
        p_origem_id: args.origem_id && UUID_RE.test(args.origem_id) ? args.origem_id : null,
        p_objetivo: args.objetivo,
        p_prazo_final: args.prazo_final || null,
        p_contraparte_tipo: args.contraparte_tipo || null,
        p_contraparte_id: args.contraparte_id && UUID_RE.test(args.contraparte_id) ? args.contraparte_id : null,
        p_phone: args.phone || null,
        p_label: args.label || null,
      });
      if (error) return { error: error.message };
      return { ok: true, mission_id: data, aviso: "A IA vai redigir o primeiro toque na próxima janela (seg-sex, 9h-18h) e pedir sua aprovação no sino." };
    },
  },
  {
    name: "cancelar_missao_acompanhamento",
    description: "Encerra uma missão de acompanhamento da IA antes de resolver (o dono desistiu ou resolveu por fora).",
    input_schema: {
      type: "object",
      properties: { mission_id: { type: "string" }, motivo: { type: "string" } },
      required: ["mission_id"],
    },
    risk: "medium",
    execute: async (args: { mission_id: string; motivo?: string }, ctx: ToolCtx) => {
      const blocked = blockTechnician(ctx);
      if (blocked) return blocked;
      if (!UUID_RE.test(args.mission_id || "")) return { error: "mission_id inválido." };
      const { data, error } = await ctx.sb.rpc("cancel_followup_mission", { p_id: args.mission_id, p_motivo: args.motivo || null });
      if (error) return { error: error.message };
      return data ? { ok: true } : { error: "Missão não estava em andamento." };
    },
  },
];
