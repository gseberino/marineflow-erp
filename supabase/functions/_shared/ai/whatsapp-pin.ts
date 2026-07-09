// Hash/verificação do PIN de aprovação de ações high-risk via WhatsApp
// (ai_users.ai_whatsapp_pin_hash). SHA-256 com salt aleatório por hash, formato
// "<salt>:<hash>" num único campo texto — sem dependência externa (usa só
// crypto.subtle, disponível nativamente no runtime Deno das Edge Functions).
// O telefone já é uma autenticação fraca; o PIN é uma segunda camada só pra ações
// high-risk, não pretende ter a força de uma senha de conta.

async function sha256Hex(input: string): Promise<string> {
  const data = new TextEncoder().encode(input);
  const digest = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

/** Gera o valor a gravar em ai_whatsapp_pin_hash. Usado pela UI de settings (Fase 6). */
export async function hashPin(pin: string): Promise<string> {
  const salt = crypto.randomUUID();
  const hash = await sha256Hex(`${salt}:${pin}`);
  return `${salt}:${hash}`;
}

/** Compara um PIN em texto puro contra o valor gravado. */
export async function verifyPin(pin: string, stored: string | null | undefined): Promise<boolean> {
  if (!stored) return false;
  const [salt, hash] = stored.split(":");
  if (!salt || !hash) return false;
  const candidate = await sha256Hex(`${salt}:${pin}`);
  return candidate === hash;
}
