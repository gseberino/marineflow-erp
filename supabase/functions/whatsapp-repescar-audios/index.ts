/**
 * Repescagem de áudio: transcreve o que a primeira tentativa não conseguiu.
 *
 * POR QUE ISTO EXISTE — a descoberta que motivou, medida em 24-25/09/2026:
 *
 * A mídia do WhatsApp **expira no Evolution em cerca de duas semanas**. Testado áudio a
 * áudio, semana a semana: de 14/09 em diante o Evolution devolve a mídia; de 07/09 para
 * trás responde "Message not found". Isso significa que uma janela de indisponibilidade
 * custa a conversa PARA SEMPRE — e não é hipótese: o Evolution ficou 4h30 fora do ar em
 * 24/09, e o acervo tinha 700 áudios mudos velhos demais para recuperar.
 *
 * A transcrição no webhook é fire-and-forget de propósito (não pode atrasar o recebimento
 * da mensagem). O preço disso é que ela falha em silêncio: Evolution caído, Groq fora,
 * túnel oscilando. Sem uma segunda passada, cada falha vira um buraco permanente no
 * histórico assim que a janela de duas semanas fecha.
 *
 * Esta função é essa segunda passada. Roda uma vez por dia, olha só os últimos 10 dias
 * (dentro da janela em que a mídia ainda existe) e tenta de novo o que ficou como
 * "[audio]".
 *
 * Ritmo deliberadamente lento: cada chamada faz o Evolution — que roda no PC do dono,
 * atrás do túnel — decifrar e devolver a mídia. Apressar para ganhar segundos num job
 * diário seria trocar um ganho nulo por risco real.
 */
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import { ORIGEM_PADRAO, servirComCors } from "../_shared/cors.ts";
import { verificarCronSecret } from "../_shared/cron-auth.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": ORIGEM_PADRAO,
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-cron-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function jr(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } });
}

import { DIAS_DA_JANELA as DIAS, TETO_POR_EXECUCAO as TETO, aindaMudo, repescar, temMidiaPedivel } from "./logica.ts";

servirComCors(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });

  const recusa = verificarCronSecret(req, corsHeaders, "whatsapp-repescar-audios");
  if (recusa) return recusa;

  try {
    const url = Deno.env.get("SUPABASE_URL")!;
    const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

    const desde = new Date(Date.now() - DIAS * 86400000).toISOString();
    // O "ainda está mudo?" é decidido em JS, não num filtro `.like`, de propósito: no
    // PostgREST o curinga do like é `*`, e um padrão com colchete (`[%]`) não faz o que
    // parece — devolveria zero linhas calado, e "nada pendente" é exatamente a resposta
    // que um filtro quebrado também dá. Dez dias de áudio cabem folgados em 300 linhas,
    // e `aindaMudo` já tem teste.
    const { data, error } = await admin
      .from("whatsapp_messages")
      .select("id, body, raw_payload")
      .eq("message_type", "audio")
      .gte("occurred_at", desde)
      .order("occurred_at", { ascending: false })
      .limit(300);
    if (error) return jr({ ok: false, error: error.message }, 500);

    // Sem a key no payload não há o que pedir ao Evolution — pular evita uma ida inútil.
    const alvos = ((data as any[]) || [])
      .filter((m) => aindaMudo(m?.body))
      .filter(temMidiaPedivel)
      .slice(0, TETO);
    if (alvos.length === 0) return jr({ ok: true, candidatos: 0, transcritos: 0, nota: "nada pendente na janela" });

    const motivos: string[] = [];
    const resumo = await repescar(alvos, async (id) => {
      const r = await fetch(`${url}/functions/v1/whatsapp-transcribe-audio`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")}`,
        },
        body: JSON.stringify({ message_id: id }),
      });
      const corpo = await r.json().catch(() => ({}));
      const ok = (corpo as any)?.ok === true && Boolean((corpo as any)?.text);
      if (!ok && motivos.length < 3) motivos.push(String((corpo as any)?.error ?? "sem detalhe").slice(0, 80));
      return { ok };
    });
    if (resumo.parouCedo) motivos.push("parou cedo: falhas seguidas (Evolution fora do ar ou mídia expirada)");

    return jr({
      ok: true,
      candidatos: alvos.length,
      tentativas: resumo.tentativas,
      transcritos: resumo.transcritos,
      falhas: resumo.falhas,
      motivos,
    });
  } catch (err) {
    return jr({ ok: false, error: err instanceof Error ? err.message : "erro" }, 500);
  }
});
