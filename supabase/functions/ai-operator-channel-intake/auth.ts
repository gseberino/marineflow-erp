// Validação fail-closed do channel intake. Isolado para teste unitário direto
// pelo Vitest (sem precisar de runtime Deno).

export function safeEqual(a: string, b: string): boolean {
  if (typeof a !== "string" || typeof b !== "string") return false;
  if (a.length !== b.length) return false;
  let mismatch = 0;
  for (let i = 0; i < a.length; i++) mismatch |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return mismatch === 0;
}

export type IntakeAuthResult =
  | { ok: true }
  | { ok: false; status: 403 | 503; error: string };

export function validateIntakeAuth(
  configuredSecret: string | undefined | null,
  providedHeader: string | undefined | null
): IntakeAuthResult {
  const secret = (configuredSecret ?? "").trim();
  // Sem secret no ambiente → função inerte. Retorna 503.
  if (!secret) return { ok: false, status: 503, error: "intake disabled: AI_OPERATOR_INTAKE_TOKEN not configured" };

  const provided = (providedHeader ?? "").trim();
  if (!provided || !safeEqual(provided, secret)) {
    return { ok: false, status: 403, error: "forbidden" };
  }
  return { ok: true };
}
