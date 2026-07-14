// Helpers do canal WhatsApp do AI Operator usados na tela de gestão de usuários.
//
// IMPORTANTE: estas duas funções precisam produzir EXATAMENTE o mesmo resultado que o
// backend, senão o funcionário nunca é reconhecido / o PIN nunca confere.
//  - normalizeWhatsappPhone espelha `normalizePhoneNumber` de
//    supabase/functions/_shared/whatsapp/normalize.ts (o webhook casa app_users por
//    phone_normalized == normalizePhoneNumber(telefone recebido)).
//  - hashPin espelha `hashPin` de supabase/functions/_shared/ai/whatsapp-pin.ts
//    (SHA-256 com salt aleatório, formato "<salt>:<hash>"). O hash é gerado aqui (admin
//    confiável define o PIN de outro usuário) para não precisar de um endpoint dedicado.

/** Espelha normalizePhoneNumber do backend (Brasil, DDI padrão 55). */
export function normalizeWhatsappPhone(raw: string, countryCode = '55'): string {
  if (!raw) return '';
  let digits = String(raw)
    .replace(/@s\.whatsapp\.net/g, '')
    .replace(/@g\.us/g, '')
    .replace(/@lid/g, '')
    .replace(/\D/g, '');
  if (!digits) return '';
  if (digits.startsWith('00')) digits = digits.slice(2);
  if (digits.length === 10 || digits.length === 11) {
    digits = `${countryCode}${digits}`;
  }
  // Celular brasileiro sem o 9º dígito (12 dígitos: 55 + DDD + 8).
  if (digits.length === 12 && digits.startsWith('55')) {
    const numberPart = digits.slice(4);
    if (/^[6-9]/.test(numberPart)) {
      digits = `${digits.slice(0, 4)}9${numberPart}`;
    }
  }
  return digits;
}

/** Um telefone normalizado é "utilizável" pelo canal se casa com o formato que o webhook espera. */
export function isUsableWhatsappPhone(normalized: string): boolean {
  return normalized.startsWith('55') && (normalized.length === 12 || normalized.length === 13);
}

async function sha256Hex(input: string): Promise<string> {
  const data = new TextEncoder().encode(input);
  const digest = await crypto.subtle.digest('SHA-256', data);
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

/** Gera o valor a gravar em app_users.ai_whatsapp_pin_hash. Espelha o backend. */
export async function hashPin(pin: string): Promise<string> {
  const salt = crypto.randomUUID();
  const hash = await sha256Hex(`${salt}:${pin}`);
  return `${salt}:${hash}`;
}
