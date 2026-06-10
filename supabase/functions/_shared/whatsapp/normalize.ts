/**
 * Canonical phone normalizer shared by all WhatsApp providers.
 *
 * Rules (Brazil-centric, DDI default 55):
 *  - Strip non-digits and @s.whatsapp.net / @g.us suffixes (Evolution webhooks)
 *  - Strip leading "00" international prefix
 *  - If already ≥12 digits, assume DDI is present and return as-is
 *  - If 10 or 11 digits (DDD + number without DDI), prepend countryCode
 *  - Otherwise return the raw digits unchanged
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
    .replace(/\D/g, "");
  if (!digits) return "";
  if (digits.startsWith("00")) digits = digits.slice(2);
  if (digits.length >= 12) return digits;
  if (digits.length === 10 || digits.length === 11) {
    return `${countryCode}${digits}`;
  }
  return digits;
}
