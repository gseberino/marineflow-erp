// Edge Function: whatsapp-transcribe-audio
// Transcreve uma nota de voz (áudio) recebida: busca o base64 no Evolution
// (getBase64FromMediaMessage) e envia ao Groq Whisper. Chamada fire-and-forget pelo
// whatsapp-webhook para áudios inbound. Grava a transcrição no corpo da mensagem ("🎤 …").
// Requer o secret GROQ_API_KEY. Degrada com graça: se algo falhar, a mensagem segue "[audio]"
// e o identify+forward continua valendo (nada quebra).
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
function jr(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });
  try {
    const GROQ_API_KEY = Deno.env.get("GROQ_API_KEY");
    // Sem chave ainda: não é erro fatal (o recurso simplesmente não está ligado).
    if (!GROQ_API_KEY) return jr({ ok: false, disabled: "GROQ_API_KEY não configurada" });

    const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
    const { message_id } = await req.json().catch(() => ({}));
    if (!message_id) return jr({ error: "message_id obrigatório" }, 400);

    const { data: msg } = await admin
      .from("whatsapp_messages")
      .select("id, body, message_type, raw_payload")
      .eq("id", message_id)
      .maybeSingle();
    if (!msg) return jr({ error: "mensagem não encontrada" }, 404);
    if (msg.message_type !== "audio") return jr({ ok: true, skipped: "não é áudio" });
    if (msg.body && msg.body !== "[audio]") return jr({ ok: true, skipped: "já processado" });

    const key = (msg.raw_payload as any)?.data?.key;
    if (!key?.id) return jr({ ok: false, error: "sem key no payload" });

    // 1) Base64 do Evolution (o webhook não traz o binário; o Evolution decifra a mídia).
    const evoUrl = (Deno.env.get("EVOLUTION_API_URL") || "").replace(/\/$/, "");
    const evoKey = Deno.env.get("EVOLUTION_API_KEY") || "";
    const evoInstance = Deno.env.get("EVOLUTION_INSTANCE") || "hbr-local";
    const mediaRes = await fetch(`${evoUrl}/chat/getBase64FromMediaMessage/${evoInstance}`, {
      method: "POST",
      headers: { "Content-Type": "application/json", apikey: evoKey },
      body: JSON.stringify({ message: { key } }),
    });
    const mediaBody = await mediaRes.json().catch(() => ({}));
    const base64 = (mediaBody as any)?.base64 || (typeof mediaBody === "string" ? mediaBody : null);
    if (!mediaRes.ok || !base64) {
      return jr({ ok: false, error: "falha ao obter áudio do Evolution", detail: JSON.stringify(mediaBody).slice(0, 200) });
    }
    const mimetype = String((mediaBody as any)?.mimetype || "audio/ogg").split(";")[0];

    // 2) Groq Whisper (whisper-large-v3-turbo: rápido, barato, ótimo em pt).
    const bytes = Uint8Array.from(atob(base64), (c) => c.charCodeAt(0));
    const form = new FormData();
    form.append("file", new Blob([bytes], { type: mimetype }), "audio.ogg");
    form.append("model", "whisper-large-v3-turbo");
    form.append("language", "pt");
    form.append("response_format", "json");
    const groqRes = await fetch("https://api.groq.com/openai/v1/audio/transcriptions", {
      method: "POST",
      headers: { Authorization: `Bearer ${GROQ_API_KEY}` },
      body: form,
    });
    const groqBody = await groqRes.json().catch(() => ({}));
    const text = String((groqBody as any)?.text || "").trim();
    if (!groqRes.ok || !text) {
      return jr({ ok: false, error: "falha na transcrição (Groq)", detail: JSON.stringify(groqBody).slice(0, 200) });
    }

    // 3) Grava a transcrição no corpo da mensagem (marcador 🎤 mantém o "veio de áudio").
    await admin.from("whatsapp_messages").update({ body: `🎤 ${text}`.slice(0, 4000) }).eq("id", message_id);
    return jr({ ok: true, text });
  } catch (err) {
    return jr({ ok: false, error: err instanceof Error ? err.message : "erro" });
  }
});
