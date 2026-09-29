// Edge Function: assinatura-do-link
//
// A página pública da OS (/view/:token, sem login) mostra a assinatura do cliente. Desde
// 29/09/2026 o bucket `signatures` é privado: esta função confere o token do link, acha a
// assinatura válida daquela OS e devolve um link TEMPORÁRIO só da imagem. O PDF assinado
// (com nome, CPF/CNPJ e endereço) não sai por aqui: só a tela interna, logada, o abre.
//
// verify_jwt = false (config.toml): quem chama é o cliente, sem sessão. A proteção é o token
// da OS (uuid), o mesmo que já abre a página.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import { ORIGEM_PADRAO, servirComCors } from "../_shared/cors.ts";
import { caminhoNoBucket } from "../_shared/arquivo-privado.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": ORIGEM_PADRAO,
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const VALIDADE_S = 600;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function jr(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

servirComCors(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });
  if (req.method !== "POST") return jr({ error: "Use POST." }, 405);

  try {
    const body = await req.json().catch(() => ({})) as { share_token?: string };
    const token = String(body.share_token ?? "").trim();
    // Token malformado nem chega ao banco (e não distingue "inválido" de "de outra OS").
    if (!UUID.test(token)) return jr({ imagem_url: null });

    const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const { data: ordem } = await admin
      .from("service_orders").select("id").eq("share_token", token).maybeSingle();
    if (!ordem) return jr({ imagem_url: null });

    const { data: assinatura } = await admin
      .from("service_order_signatures")
      .select("signature_image_url")
      .eq("service_order_id", ordem.id)
      .is("superseded_at", null)
      .order("signed_at", { ascending: false })
      .limit(1)
      .maybeSingle();

    const caminho = caminhoNoBucket(assinatura?.signature_image_url, "signatures");
    if (!caminho) return jr({ imagem_url: null });

    const { data: link, error } = await admin.storage.from("signatures").createSignedUrl(caminho, VALIDADE_S);
    if (error || !link?.signedUrl) {
      console.warn("[assinatura-do-link] não gerou o link:", error?.message);
      return jr({ imagem_url: null });
    }
    return jr({ imagem_url: link.signedUrl, validade_s: VALIDADE_S });
  } catch (e) {
    console.error("[assinatura-do-link] erro", e);
    return jr({ error: "Erro ao buscar a assinatura." }, 500);
  }
});
