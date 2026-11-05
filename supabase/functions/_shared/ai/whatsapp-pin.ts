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

// O áudio transcrito e a pontuação do celular trazem "Sim, 7391." e "🎤 Sim. 7391". Sem isto, a 1ª palavra ("sim,")
// não é aprovação e a frase ia ao modelo com o PIN. Só a forma exata: "sim, mas 7391" e "sim 7391 reais" ficam como estão.
const SIM_COM_PIN = /^\s*🎤?\s*"?\s*sim[\s,.;:!-]+(\d{3,8})[\s.!"]*$/iu;

/** "Sim, 7391." e "🎤 Sim. 7391" viram "sim 7391". O resto volta igual. */
export function normalizarSimComPin(texto: string): string {
  const m = SIM_COM_PIN.exec(texto);
  return m ? `sim ${m[1]}` : texto;
}

const MAX_CANDIDATOS = 30;

/** Os números do texto com tamanho de PIN, inteiros ou com os dígitos separados ("7 3 9 1"). */
function candidatosAPin(texto: string): string[] {
  const inteiros = texto.match(/(?<!\d)\d{3,8}(?!\d)/g) ?? [];
  const separados = (texto.match(/(?<!\d)\d(?:[\s.-]\d){2,7}(?!\d)/g) ?? []).map((t) => t.replace(/\D/g, ""));
  return [...new Set([...inteiros, ...separados])].slice(0, MAX_CANDIDATOS);
}

/**
 * Há um PIN válido solto no texto? Retorno (05/11/2026): é a última barreira antes do modelo, depois do bloco de
 * confirmação. Nunca conta como tentativa errada: quem chama só deixa de repassar o texto.
 */
export async function pinNoTexto(texto: string, stored: string | null | undefined): Promise<boolean> {
  if (!stored) return false;
  for (const candidato of candidatosAPin(texto)) {
    if (await verifyPin(candidato, stored)) return true;
  }
  return false;
}
