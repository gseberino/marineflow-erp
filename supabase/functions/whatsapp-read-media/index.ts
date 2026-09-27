// Edge Function: whatsapp-read-media
// Lê um DOCUMENTO (PDF) ou IMAGEM recebido no WhatsApp e transforma em TEXTO.
// Mesmo padrão do whatsapp-transcribe-audio: busca o base64 no Evolution
// (getBase64FromMediaMessage) e grava o resultado no corpo da mensagem com um marcador
// ("📄 …" para documento, "📷 …" para imagem), preservando "veio de PDF/imagem".
//
// Uso principal: resposta de COTAÇÃO que o fornecedor mandou como PDF ou foto do orçamento.
// O foco do prompt é extrair item / preço unitário / prazo — mas também devolve o texto geral,
// para não perder informação quando não for cotação.
//
// Degrada com graça: se faltar credencial ou a mídia não vier, a mensagem segue "[document]"/
// "[image]" e o agente pede o valor por texto. NUNCA lança erro fatal para quem chamou.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import { ORIGEM_PADRAO, servirComCors } from "../_shared/cors.ts";
// Finalidade "auto" (27/09/2026): foto mandada ao assistente por quem usa o financeiro — se for
// cupom ou comprovante, a primeira linha sai no formato que o webhook lê (_shared/ai/comprovante.ts).
import { legendaDaMidia, PEDIDO_DE_LEITURA_AUTO } from "../_shared/ai/comprovante.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": ORIGEM_PADRAO,
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
function jr(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } });
}

// Modelo leve: a extração é tarefa fechada e TODO número extraído ainda passa por confirmação
// humana antes de virar custo/ordem de compra — não vale pagar o modelo grande aqui.
const EXTRACTION_MODEL = "anthropic/claude-haiku-4.5";
/** ~3 MB de arquivo (em base64): acima disso a foto ao assistente não é lida. */
const TETO_DO_ARQUIVO_AUTO = 4_000_000;

const PROMPT = `Você recebeu um arquivo enviado por um FORNECEDOR pelo WhatsApp (normalmente uma cotação/orçamento).

Extraia o conteúdo em português, de forma compacta e fiel. Se houver itens com preços, liste um por linha no formato:
- <descrição do item> | unitário: R$ <valor> | prazo: <prazo se houver>

Regras:
- NÃO invente valores. Se um preço ou prazo não estiver no arquivo, escreva "não informado".
- Se houver total, frete ou condição de pagamento, inclua em uma linha "Observações:".
- Se o arquivo NÃO for uma cotação, apenas resuma o conteúdo em até 5 linhas.
- Responda só com o conteúdo extraído, sem preâmbulo.`;

servirComCors(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });
  try {
    const apiKey = Deno.env.get("OPENROUTER_API_KEY");
    if (!apiKey) return jr({ ok: false, disabled: "OPENROUTER_API_KEY não configurada" });

    const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
    const { message_id, force, finalidade } = await req.json().catch(() => ({}));
    // "cotacao" (padrão, o uso de sempre: resposta de fornecedor) ou "auto" (foto ao assistente).
    const pedido = finalidade === "auto" ? PEDIDO_DE_LEITURA_AUTO : PROMPT;
    if (!message_id) return jr({ error: "message_id obrigatório" }, 400);

    const { data: msg } = await admin
      .from("whatsapp_messages")
      .select("id, body, message_type, raw_payload")
      .eq("id", message_id)
      .maybeSingle();
    if (!msg) return jr({ error: "mensagem não encontrada" }, 404);

    const kind = msg.message_type === "image" ? "image" : msg.message_type === "document" ? "document" : null;
    if (!kind) return jr({ ok: true, skipped: "não é documento nem imagem" });

    const already = typeof msg.body === "string" && (msg.body.startsWith("📄") || msg.body.startsWith("📷"));
    if (already && !force) return jr({ ok: true, skipped: "já processado", text: msg.body });

    const key = (msg.raw_payload as any)?.data?.key;
    if (!key?.id) return jr({ ok: false, error: "sem key no payload" });

    // 1) Base64 da mídia (o webhook não traz o binário; o Evolution decifra).
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
      // Mídia antiga costuma expirar no WhatsApp — não é erro do sistema.
      return jr({ ok: false, error: "falha ao obter a mídia no Evolution (pode ter expirado)", detail: JSON.stringify(mediaBody).slice(0, 200) });
    }
    const mimetype = String((mediaBody as any)?.mimetype || (kind === "image" ? "image/jpeg" : "application/pdf")).split(";")[0];
    // Foto mandada ao assistente: comprovante é pequeno. PDF grande custaria por página e
    // atrasaria a resposta — fica sem ler, e o assistente pede o que precisa por texto.
    if (finalidade === "auto" && String(base64).length > TETO_DO_ARQUIVO_AUTO) {
      return jr({ ok: false, error: "arquivo grande demais para ler sozinho" });
    }
    const dataUri = `data:${mimetype};base64,${base64}`;

    // 2) Extração pelo modelo (formato OpenAI-compatível do OpenRouter).
    const contentBlock = kind === "image"
      ? { type: "image_url", image_url: { url: dataUri } }
      : { type: "file", file: { filename: "cotacao.pdf", file_data: dataUri } };

    const aiRes = await fetch("https://openrouter.ai/api/v1/chat/completions", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${apiKey}`,
        "Content-Type": "application/json",
        "HTTP-Referer": "https://hbrmarine.online",
      },
      body: JSON.stringify({
        model: EXTRACTION_MODEL,
        max_tokens: 1500,
        messages: [{ role: "user", content: [{ type: "text", text: pedido }, contentBlock] }],
      }),
      // Na foto ao assistente, a resposta ao dono espera por isto (o webhook desiste em 30 s).
      ...(finalidade === "auto" ? { signal: AbortSignal.timeout(25_000) } : {}),
    });
    const aiBody = await aiRes.json().catch(() => ({}));
    const text = String((aiBody as any)?.choices?.[0]?.message?.content || "").trim();
    if (!aiRes.ok || !text) {
      return jr({ ok: false, error: "falha na extração", detail: JSON.stringify(aiBody).slice(0, 300) });
    }

    // 3) Grava no corpo da mensagem (marcador mantém a origem: veio de PDF/imagem). Na foto
    //    mandada ao assistente, a legenda que a pessoa escreveu ("almoço da equipe, OS-60")
    //    continua no histórico, depois do texto lido — antes ela sumia, trocada pela leitura.
    const marker = kind === "image" ? "📷" : "📄";
    const legenda = finalidade !== "auto" ? null
      : already ? (String(msg.body).match(/\nLegenda: ([^\n]*)$/)?.[1] ?? null)
      : legendaDaMidia(msg.body);
    const final = legenda ? `\nLegenda: ${legenda.slice(0, 500)}` : "";
    await admin.from("whatsapp_messages").update({ body: `${marker} ${text}`.slice(0, 4000 - final.length) + final }).eq("id", message_id);

    return jr({ ok: true, kind, text });
  } catch (err) {
    return jr({ ok: false, error: err instanceof Error ? err.message : "erro" });
  }
});
