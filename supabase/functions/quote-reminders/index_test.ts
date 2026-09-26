import { assert } from "https://deno.land/std@0.224.0/assert/mod.ts";

// Guarda da decisão do dono de 26/09/2026: a rotina quote-reminders NÃO rejeita orçamento.
//
// Ela rejeitava em silêncio (sem audit_log) todo orçamento com 7 dias de criação, inclusive
// os aprovados aguardando sinal — R$ 133 mil em 23-24/09. O vencimento virou aviso (R19 do
// task-automations). Este teste lê o CÓDIGO (sem comentários) e falha se alguém devolver a
// expiração para cá: é mais barato que descobrir de novo pelo dinheiro sumindo do funil.

const fonte = Deno.readTextFileSync(new URL("./index.ts", import.meta.url));
// Só código: os comentários explicam a história e citam 'rejected' de propósito.
const codigo = fonte.replace(/\/\*[\s\S]*?\*\//g, "").replace(/\/\/.*$/gm, "");

Deno.test("quote-reminders não marca orçamento como rejeitado", () => {
  assert(!/rejected/.test(codigo), "a rotina voltou a gravar 'rejected' — vencimento é aviso (R19), não rejeição");
});

Deno.test("quote-reminders não lê mais quote_expiry_days nem mexe em 'aguardando sinal'", () => {
  assert(!/quote_expiry_days/.test(codigo), "quote_expiry_days voltou a ser usado");
  assert(!/awaiting_deposit/.test(codigo), "a rotina voltou a olhar orçamentos aguardando sinal");
});
