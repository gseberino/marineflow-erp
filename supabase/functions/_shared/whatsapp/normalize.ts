/**
 * Canonical phone normalizer shared by all WhatsApp providers.
 *
 * Rules (Brazil-centric, DDI default 55):
 *  - Strip non-digits and @s.whatsapp.net / @g.us / @lid suffixes (Evolution webhooks)
 *  - Strip leading "00" international prefix
 *  - If 10 or 11 digits (DDD + number without DDI), prepend countryCode
 *  - If 12 digits and Brazilian mobile (55 + DDD + 8 digits starting 6-9),
 *    insert the 9th digit → 13 digits (matches legacy whatsapp-webhook behavior,
 *    so inbound numbers match stored client records)
 *  - Otherwise return the digits as-is
 *
 * Supersedes the four divergent implementations found in the codebase
 * (normalizePhone in whatsapp-webhook, normalizePhoneE164 in masks.ts,
 *  inline replace(/\D/g,'') in use-zapi-send, and others).
 */
export function normalizePhoneNumber(
  raw: string,
  countryCode = "55",
): string {
  if (!raw) return "";
  let digits = String(raw)
    .replace(/@s\.whatsapp\.net/g, "")
    .replace(/@g\.us/g, "")
    .replace(/@lid/g, "")
    .replace(/\D/g, "");
  if (!digits) return "";
  if (digits.startsWith("00")) digits = digits.slice(2);
  if (digits.length === 10 || digits.length === 11) {
    digits = `${countryCode}${digits}`;
  }
  // Brazilian mobile sent without the 9th digit (12 digits: 55 + DDD + 8).
  // If the subscriber part starts with 6-9 it's a mobile → insert the 9.
  if (digits.length === 12 && digits.startsWith("55")) {
    const numberPart = digits.slice(4);
    if (/^[6-9]/.test(numberPart)) {
      digits = `${digits.slice(0, 4)}9${numberPart}`;
    }
  }
  return digits;
}
