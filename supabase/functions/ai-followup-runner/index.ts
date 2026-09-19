// Edge Function: ai-followup-runner — o maquinista do "Deixar a IA acompanhar".
//
// Acorda de hora em hora (pg_cron) e, para cada missão em andamento:
//   1. relê o ERP (Princípio 1): tarefa concluída, orçamento decidido ou fio solto fechado →
//      a missão fecha SEM falar com ninguém;
//   2. devolve ao dono o que estourou (teto de toques sem resposta, prazo vencido);
//   3. se há toque devido, está na janela (seg-sex 9-18h de Brasília), ainda não tocou hoje e
//      o teto diário não foi atingido → redige o toque no tom da casa e grava uma PENDÊNCIA
//      de aprovação (ai_operator_pending_actions, action followup_send_touch). Fase 1 é
//      copiloto: nada sai daqui sem o "sim" do dono no sino.
//
// Resposta do terceiro é dado, não comando: quem a recebe é o webhook (followup_registrar_
// resposta), que pausa a missão em waiting_reply para o dono ler. Este runner não interpreta
// respostas (Fase 2).
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import { verificarCronSecret } from "../_shared/cron-auth.ts";
import { callClaude, type ClaudeToolSchema } from "../_shared/ai/anthropic.ts";
import { MODEL_LITE } from "../_shared/ai/models.ts";
import { perfilDeVoz, perfilParaPrompt } from "../_shared/ai/comms/voice-profiles.ts";
import { guardaDeEnvio } from "../_shared/ai/comms/send-guard.ts";
import { dentroDaJanela, esperaFinalEsgotada, jaTocouHoje, partesBrasilia } from "../_shared/ai/followups/cadencia.ts";
import { ORIGEM_PADRAO, servirComCors } from "../_shared/cors.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": ORIGEM_PADRAO,
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-cron-secret",
  "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
};
const jr = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } });

const PROPOR_TOQUE: ClaudeToolSchema = {
  name: "propor_toque",
  description: "Devolve a mensagem de WhatsApp pronta para o dono aprovar.",
  input_schema: {
    type: "object",
    properties: {
      mensagem: { type: "string", description: "Texto final da mensagem, em português do Brasil, pronto para enviar." },
      justificativa: { type: "string", description: "Uma frase para o dono: por que este texto, agora." },
    },
    required: ["mensagem", "justificativa"],
  },
};

type Missao = Record<string, any>;

/** Camada 1 do "resolveu": o ERP prova. Devolve a evidência ou null. */
async function erpResolveu(admin: any, m: Missao): Promise<string | null> {
  if (m.criterio_erp === "task_done" && m.origem_id) {
    const { data } = await admin.from("agenda_tasks").select("status, completed_at").eq("id", m.origem_id).maybeSingle();
    if (!data) return "tarefa de origem não existe mais";
    if (data.status === "done") return `tarefa concluída em ${data.completed_at ?? "data não registrada"}`;
  }
  if (m.criterio_erp === "quote_decided" && m.origem_id) {
    const { data } = await admin.from("service_orders").select("quote_status, status, service_order_number").eq("id", m.origem_id).maybeSingle();
    if (!data) return "orçamento de origem não existe mais";
    if (["approved", "awaiting_deposit", "rejected"].includes(data.quote_status)) return `${data.service_order_number}: orçamento ${data.quote_status}`;
    if (data.status !== "draft") return `${data.service_order_number} virou OS (${data.status})`;
  }
  if (m.criterio_erp === "open_loop_resolved" && m.open_loop_id) {
    const { data } = await admin.from("entity_open_loops").select("status, resolved_reason, resolved_at").eq("id", m.open_loop_id).maybeSingle();
    if (data?.status === "resolved") return `fio solto fechado (${data.resolved_reason ?? "sem motivo"}) em ${data.resolved_at ?? "?"}`;
  }
  return null;
}

async function notificar(admin: any, userId: string | null, title: string, body: string) {
  if (!userId) return;
  try {
    await admin.from("app_notifications").insert({ user_id: userId, type: "followup_mission", title, body, navigate_to: "/v2/agenda/acompanhamentos" });
  } catch { /* best-effort */ }
}

async function fechar(admin: any, m: Missao, status: string, tipoEvento: string, conteudo: string, evidencia?: string) {
  await admin.from("ai_followup_missions").update({
    status, resolucao: conteudo, resolucao_evidencia: evidencia ?? null, resolvida_em: new Date().toISOString(), proximo_toque_em: null,
  }).eq("id", m.id);
  await admin.from("ai_followup_events").insert({ mission_id: m.id, tipo: tipoEvento, conteudo, evidencia: evidencia ?? null });
  // Rascunho parado no sino não pode mais ser aprovado: a missão acabou.
  const { data: rasc } = await admin.from("ai_followup_events").select("pending_action_id").eq("mission_id", m.id).eq("tipo", "draft").not("pending_action_id", "is", null);
  for (const r of (rasc as any[]) || []) {
    await admin.from("ai_operator_pending_actions").update({ status: "expired" }).eq("id", r.pending_action_id).eq("status", "pending");
  }
}

/** Contexto que o modelo precisa para escrever UM toque útil, e nada mais. */
async function montarContexto(admin: any, m: Missao) {
  const partes: string[] = [];
  if (m.origem_tipo === "agenda_task" && m.origem_id) {
    const { data } = await admin.from("agenda_tasks").select("title, description, due_at, notes").eq("id", m.origem_id).maybeSingle();
    if (data) partes.push(`Tarefa de origem: "${data.title}"${data.description ? ` — ${data.description}` : ""}${data.due_at ? ` (prazo da tarefa: ${String(data.due_at).slice(0, 10)})` : ""}.`);
  }
  if (m.origem_tipo === "quote" && m.origem_id) {
    const { data } = await admin.from("service_orders").select("service_order_number, grand_total, updated_at, quote_status, vessels(name)").eq("id", m.origem_id).maybeSingle();
    if (data) {
      const { data: servs } = await admin.from("service_order_services").select("name_snapshot").eq("service_order_id", m.origem_id).limit(4);
      const nomes = ((servs as any[]) || []).map((s) => s.name_snapshot).filter(Boolean).join(", ");
      partes.push(`Orçamento ${data.service_order_number}${(data as any).vessels?.name ? ` para ${(data as any).vessels.name}` : ""}, situação "${data.quote_status}", enviado/atualizado em ${String(data.updated_at).slice(0, 10)}${nomes ? `; serviços: ${nomes}` : ""}. NÃO cite valores.`);
    }
  }
  if (m.origem_tipo === "open_loop" && m.open_loop_id) {
    const { data } = await admin.from("entity_open_loops").select("title, detail, evidence, due_at").eq("id", m.open_loop_id).maybeSingle();
    if (data) partes.push(`Compromisso: "${data.title}"${data.detail ? ` — ${data.detail}` : ""}${data.evidence ? ` (na conversa: "${String(data.evidence).slice(0, 160)}")` : ""}.`);
  }
  const { data: msgs } = await admin.from("whatsapp_messages")
    .select("direction, body, occurred_at").eq("phone_normalized", m.contraparte_phone)
    .order("occurred_at", { ascending: false }).limit(6);
  const historico = (((msgs as any[]) || []).reverse())
    .map((x) => `[${String(x.occurred_at ?? "").slice(0, 10)}] ${x.direction === "outbound" ? "HBR" : m.contraparte_label}: ${String(x.body ?? "").slice(0, 200)}`)
    .join("\n");
  const { data: toques } = await admin.from("ai_followup_events").select("tipo, conteudo, pending_action_id, created_at")
    .eq("mission_id", m.id).in("tipo", ["touch_sent", "draft"]).order("created_at", { ascending: true });
  const enviados = ((toques as any[]) || []).filter((t) => t.tipo === "touch_sent").map((t) => `- ${String(t.conteudo).slice(0, 300)}`);
  // Feedback do dono num rascunho rejeitado ("Ensinar a IA") é a instrução mais valiosa que existe.
  let feedback = "";
  const ultimoDraft = ((toques as any[]) || []).filter((t) => t.tipo === "draft" && t.pending_action_id).pop();
  if (ultimoDraft) {
    const { data: aud } = await admin.from("ai_operator_audit").select("event_type, payload").eq("pending_action_id", ultimoDraft.pending_action_id).order("created_at", { ascending: false }).limit(1).maybeSingle();
    if (aud && String(aud.event_type).startsWith("reject:")) {
      feedback = `O dono REJEITOU o rascunho anterior ("${String(ultimoDraft.conteudo).slice(0, 200)}")${aud.payload?.user_note ? ` com a observação: "${aud.payload.user_note}"` : ""}. Escreva diferente, obedecendo à observação.`;
    }
  }
  return { partes, historico, enviados, feedback };
}

servirComCors(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });
  const recusa = verificarCronSecret(req, corsHeaders, "ai-followup-runner");
  if (recusa) return recusa;

  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const resumo = { verificadas: 0, resolvidas_pelo_erp: 0, devolvidas_ao_dono: 0, rascunhos: 0, puladas: [] as string[] };
  // Disparo manual (só passa quem tem o cron secret): `{"ignorar_janela": true}` rascunha fora
  // do horário comercial. O rascunho ainda vai para o sino — o ENVIO continua respeitando a
  // guarda de horário na hora da aprovação.
  let ignorarJanela = false;
  try { const b = await req.json(); ignorarJanela = b?.ignorar_janela === true; } catch { /* corpo vazio é o normal do cron */ }
  try {
    const { data: srows } = await admin.from("app_settings").select("key, value")
      .in("key", ["followup_missions_enabled", "followup_missions_daily_cap", "company_name"]);
    const s = Object.fromEntries(((srows as any[]) || []).map((r) => [r.key, String(r.value ?? "")]));
    if ((s.followup_missions_enabled ?? "true").trim().toLowerCase() === "false") return jr({ ok: true, skipped: "kill_switch" });
    const cap = parseInt(s.followup_missions_daily_cap || "10", 10) || 10;
    const empresa = s.company_name || "HBR Marine Solutions";
    const agora = new Date();

    const { data: missoes, error } = await admin.from("ai_followup_missions").select("*")
      .in("status", ["active", "waiting_reply"]).order("created_at", { ascending: true });
    if (error) return jr({ ok: false, error: error.message }, 500);

    // Teto diário conta rascunhos criados hoje + toques enviados hoje: o que já está no sino
    // também vai sair hoje se for aprovado.
    const { dataISO } = partesBrasilia(agora);
    const inicioDia = new Date(`${dataISO}T03:00:00Z`).toISOString();
    const { count: jaHoje } = await admin.from("ai_followup_events").select("id", { count: "exact", head: true })
      .in("tipo", ["touch_sent", "draft"]).gte("created_at", inicioDia);
    let orcamentoDoDia = Math.max(0, cap - (jaHoje ?? 0));

    for (const m of (missoes as Missao[]) || []) {
      resumo.verificadas++;
      const evid = await erpResolveu(admin, m);
      if (evid) {
        await fechar(admin, m, "resolved", "erp_resolved", "Resolvido pelo ERP — ninguém precisou ser cobrado.", evid);
        await notificar(admin, m.criada_por, `Missão resolvida sozinha: ${m.contraparte_label}`, evid);
        resumo.resolvidas_pelo_erp++;
        continue;
      }
      if (m.status === "waiting_reply") { resumo.puladas.push(`${m.id}: esperando o dono ler a resposta`); continue; }

      const semToquesRestantes = Number(m.toques_feitos) >= Number(m.max_toques);
      if ((semToquesRestantes || (m.prazo_final && new Date(m.prazo_final) <= agora)) && esperaFinalEsgotada(m.ultimo_toque_em, m.prazo_final, agora)) {
        const motivo = semToquesRestantes ? `Sem resposta após ${m.toques_feitos} toque(s).` : "Prazo venceu sem resposta.";
        await fechar(admin, m, "escalated", "escalated", `${motivo} Devolvida ao dono.`);
        await notificar(admin, m.criada_por, `A IA devolveu: ${m.contraparte_label}`, `${motivo} Objetivo: ${m.objetivo}`);
        resumo.devolvidas_ao_dono++;
        continue;
      }
      if (semToquesRestantes) { resumo.puladas.push(`${m.id}: último toque dado, esperando resposta`); continue; }

      // Rascunho já no sino? Então é com o dono. Rejeitado/expirado sem envio? Rearma.
      const { data: drafts } = await admin.from("ai_followup_events").select("id, pending_action_id, created_at")
        .eq("mission_id", m.id).eq("tipo", "draft").order("created_at", { ascending: false }).limit(1);
      const ultimoDraft = ((drafts as any[]) || [])[0];
      if (ultimoDraft?.pending_action_id) {
        const { data: pa } = await admin.from("ai_operator_pending_actions").select("status").eq("id", ultimoDraft.pending_action_id).maybeSingle();
        if (pa?.status === "pending" || pa?.status === "approved") { resumo.puladas.push(`${m.id}: rascunho aguardando decisão`); continue; }
        if ((pa?.status === "rejected" || pa?.status === "expired" || pa?.status === "failed") && !m.proximo_toque_em) {
          // Rejeitado: tenta de novo já (com o feedback do dono); expirado/falhou: amanhã.
          const quando = pa.status === "rejected" ? agora : new Date(agora.getTime() + 86_400_000);
          await admin.from("ai_followup_missions").update({ proximo_toque_em: quando.toISOString() }).eq("id", m.id);
          await admin.from("ai_followup_events").insert({ mission_id: m.id, tipo: "skipped", conteudo: `Rascunho ${pa.status}; nova tentativa ${pa.status === "rejected" ? "na próxima janela" : "amanhã"}.` });
          m.proximo_toque_em = quando.toISOString();
        }
      }

      if (!m.proximo_toque_em || new Date(m.proximo_toque_em) > agora) { resumo.puladas.push(`${m.id}: próximo toque em ${m.proximo_toque_em ?? "—"}`); continue; }
      if (!dentroDaJanela(agora) && !ignorarJanela) { resumo.puladas.push(`${m.id}: fora da janela seg-sex 9-18h`); continue; }
      if (jaTocouHoje(m.ultimo_toque_em, agora)) { resumo.puladas.push(`${m.id}: já tocou hoje`); continue; }
      // Rascunho já criado hoje (mesmo que rejeitado) não gera outro: um por dia.
      if (ultimoDraft && jaTocouHoje(ultimoDraft.created_at, agora)) { resumo.puladas.push(`${m.id}: já rascunhou hoje`); continue; }
      if (orcamentoDoDia <= 0) { resumo.puladas.push(`${m.id}: teto diário (${cap})`); continue; }

      const audiencia = m.contraparte_tipo === "supplier" ? "fornecedor" : "cliente";
      const perfil = perfilDeVoz(audiencia, "whatsapp");
      const ctx = await montarContexto(admin, m);
      const toque = Number(m.toques_feitos) + 1;
      const system = [
        `Você é o assistente virtual da ${empresa} e vai redigir UMA mensagem de WhatsApp para ${m.contraparte_label} (${audiencia}).`,
        `Objetivo da missão: ${m.objetivo}.`,
        `Este é o toque ${toque} de no máximo ${m.max_toques}.${m.prazo_final ? ` Prazo final que importa para a ${empresa}: ${String(m.prazo_final).slice(0, 10)}.` : ""}`,
        toque === 1
          ? `OBRIGATÓRIO no primeiro toque: identifique-se como assistente virtual da ${empresa} (uma frase curta). Nos seguintes, não repita.`
          : "Não se identifique de novo; retome o assunto com um gancho novo, sem repetir o toque anterior.",
        "A mensagem é SOBRE o objetivo da missão e sobre a origem descrita abaixo — o histórico de conversa serve só para tom e continuidade; não invente assunto a partir dele nem cobre coisa que não é o objetivo.",
        "Regras: uma pergunta objetiva; tom cordial e direto; NUNCA negocie preço, prazo ou condição; não cite valores; não ameace; sem links; sem emojis em excesso; termine de um jeito que facilite responder.",
        perfilParaPrompt(perfil),
        ctx.feedback,
      ].filter(Boolean).join("\n");
      const user = [
        ...ctx.partes,
        ctx.historico ? `Últimas mensagens trocadas com esta pessoa:\n${ctx.historico}` : "Não há conversa recente registrada com esta pessoa.",
        ctx.enviados.length ? `Toques desta missão já enviados (não repetir):\n${ctx.enviados.join("\n")}` : "",
        "Redija a mensagem chamando a tool propor_toque.",
      ].filter(Boolean).join("\n\n");

      let mensagem = ""; let justificativa = "";
      try {
        const r = await callClaude({ model: MODEL_LITE, system: [{ type: "text", text: system }], messages: [{ role: "user", content: [{ type: "text", text: user }] }], tools: [PROPOR_TOQUE], maxTokens: 700 });
        const call = r.content.find((b: any) => b.type === "tool_use" && b.name === "propor_toque") as any;
        mensagem = String(call?.input?.mensagem ?? "").trim();
        justificativa = String(call?.input?.justificativa ?? "").trim();
      } catch (e) {
        resumo.puladas.push(`${m.id}: LLM falhou (${(e as Error).message.slice(0, 80)})`);
        continue;
      }
      if (!mensagem) { resumo.puladas.push(`${m.id}: modelo não devolveu mensagem`); continue; }
      // No rascunho só interessa o TEXTO (linter + travas textuais). O horário é regra de
      // ENVIO e é conferido de novo por followup_send_touch na hora da aprovação — um toque
      // redigido à noite pode e deve esperar no sino até o horário comercial.
      const guarda = guardaDeEnvio(mensagem, { tipo: "generico", audiencia, canal: "whatsapp", horaBrasilia: 12, destinatarioIdentificado: Boolean(m.contraparte_id), texto: mensagem });
      if (guarda.bloqueado) { resumo.puladas.push(`${m.id}: guarda bloqueou (${guarda.codigoBloqueio})`); continue; }

      const { data: ev } = await admin.from("ai_followup_events").insert({
        mission_id: m.id, tipo: "draft", conteudo: mensagem,
        meta: { toque, de: m.max_toques, justificativa, avisos: guarda.avisos },
      }).select("id").single();
      const summary = [
        `**Missão:** ${m.objetivo}`,
        `**Para:** ${m.contraparte_label} (${audiencia}) · ${m.contraparte_phone}`,
        `**Toque:** ${toque} de ${m.max_toques}${m.prazo_final ? ` · prazo ${String(m.prazo_final).slice(0, 10)}` : ""}`,
        "",
        mensagem.split("\n").map((l) => `> ${l}`).join("\n"),
        "",
        justificativa ? `_${justificativa}_` : "",
        guarda.avisos.length ? `\n⚠️ ${guarda.avisos.join(" · ")}` : "",
      ].filter((l) => l !== undefined).join("\n");
      const { data: pend } = await admin.from("ai_operator_pending_actions").insert({
        requested_by_user_id: m.criada_por,
        action_name: "followup_send_touch",
        risk_level: "high",
        risk_reason: "Mensagem a terceiro em nome da empresa (Deixar a IA acompanhar, copiloto)",
        title: `Toque ${toque}/${m.max_toques} · ${m.contraparte_label}`,
        summary,
        payload: { mission_id: m.id, event_id: (ev as any).id },
        status: "pending",
        expires_at: new Date(agora.getTime() + 24 * 60 * 60 * 1000).toISOString(),
      }).select("id").single();
      await admin.from("ai_followup_events").update({ pending_action_id: (pend as any)?.id ?? null }).eq("id", (ev as any).id);
      await admin.from("ai_followup_missions").update({ proximo_toque_em: null }).eq("id", m.id);
      await notificar(admin, m.criada_por, `A IA redigiu um toque para ${m.contraparte_label}`, "Aprove ou rejeite no sino de pendências.");
      orcamentoDoDia--;
      resumo.rascunhos++;
    }
    return jr({ ok: true, ...resumo });
  } catch (e) {
    console.error("[ai-followup-runner]", e);
    return jr({ ok: false, error: (e as Error).message, ...resumo }, 500);
  }
});
