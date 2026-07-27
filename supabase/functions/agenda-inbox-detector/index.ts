// Edge Function: agenda-inbox-detector (Agenda Autônoma — Fase 9)
// Lê as conversas de WhatsApp da janela recente, extrai COMPROMISSOS e grava
// SUGESTÕES (nunca tarefas) na Caixa de Entrada da Agenda.
// Escopo autorizado pelo usuário (26/07/2026): todas as conversas do número da HBR,
// com lista de exclusão por contato (agenda_detector_exclusions).
// Cursor em app_settings.agenda_detector_cursor evita reprocessar e limita custo.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import {
  detectInConversation, shouldAutoCreate,
  type ConversationMessage, type DetectorStats,
} from "../_shared/ai/inbox-detector.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-cron-secret",
  "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
};
function jr(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } });
}

const CURSOR_KEY = "agenda_detector_cursor";
const MAX_CONVERSATIONS_PER_RUN = 12; // teto de custo por execução

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });

  const cronSecret = Deno.env.get("CRON_SECRET");
  if (cronSecret && req.headers.get("x-cron-secret") !== cronSecret) {
    return jr({ error: "Unauthorized" }, 401);
  }

  const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

  try {
    const { data: settingsRows } = await db.from("app_settings").select("key, value")
      .in("key", [CURSOR_KEY, "agenda_detector_enabled", "agenda_autonomy_enabled"]);
    const settings = Object.fromEntries((settingsRows || []).map((s: any) => [s.key, s.value]));

    if ((settings["agenda_detector_enabled"] ?? "true") !== "true") {
      return jr({ ok: true, skipped: "disabled" });
    }
    // Autonomia graduada (Fase 11): nasce LIGADA, mas só age em detector que já provou
    // acerto (≥8 decisões e ≥80% de aceite). Até lá, tudo continua indo para a caixa.
    const autonomyEnabled = (settings["agenda_autonomy_enabled"] ?? "true") === "true";

    // Histórico de decisões por detector — a evidência que libera (ou não) a autonomia
    const { data: hist } = await db.from("agenda_suggestions")
      .select("detector, status").in("status", ["accepted", "dismissed"]).limit(1000);
    const statsByDetector: Record<string, DetectorStats> = {};
    for (const s of ((hist as any[]) || [])) {
      statsByDetector[s.detector] = statsByDetector[s.detector] || { accepted: 0, dismissed: 0 };
      if (s.status === "accepted") statsByDetector[s.detector].accepted++;
      else statsByDetector[s.detector].dismissed++;
    }

    // Janela: do cursor até agora (com piso de 24h para não varrer histórico inteiro)
    const floor = new Date(Date.now() - 24 * 3600000).toISOString();
    const cursor = settings[CURSOR_KEY] && settings[CURSOR_KEY] > floor ? settings[CURSOR_KEY] : floor;
    const runAt = new Date().toISOString();

    const { data: msgs } = await db.from("whatsapp_messages")
      .select("id, direction, body, occurred_at, message_type, phone_normalized, client_id")
      .gt("occurred_at", cursor)
      .lte("occurred_at", runAt)
      .order("occurred_at", { ascending: true })
      .limit(400);

    const rows = (msgs as any[]) || [];
    if (rows.length === 0) {
      await db.from("app_settings").upsert({ key: CURSOR_KEY, value: runAt }, { onConflict: "key" });
      return jr({ ok: true, novas_mensagens: 0, sugestoes: 0 });
    }

    // Exclusões (contatos que o detector nunca lê)
    const { data: excl } = await db.from("agenda_detector_exclusions").select("phone_normalized");
    const excluded = new Set(((excl as any[]) || []).map((e) => e.phone_normalized));

    // Destinatário da caixa de entrada: piloto = o dono (admin ativo com canal IA)
    const { data: owner } = await db.from("app_users")
      .select("id").eq("active", true).eq("ai_whatsapp_enabled", true)
      .order("created_at", { ascending: true }).limit(1).maybeSingle();
    const targetUserId = (owner as any)?.id ?? null;

    // Agrupa por conversa (telefone)
    const byPhone = new Map<string, any[]>();
    for (const m of rows) {
      const phone = m.phone_normalized || "desconhecido";
      if (excluded.has(phone)) continue;
      if (!byPhone.has(phone)) byPhone.set(phone, []);
      byPhone.get(phone)!.push(m);
    }

    // Conversas mais movimentadas primeiro (mais provável conter compromisso)
    const conversations = Array.from(byPhone.entries())
      .sort((a, b) => b[1].length - a[1].length)
      .slice(0, MAX_CONVERSATIONS_PER_RUN);

    let created = 0;
    let autoCreated = 0;
    const detalhes: any[] = [];

    for (const [phone, convMsgs] of conversations) {
      try {
        // Rótulo do contato: cliente cadastrado > telefone
        let contactLabel = phone;
        let clientId: string | null = null;
        const withClient = convMsgs.find((m: any) => m.client_id);
        if (withClient) {
          clientId = withClient.client_id;
          const { data: c } = await db.from("clients").select("name").eq("id", clientId).maybeSingle();
          if ((c as any)?.name) contactLabel = (c as any).name;
        }

        // Contexto: inclui até 10 mensagens anteriores da MESMA conversa (fora da janela),
        // senão "vou te mandar amanhã" isolado perde o assunto.
        const { data: prev } = await db.from("whatsapp_messages")
          .select("id, direction, body, occurred_at, message_type")
          .eq("phone_normalized", phone)
          .lte("occurred_at", convMsgs[0].occurred_at)
          .order("occurred_at", { ascending: false })
          .limit(10);
        const contextMsgs: ConversationMessage[] = [
          ...(((prev as any[]) || []).reverse()),
          ...convMsgs,
        ].filter((m, i, arr) => arr.findIndex((x) => x.id === m.id) === i);

        const proposals = await detectInConversation(contextMsgs, contactLabel);

        for (const p of proposals) {
          const auto = shouldAutoCreate(p, statsByDetector, autonomyEnabled);
          const { data: sugg, error } = await db.from("agenda_suggestions").insert({
            title: p.title,
            kind: p.kind,
            suggested_due_at: p.suggested_due_at,
            suggested_start_at: p.suggested_start_at,
            priority: p.priority || "normal",
            evidence: p.evidence,
            evidence_at: p.evidence_at,
            confidence: p.confidence,
            detector: p.detector,
            origin: "whatsapp",
            source_message_id: p.source_message_id,
            source_phone: phone,
            contact_label: contactLabel,
            client_id: clientId,
            related_entity_type: clientId ? "client" : null,
            related_entity_id: clientId,
            target_user_id: targetUserId,
          }).select("id").single();
          // 23505 = já existe sugestão viva idêntica para a mesma mensagem
          if (error) {
            if ((error as any).code !== "23505") console.error("insert suggestion:", error);
            continue;
          }
          created++;

          // Autonomia conquistada: cria a tarefa direto e marca a sugestão como aceita.
          // O card continua existindo (com o vínculo), então desfazer é 1 clique.
          if (auto) {
            const { data: task } = await db.from("agenda_tasks").insert({
              title: p.title,
              kind: p.kind,
              status: "pending",
              priority: p.priority || "normal",
              assignee_user_id: targetUserId,
              due_at: p.suggested_due_at,
              scheduled_start_at: p.suggested_start_at,
              client_id: clientId,
              related_entity_type: clientId ? "client" : null,
              related_entity_id: clientId,
              notes: `Criada automaticamente da conversa com ${contactLabel}\n"${p.evidence}"`,
              source: "ai",
            }).select("id").single();
            if (task) {
              await db.from("agenda_suggestions").update({
                status: "accepted",
                resolved_at: new Date().toISOString(),
                created_task_id: (task as any).id,
                dismiss_reason: "auto:autonomia",
              }).eq("id", (sugg as any).id);
              autoCreated++;
            }
          }
        }
        if (proposals.length > 0) {
          detalhes.push({ contato: contactLabel, propostas: proposals.length });
        }
      } catch (e) {
        console.error(`detector falhou na conversa ${phone}:`, e);
      }
    }

    await db.from("app_settings").upsert({ key: CURSOR_KEY, value: runAt }, { onConflict: "key" });

    if (created > 0) {
      await db.from("ai_operator_audit").insert({
        actor_kind: "system", event_type: "agenda_inbox_detector_run", event_category: "data",
        payload: { mensagens: rows.length, conversas: conversations.length, sugestoes: created, detalhes },
      }).then(() => {}, () => {});
    }

    return jr({
      ok: true,
      novas_mensagens: rows.length,
      conversas_analisadas: conversations.length,
      sugestoes: created,
      criadas_automaticamente: autoCreated,
      autonomia: Object.fromEntries(Object.entries(statsByDetector).map(([k, v]) => [
        k, `${v.accepted}/${v.accepted + v.dismissed}`,
      ])),
      detalhes,
    });
  } catch (e) {
    console.error("[agenda-inbox-detector] fatal", e);
    return jr({ ok: false, error: String(e) }, 500);
  }
});
