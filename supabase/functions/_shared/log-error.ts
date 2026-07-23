// Registro de erros de EDGE FUNCTION na tabela app_error_logs (via RPC
// log_app_error). Complementa o console.error: o console fica nos logs do
// Supabase, que nem sempre estão acessíveis; a tabela é consultável por SQL.
//
// NUNCA lança: um log que derruba o fluxo é pior que não ter log. Por isso é
// "fire-and-forget" — o chamador não precisa await.

// deno-lint-ignore no-explicit-any
type SupabaseClient = any;

// Remove segredos óbvios do texto antes de gravar (mesma ideia do mask() do
// front): JWT, Bearer e tokens longos.
function mask(input: string): string {
  return String(input ?? "")
    .replace(/\beyJ[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{5,}\b/g, "<JWT>")
    .replace(/Bearer\s+[A-Za-z0-9._\-]+/gi, "Bearer <redacted>")
    .replace(/\b[A-Za-z0-9_\-]{40,}\b/g, (m) => `<token:${m.length}c>`);
}

export async function logEdgeError(
  supabase: SupabaseClient,
  input: {
    /** Nome da edge function — vira o `context` (ex.: "process-nfe-xml"). */
    context: string;
    message: string;
    action?: string;
    level?: "error" | "warn";
    // deno-lint-ignore no-explicit-any
    details?: Record<string, any>;
    error?: unknown;
  },
): Promise<void> {
  try {
    const msg = mask(input.message ?? "").slice(0, 2000);
    if (!msg.trim()) return;
    // deno-lint-ignore no-explicit-any
    const err = input.error as any;
    const details: Record<string, unknown> = { ...(input.details ?? {}) };
    if (err?.stack) details.stack = mask(String(err.stack)).slice(0, 4000);

    await supabase.rpc("log_app_error", {
      p_source: "edge",
      p_message: msg,
      p_context: input.context,
      p_action: input.action ?? null,
      p_level: input.level ?? "error",
      p_details: JSON.parse(mask(JSON.stringify(details)) || "{}"),
    });
  } catch {
    /* silencioso de propósito */
  }
}
