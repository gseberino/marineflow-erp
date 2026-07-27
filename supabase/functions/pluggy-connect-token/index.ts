// Edge Function: pluggy-connect-token
// Gera um Connect Token do Pluggy para o frontend abrir o widget Pluggy Connect
// (fluxo de consentimento Open Finance). Substitui o exemplo Next.js do quickstart
// do Pluggy (app/api/connect-token) na nossa stack Vite + Supabase.
// verify_jwt = true (default): só usuários logados no ERP conseguem chamar —
// o gateway barra chamadas anônimas antes de chegar aqui.
// Credenciais ficam SÓ em Supabase secrets (PLUGGY_CLIENT_ID / PLUGGY_CLIENT_SECRET);
// nada de client_id/secret no navegador — o browser só recebe o accessToken
// de curta duração, que é o desenho recomendado pelo próprio Pluggy.

const PLUGGY_API = "https://api.pluggy.ai";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function jr(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });
  if (req.method !== "POST") return jr({ error: "method_not_allowed" }, 405);

  const clientId = Deno.env.get("PLUGGY_CLIENT_ID");
  const clientSecret = Deno.env.get("PLUGGY_CLIENT_SECRET");
  if (!clientId || !clientSecret) {
    console.error("[pluggy-connect-token] PLUGGY_CLIENT_ID/PLUGGY_CLIENT_SECRET ausentes nos secrets.");
    return jr({ error: "provider_not_configured" }, 500);
  }

  // itemId opcional: quando presente, o widget abre em modo "update" para
  // reconectar/renovar o consentimento de uma conexão existente.
  const { clientUserId, itemId } = await req.json().catch(() => ({}));

  try {
    // 1) Autentica no Pluggy (apiKey de curta duração, ~2h — gerada a cada chamada,
    //    sem cache, para não guardar material sensível entre execuções).
    const authRes = await fetch(`${PLUGGY_API}/auth`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ clientId, clientSecret }),
    });
    if (!authRes.ok) {
      console.error("[pluggy-connect-token] /auth falhou:", authRes.status, await authRes.text());
      return jr({ error: "pluggy_auth_failed" }, 502);
    }
    const { apiKey } = await authRes.json();

    // 2) Cria o Connect Token que o widget consome no navegador.
    const tokenRes = await fetch(`${PLUGGY_API}/connect_token`, {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-API-KEY": apiKey },
      body: JSON.stringify({
        ...(itemId ? { itemId } : {}),
        options: { ...(clientUserId ? { clientUserId } : {}) },
      }),
    });
    if (!tokenRes.ok) {
      console.error("[pluggy-connect-token] /connect_token falhou:", tokenRes.status, await tokenRes.text());
      return jr({ error: "connect_token_failed" }, 502);
    }
    const { accessToken } = await tokenRes.json();
    return jr({ accessToken });
  } catch (e) {
    console.error("[pluggy-connect-token] erro inesperado:", e);
    return jr({ error: "unexpected_error" }, 500);
  }
});
