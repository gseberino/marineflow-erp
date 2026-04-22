export function maskCPF(value: string): string {
  const digits = value.replace(/\D/g, '').slice(0, 11);
  if (digits.length <= 3) return digits;
  if (digits.length <= 6) return `${digits.slice(0,3)}.${digits.slice(3)}`;
  if (digits.length <= 9) return `${digits.slice(0,3)}.${digits.slice(3,6)}.${digits.slice(6)}`;
  return `${digits.slice(0,3)}.${digits.slice(3,6)}.${digits.slice(6,9)}-${digits.slice(9,11)}`;
}

export function maskCNPJ(value: string): string {
  const digits = value.replace(/\D/g, '').slice(0, 14);
  if (digits.length <= 2) return digits;
  if (digits.length <= 5) return `${digits.slice(0,2)}.${digits.slice(2)}`;
  if (digits.length <= 8) return `${digits.slice(0,2)}.${digits.slice(2,5)}.${digits.slice(5)}`;
  if (digits.length <= 12) return `${digits.slice(0,2)}.${digits.slice(2,5)}.${digits.slice(5,8)}/${digits.slice(8)}`;
  return `${digits.slice(0,2)}.${digits.slice(2,5)}.${digits.slice(5,8)}/${digits.slice(8,12)}-${digits.slice(12,14)}`;
}

export function maskCPFCNPJ(value: string): string {
  const digits = value.replace(/\D/g, '');
  if (digits.length <= 11) return maskCPF(value);
  return maskCNPJ(value);
}

export function maskPhone(value: string): string {
  const digits = value.replace(/\D/g, '').slice(0, 11);
  if (digits.length === 0) return '';
  if (digits.length <= 2) return `(${digits}`;
  if (digits.length <= 6) return `(${digits.slice(0,2)}) ${digits.slice(2)}`;
  if (digits.length <= 10) return `(${digits.slice(0,2)}) ${digits.slice(2,6)}-${digits.slice(6)}`;
  return `(${digits.slice(0,2)}) ${digits.slice(2,7)}-${digits.slice(7,11)}`;
}

export function maskCEP(value: string): string {
  const digits = value.replace(/\D/g, '').slice(0, 8);
  if (digits.length <= 5) return digits;
  return `${digits.slice(0,5)}-${digits.slice(5)}`;
}

/**
 * Máscara monetária estilo "caixa registradora" no padrão BR.
 * - Aceita apenas dígitos (remove qualquer outro caractere).
 * - Os 2 últimos dígitos são os centavos.
 * - Separador decimal: vírgula. Separador de milhar: ponto.
 * Ex.: "19990" -> "199,90" ; "1299900" -> "12.999,00"
 */
export function maskMoney(value: string | number | null | undefined): string {
  if (value === null || value === undefined || value === '') return '';
  const digits = String(value).replace(/\D/g, '');
  if (!digits) return '';
  const padded = digits.padStart(3, '0');
  const intPart = padded.slice(0, -2).replace(/^0+(?=\d)/, '');
  const decPart = padded.slice(-2);
  const intWithThousands = intPart.replace(/\B(?=(\d{3})+(?!\d))/g, '.');
  return `${intWithThousands},${decPart}`;
}

/**
 * Converte string mascarada (ou número) em float.
 * Ex.: "1.299,90" -> 1299.9 ; "199,90" -> 199.9
 */
export function parseMoney(value: string | number | null | undefined): number {
  if (value === null || value === undefined || value === '') return 0;
  if (typeof value === 'number') return isFinite(value) ? value : 0;
  const digits = String(value).replace(/\D/g, '');
  if (!digits) return 0;
  return parseInt(digits, 10) / 100;
}

/**
 * Formata um número (float) na máscara monetária BR para exibição em inputs.
 * Ex.: 199.9 -> "199,90"
 */
export function formatMoneyFromNumber(n: number | null | undefined): string {
  if (n === null || n === undefined || !isFinite(Number(n))) return '';
  if (Number(n) === 0) return '';
  const cents = Math.round(Number(n) * 100);
  return maskMoney(String(cents));
}

export function isValidCPF(value: string): boolean {
  const digits = value.replace(/\D/g, '');
  if (digits.length !== 11) return false;
  if (/^(\d)\1{10}$/.test(digits)) return false;
  let sum = 0;
  for (let i = 0; i < 9; i++) sum += parseInt(digits[i]) * (10 - i);
  let rev = 11 - (sum % 11);
  if (rev === 10 || rev === 11) rev = 0;
  if (rev !== parseInt(digits[9])) return false;
  sum = 0;
  for (let i = 0; i < 10; i++) sum += parseInt(digits[i]) * (11 - i);
  rev = 11 - (sum % 11);
  if (rev === 10 || rev === 11) rev = 0;
  return rev === parseInt(digits[10]);
}

export function isValidCNPJ(value: string): boolean {
  const digits = value.replace(/\D/g, '');
  if (digits.length !== 14) return false;
  if (/^(\d)\1{13}$/.test(digits)) return false;
  const calc = (d: string, weights: number[]) =>
    weights.reduce((s, w, i) => s + parseInt(d[i]) * w, 0);
  const mod = (n: number) => { const r = n % 11; return r < 2 ? 0 : 11 - r; };
  const w1 = [5,4,3,2,9,8,7,6,5,4,3,2];
  const w2 = [6,5,4,3,2,9,8,7,6,5,4,3,2];
  return mod(calc(digits, w1)) === parseInt(digits[12]) &&
         mod(calc(digits, w2)) === parseInt(digits[13]);
}

export function isValidPhone(value: string): boolean {
  const digits = value.replace(/\D/g, '');
  return digits.length === 10 || digits.length === 11;
}

/**
 * Normaliza telefone para formato internacional (somente dígitos, com DDI).
 * Regras:
 * - Remove tudo que não é dígito.
 * - Remove prefixo "00" de discagem internacional, se houver.
 * - Se já parece ter DDI (12+ dígitos), retorna como está.
 * - Se tem 10 ou 11 dígitos (formato BR sem DDI), prefixa com o DDI default (55).
 * - Se tem 8 ou 9 dígitos (sem DDD), não há como adivinhar DDD/DDI: retorna apenas os dígitos.
 * - Vazio retorna string vazia.
 */
export function normalizePhoneE164(value: string | null | undefined, defaultCountryCode = '55'): string {
  if (!value) return '';
  let digits = String(value).replace(/\D/g, '');
  if (!digits) return '';
  // Remove prefixo internacional "00"
  if (digits.startsWith('00')) digits = digits.slice(2);
  // Já tem DDI (BR é 13 com 9º dígito, 12 sem; outros países variam) — assume internacional
  if (digits.length >= 12) return digits;
  // Formato BR completo (DDD + número): 10 ou 11 dígitos → prefixa DDI
  if (digits.length === 10 || digits.length === 11) return `${defaultCountryCode}${digits}`;
  // Caso ambíguo (curto demais) — devolve só os dígitos
  return digits;
}

