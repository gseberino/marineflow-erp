/**
 * Autenticação das funções chamadas pelo pg_cron (MF-AUD-054).
 *
 * Estas funções rodam com `verify_jwt = false` — o gateway não pode exigir JWT
 * porque o pg_cron chama sem Authorization, mandando só `x-cron-secret`. Isso
 * significa que o segredo é a ÚNICA autenticação: sem ele, a URL fica aberta
 * na internet e qualquer um dispara o worker (no caso da fila de WhatsApp,
 * isso faz sair mensagem de verdade e esgota o limite por hora).
 *
 * O valor comparado é o secret `CRON_SECRET` do Supabase. O pg_cron manda
 * `app_settings.cron_worker_secret`; os dois são o mesmo valor (conferido por
 * hash em 09/08/2026, sem expor o segredo).
 *
 * Fail-closed de propósito: sem o secret configurado, rejeita tudo. O padrão
 * antigo de algumas functions (`if (cronSecret && ...)`) é fail-OPEN — some o
 * env var, some a proteção, em silêncio. Ver `task-automations/index.ts:401`,
 * que segue no modelo antigo e vale alinhar depois.
 */

/** Comparação em tempo constante para não vazar o segredo por timing. */
function timingSafeEqual(a: string, b: string): boolean {
  const enc = new TextEncoder();
  const ab = enc.encode(a);
  const bb = enc.encode(b);
  if (ab.length !== bb.length) return false;
  let diff = 0;
  for (let i = 0; i < ab.length; i++) diff |= ab[i] ^ bb[i];
  return diff === 0;
}

/**
 * Devolve a Response de recusa, ou `null` quando a requisição está autorizada.
 * Deve ser chamada ANTES de qualquer I/O — é o que garante que uma requisição
 * anônima não alcance o banco nem o provedor de WhatsApp.
 */
export function verificarCronSecret(
  req: Request,
  corsHeaders: Record<string, string>,
  nomeDaFuncao: string,
): Response | null {
  const json = (body: unknown, status: number) =>
    new Response(JSON.stringify(body), {
      status,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });

  const esperado = Deno.env.get("CRON_SECRET");
  if (!esperado) {
    console.error(`[${nomeDaFuncao}] CRON_SECRET ausente nos secrets — rejeitando tudo.`);
    return json({ error: "not_configured" }, 500);
  }

  const apresentado = req.headers.get("x-cron-secret") ?? "";
  if (!timingSafeEqual(apresentado, esperado)) {
    console.warn(`[${nomeDaFuncao}] 401 — x-cron-secret ausente ou incorreto.`);
    return json({ error: "unauthorized" }, 401);
  }

  return null;
}
