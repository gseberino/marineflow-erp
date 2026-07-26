// Edge Function: agenda-voice-capture (Agenda Autônoma — Fase 9)
// Recebe um RECADO (áudio base64 do app, ou texto) e transforma em SUGESTÕES na
// Caixa de Entrada — um recado pode virar várias ("cobra a marina sexta E agenda a
// revisão do Pedro"). Autenticado com o JWT do usuário (é ação dele, não cron).
//
// Áudio: Groq Whisper (mesmo provedor já usado em whatsapp-transcribe-audio).
// Texto: pula a transcrição. Em ambos, a EVIDÊNCIA é a própria transcrição/texto —
// o princípio "nada sem evidência" vale igual.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import { callClaude } from "../_shared/ai/anthropic.ts";
import { MODEL_LITE } from "../_shared/ai/models.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
function jr(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } });
}

const SPLIT_TOOL = {
  name: "split_note",
  description: "Divide o recado em tarefas objetivas.",
  input_schema: {
    type: "object",
    properties: {
      tasks: {
        type: "array",
        items: {
          type: "object",
          properties: {
            title: { type: "string", description: "Ação no imperativo, curta e específica." },
            due_date: { type: "string", description: "YYYY-MM-DD se o recado indicar dia." },
            time: { type: "string", description: "HH:MM se houver hora explícita." },
            priority: { type: "string", enum: ["low", "normal", "high", "urgent"] },
          },
          required: ["title"],
        },
      },
    },
    required: ["tasks"],
  },
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });

  try {
    const authHeader = req.headers.get("Authorization") || "";
    const jwt = authHeader.replace("Bearer ", "");
    if (!jwt) return jr({ error: "não autenticado" }, 401);

    const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
    const { data: userData } = await admin.auth.getUser(jwt);
    const userId = userData?.user?.id;
    if (!userId) return jr({ error: "sessão inválida" }, 401);

    const { audio_base64, mimetype, text } = await req.json().catch(() => ({}));
    let transcript = String(text || "").trim();

    // 1) Áudio → texto (Groq Whisper)
    if (!transcript && audio_base64) {
      const GROQ_API_KEY = Deno.env.get("GROQ_API_KEY");
      if (!GROQ_API_KEY) return jr({ error: "Transcrição indisponível (GROQ_API_KEY não configurada)" }, 503);
      const bytes = Uint8Array.from(atob(String(audio_base64)), (c) => c.charCodeAt(0));
      const form = new FormData();
      form.append("file", new Blob([bytes], { type: String(mimetype || "audio/webm") }), "nota.webm");
      form.append("model", "whisper-large-v3-turbo");
      form.append("language", "pt");
      const res = await fetch("https://api.groq.com/openai/v1/audio/transcriptions", {
        method: "POST",
        headers: { Authorization: `Bearer ${GROQ_API_KEY}` },
        body: form,
      });
      const body = await res.json().catch(() => ({}));
      if (!res.ok) return jr({ error: "falha na transcrição", detail: String((body as any)?.error?.message || "").slice(0, 200) }, 502);
      transcript = String((body as any)?.text || "").trim();
    }

    if (!transcript) return jr({ error: "nada para processar (envie audio_base64 ou text)" }, 400);

    // 2) Texto → N tarefas
    const hojeBRT = new Date(Date.now() - 3 * 3600000).toISOString().slice(0, 10);
    const result = await callClaude({
      model: MODEL_LITE,
      system: [{
        type: "text",
        text: `Você recebe um recado ditado pelo dono de uma empresa de manutenção náutica e o transforma em tarefas objetivas.
Hoje é ${hojeBRT} (America/Sao_Paulo).
Regras:
- Um recado pode conter VÁRIAS tarefas ("cobra a marina sexta e agenda a revisão do Pedro" = 2).
- Título no imperativo, curto, mantendo nomes próprios ditos.
- Só coloque data se o recado disser ("sexta", "amanhã", "dia 12"); converta para YYYY-MM-DD.
- Hora só se explícita.
- Não invente nada que não foi dito. Se o recado não contiver tarefa alguma, devolva lista vazia.`,
      }],
      messages: [{ role: "user", content: [{ type: "text", text: transcript }] }],
      tools: [SPLIT_TOOL as any],
      maxTokens: 1000,
    });

    const call = result.content.find((b: any) => b.type === "tool_use" && b.name === "split_note") as any;
    const tasks = (call?.input?.tasks as any[]) || [];
    if (tasks.length === 0) {
      return jr({ ok: true, transcript, sugestoes: 0, mensagem: "Não identifiquei nenhuma tarefa nesse recado." });
    }

    // 3) Grava como SUGESTÕES (mesmo princípio: humano confirma)
    const { data: appUser } = await admin.from("app_users").select("id").eq("id", userId).maybeSingle();
    const rows = tasks.slice(0, 8).map((t: any) => {
      const dateStr = /^\d{4}-\d{2}-\d{2}$/.test(String(t.due_date || "")) ? String(t.due_date) : null;
      const timeStr = /^\d{2}:\d{2}$/.test(String(t.time || "")) ? String(t.time) : null;
      return {
        title: String(t.title).slice(0, 200),
        kind: timeStr ? "appointment" : "task",
        suggested_start_at: dateStr && timeStr ? new Date(`${dateStr}T${timeStr}:00-03:00`).toISOString() : null,
        suggested_due_at: dateStr && !timeStr ? new Date(`${dateStr}T08:00:00-03:00`).toISOString() : null,
        priority: ["low", "normal", "high", "urgent"].includes(String(t.priority)) ? String(t.priority) : "normal",
        evidence: transcript.slice(0, 1000),
        evidence_at: new Date().toISOString(),
        confidence: 0.95, // recado ditado pelo próprio dono: intenção explícita
        detector: "voice_note",
        origin: audio_base64 ? "voice_app" : "manual_text",
        target_user_id: (appUser as any)?.id ?? null,
      };
    });

    const { data: inserted, error } = await admin.from("agenda_suggestions").insert(rows).select("id, title");
    if (error) throw error;

    return jr({
      ok: true,
      transcript,
      sugestoes: inserted?.length ?? 0,
      itens: (inserted || []).map((i: any) => i.title),
    });
  } catch (e) {
    console.error("[agenda-voice-capture] fatal", e);
    return jr({ ok: false, error: String(e) }, 500);
  }
});
