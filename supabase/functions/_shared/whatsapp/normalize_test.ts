// Tests for normalizePhoneNumber
// Run: deno test supabase/functions/_shared/whatsapp/normalize_test.ts
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { normalizePhoneNumber } from "./normalize.ts";

Deno.test("empty string returns empty", () => {
  assertEquals(normalizePhoneNumber(""), "");
});

Deno.test("number with DDI already present (≥12 digits) is returned as-is", () => {
  assertEquals(normalizePhoneNumber("5547999999999"), "5547999999999");
});

Deno.test("11-digit number (DDD+9+number, no DDI) gets 55 prepended", () => {
  assertEquals(normalizePhoneNumber("47999999999"), "5547999999999");
});

Deno.test("10-digit mobile (DDD+8 digits) gets 55 prepended and 9th digit inserted", () => {
  // 4799999999 → 554799999999 (12) → mobile (starts 9) → 5547999999999 (13)
  assertEquals(normalizePhoneNumber("4799999999"), "5547999999999");
});

Deno.test("12-digit BR mobile without 9th digit gets the 9 inserted", () => {
  // Real Evolution senderPn case: 554799159654 → 5547999159654
  assertEquals(normalizePhoneNumber("554799159654"), "5547999159654");
});

Deno.test("12-digit BR landline (subscriber starts 2-5) is left unchanged", () => {
  // 553133334444 → DDD 31 + 33334444 (starts 3) → not a mobile → no 9 inserted
  assertEquals(normalizePhoneNumber("553133334444"), "553133334444");
});

Deno.test("@lid suffix is stripped (LID is not a phone, digits returned as-is)", () => {
  assertEquals(normalizePhoneNumber("113408678621372@lid"), "113408678621372");
});

Deno.test("leading 00 international prefix is stripped", () => {
  assertEquals(normalizePhoneNumber("005547999999999"), "5547999999999");
});

Deno.test("@s.whatsapp.net suffix is stripped before normalizing", () => {
  assertEquals(normalizePhoneNumber("5547999999999@s.whatsapp.net"), "5547999999999");
});

Deno.test("@g.us group JID suffix is stripped", () => {
  // Long group IDs (≥12 digits) are returned after stripping non-digits
  assertEquals(normalizePhoneNumber("120363000000000000@g.us"), "120363000000000000");
});

Deno.test("non-digit characters are stripped (formatted phone)", () => {
  assertEquals(normalizePhoneNumber("+55 (47) 9-9999-9999"), "5547999999999");
});

Deno.test("custom country code is applied when DDI is absent", () => {
  // 11-digit number with countryCode "1" (US)
  assertEquals(normalizePhoneNumber("12125551234", "1"), "112125551234");
});

Deno.test("short number (< 10 digits) is returned as raw digits", () => {
  // Insufficient length — cannot reliably determine country; return digits unchanged
  assertEquals(normalizePhoneNumber("12345"), "12345");
});
